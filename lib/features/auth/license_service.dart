/// م135 — خدمة الترخيص (المرحلة ٥ من مشروع التراخيص).
///
///  القرار: هل يُسمح للمستخدم بدخول التطبيق؟ ثلاث حقائق تتضافر:
///    ١) حمولة verify_license من الخادم (status/enforce/expires/server_time…).
///    ٢) التخبئة المحلية لفترة سماحٍ دون اتصال (offline grace) — فالعيادة
///       تعمل بلا إنترنت أياماً، لكن لا للأبد: بعد النافذة يُطلب التحقق.
///    ٣) دفاع تلاعب الساعة: نخزّن آخر «وقت خادمٍ» موقَّتاً رأيناه؛ فإن رجعت
///       ساعة الجهاز خلفه بوضوح فتلك محاولةُ تمديدٍ بتزوير التاريخ ⇒ حجب.
///
///  الإجبار علمٌ خادمي (gate.enforce): بينما هو false يُسمح دائماً (الوضع
///  الحالي) فلا يتغيّر شيءٌ على المستخدمين. حين يُفعَّل: يُحجب المنتهي/
///  المحظور/المجمَّد/بلا اشتراك، ويُعاد للتفعيل.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import '../../data/db/local_db.dart';
import '../../data/sync/transport.dart' show LicenseTransport;

/// حالة الاشتراك كما يراها العميل بعد الحسم.
enum LicenseGateResult {
  allowed, // ادخل
  needsActivation, // منتهٍ/بلا اشتراك ⇒ شاشة التفعيل
  frozen, // جمّدته الإدارة
  banned, // حظرته الإدارة
  offlineExpired, // انقطع الاتصال وتجاوزنا فترة السماح
  clockTampered, // رجعت ساعة الجهاز خلف آخر وقت خادمٍ موقَّت
  deviceLimit, // تجاوز عدد الأجهزة المسموح (المرحلة ج) — يقرّره الخادم
}

/// لقطة الترخيص المحسومة (للعرض والقرار).
class LicenseSnapshot {
  const LicenseSnapshot({
    required this.result,
    required this.status,
    required this.planCode,
    required this.enforce,
    required this.expiresAt,
    required this.fromCache,
    this.features = const {},
    this.deviceAllowed = true,
  });
  final LicenseGateResult result;
  final String status;
  final String planCode;
  final bool enforce;
  final DateTime? expiresAt;
  final bool fromCache; // حُسمت من التخبئة (بلا اتصال)؟

  /// المزايا الفعّالة من حمولة verify_license (max_clinics/max_devices/…)
  /// — مصدر حدود الواجهة. المرحلة ب تقرأ max_clinics منها.
  final Map<String, Object?> features;

  /// هل عدد أجهزة الحساب ضمن الحد؟ (يحسبه الخادم في verify_license) — م ج.
  final bool deviceAllowed;

  bool get allowed => result == LicenseGateResult.allowed;

  /// حد العيادات الفعّال — 0 يعني بلا حدّ (غير معرّف).
  int get maxClinics => int.tryParse('${features['max_clinics'] ?? ''}') ?? 0;

  /// حد الأجهزة الفعّال — 0 يعني بلا حدّ.
  int get maxDevices => int.tryParse('${features['max_devices'] ?? ''}') ?? 0;
}

const _kCache = 'license.cache'; // آخر حمولة verify_license (JSON)
const _kCacheAt = 'license.cache_at'; // مللي عند آخر تحقق ناجح (ساعة الجهاز)
const _kLastServer = 'license.last_server_ms'; // آخر server_time موقَّت رأيناه

class LicenseService {
  // البارامتر باسم `cloud` عام للمنادي والحقل خاص — التجاهل مقصود.
  LicenseService(this._db, {LicenseTransport? cloud, DateTime Function()? now})
    // ignore: prefer_initializing_formals
    : _cloud = cloud,
      _now = now ?? DateTime.now;

  final LocalDb _db;
  final LicenseTransport? _cloud;
  final DateTime Function() _now;

  String? _readMeta(String k) {
    final row = _db.queryFirst('SELECT value FROM metadata WHERE key = ?', [k]);
    final v = '${row?['value'] ?? ''}';
    return v.isEmpty ? null : v;
  }

  void _writeMeta(String k, String v) => _db.execute(
    "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
    "VALUES (?, ?, datetime('now'))",
    [k, v],
  );

  Map<String, Object?> get _cache {
    final raw = _readMeta(_kCache);
    if (raw == null) return const {};
    try {
      final m = jsonDecode(raw);
      return m is Map ? m.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// فترة السماح دون اتصال (يوم) — من حمولة الخادم المخبَّأة (grace_days)،
  /// وإلا الافتراضي ٧ (يطابق license.grace_days على الخادم).
  int get _graceDays {
    final g = _cache['grace_days'];
    final n = g is num ? g.toInt() : int.tryParse('$g') ?? 0;
    return n > 0 ? n : 7;
  }

  /// حمولة الجهاز لـverify_license/activate_code.
  Map<String, Object?> _device() => {
    'device_id': _db.deviceId,
    'platform': 'android',
    'app_version': _appVersion,
    // المرحلة ج — إثراء الجهاز لإدارته من اللوحة. os_version من dart:io بلا
    // اعتمادية (يغطي «إصدار أندرويد»). model/brand يملؤهما تعزيزٌ لاحق
    // (device_info_plus) إن لزم — والبنية تدعمهما أصلاً.
    'os_version': _osVersion(),
  };

  static String _osVersion() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return '';
    }
  }

  String _appVersion = '';
  set appVersion(String v) => _appVersion = v;

  /// خبّئ حمولة خادمٍ ناجحة + اختم وقتها ووقت الخادم (لكشف التلاعب).
  void _store(Map<String, Object?> payload) {
    _writeMeta(_kCache, jsonencodeSafe(payload));
    _writeMeta(_kCacheAt, '${_now().millisecondsSinceEpoch}');
    final st = DateTime.tryParse('${payload['server_time'] ?? ''}');
    if (st != null) {
      final prev = int.tryParse(_readMeta(_kLastServer) ?? '') ?? 0;
      final ms = st.millisecondsSinceEpoch;
      if (ms > prev) _writeMeta(_kLastServer, '$ms');
    }
  }

  /// الحسم من حمولةٍ (حيّة أو مخبَّأة).
  LicenseGateResult _classify(Map<String, Object?> p, {required bool cached}) {
    final enforce = p['enforce'] == true;
    if (!enforce) return LicenseGateResult.allowed; // الإجبار مطفأ

    final status = '${p['status'] ?? 'none'}';
    if (status == 'banned') return LicenseGateResult.banned;
    if (status == 'frozen') return LicenseGateResult.frozen;

    // انتهاء فعلي بالتاريخ (حتى لو بقيت الحالة active في التخبئة).
    final exp = DateTime.tryParse('${p['expires_at'] ?? ''}');
    final expired = exp != null && exp.isBefore(_effectiveNow());
    if (status == 'expired' || expired) {
      return LicenseGateResult.needsActivation;
    }
    if (status == 'active' || status == 'trial') {
      // المرحلة ج — حد الأجهزة: الخادم يقرّره خلف مفتاحه (device_block يكون
      // true فقط حين enforce_devices مفعّل وعدد الأجهزة تجاوز الحد). فالعميل
      // يطيعه دون قرارٍ محلي — لا حجب جديد حتى يقرّره المالك.
      if (p['device_block'] == true) return LicenseGateResult.deviceLimit;
      return LicenseGateResult.allowed;
    }
    return LicenseGateResult.needsActivation; // none/غير معروف
  }

  /// «الآن» المقاوم للتلاعب: أكبر ساعة الجهاز وآخر وقت خادمٍ رأيناه — فلا
  /// يفيد إرجاعُ الساعة للوراء في تمديد اشتراكٍ منتهٍ.
  DateTime _effectiveNow() {
    final dev = _now();
    final lastMs = int.tryParse(_readMeta(_kLastServer) ?? '') ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return dev.isAfter(last) ? dev : last;
  }

  /// كشف تلاعب الساعة: ساعة الجهاز أقدم من آخر وقت خادمٍ بأكثر من يومٍ
  /// كامل (هامش للمناطق الزمنية والانحراف الطبيعي).
  bool _clockTampered() {
    final lastMs = int.tryParse(_readMeta(_kLastServer) ?? '') ?? 0;
    if (lastMs == 0) return false;
    final dev = _now().millisecondsSinceEpoch;
    return dev < lastMs - 24 * 3600 * 1000;
  }

  /// القرار الكامل: يحاول الخادم؛ فإن تعذّر سقط للتخبئة ضمن السماح.
  Future<LicenseSnapshot> evaluate() async {
    // ١) تلاعب الساعة يُحسم أولاً — لا يُنقذه اتصالٌ ولا تخبئة.
    if (_clockTampered()) {
      return _snap(LicenseGateResult.clockTampered, _cache, cached: true);
    }

    // ٢) المحاولة الحيّة.
    final cloud = _cloud;
    if (cloud != null) {
      try {
        final p = await cloud.verifyLicense(_device());
        if (p.isNotEmpty) {
          _store(p);
          return _snap(_classify(p, cached: false), p, cached: false);
        }
      } catch (_) {
        /* نسقط للتخبئة */
      }
    }

    // ٣) بلا اتصال (أو بلا سحابة): التخبئة ضمن فترة السماح.
    final cache = _cache;
    if (cache.isEmpty) {
      // بلا سحابة أصلاً (وضع محلي) ⇒ اسمح؛ ومع سحابةٍ بلا تخبئةٍ بعد،
      // لا نحجب أول إقلاعٍ أوفلاين (فشل آمن، والإجبار يُحسم أول اتصال).
      return _snap(LicenseGateResult.allowed, const {
        'enforce': false,
      }, cached: true);
    }
    if (cache['enforce'] != true) {
      return _snap(LicenseGateResult.allowed, cache, cached: true);
    }
    final atMs = int.tryParse(_readMeta(_kCacheAt) ?? '') ?? 0;
    final ageDays = (_now().millisecondsSinceEpoch - atMs) / (24 * 3600 * 1000);
    if (atMs > 0 && ageDays > _graceDays) {
      return _snap(LicenseGateResult.offlineExpired, cache, cached: true);
    }
    return _snap(_classify(cache, cached: true), cache, cached: true);
  }

  /// تفعيل بكود — يعيد لقطةً محسومة (مسموحة عند النجاح).
  Future<LicenseSnapshot> activate(String code) async {
    final cloud = _cloud;
    if (cloud == null) {
      throw const LicenseException('التفعيل يتطلّب اتصالاً بالخادم.');
    }
    try {
      final p = await cloud.activateCode(code.trim(), _device());
      if (p.isEmpty) throw const LicenseException('ردٌّ فارغ من الخادم.');
      _store(p);
      return _snap(_classify(p, cached: false), p, cached: false);
    } on LicenseException {
      rethrow;
    } catch (e) {
      // ترجمة أخطاء الخادم الشائعة لعربيةٍ مفهومة.
      final s = '$e';
      final msg = s.contains('invalid activation code')
          ? 'الكود غير صحيح.'
          : s.contains('already used or revoked')
          ? 'الكود مستخدَم أو مُبطَل.'
          : s.contains('rate limited')
          ? 'محاولات كثيرة — انتظر قليلاً ثم أعد المحاولة.'
          : 'تعذّر التفعيل: $s';
      throw LicenseException(msg);
    }
  }

  LicenseSnapshot _snap(
    LicenseGateResult r,
    Map<String, Object?> p, {
    required bool cached,
  }) => LicenseSnapshot(
    result: r,
    status: '${p['status'] ?? 'none'}',
    planCode: '${p['plan_code'] ?? ''}',
    enforce: p['enforce'] == true,
    expiresAt: DateTime.tryParse('${p['expires_at'] ?? ''}'),
    fromCache: cached,
    features: (p['features'] as Map?)?.cast<String, Object?>() ?? const {},
    deviceAllowed: p['device_allowed'] != false,
  );

  /// حد العيادات من آخر حمولة مخبَّأة (متزامن، بلا شبكة) — 0 = بلا حدّ.
  /// تستعمله الواجهات لفرض الحدّ دون نداءٍ إضافي.
  int cachedMaxClinics() {
    final f = _cache['features'];
    if (f is Map) return int.tryParse('${f['max_clinics'] ?? ''}') ?? 0;
    return 0;
  }

  /// مسح تخبئة الترخيص (تبديل حساب).
  void reset() {
    for (final k in [_kCache, _kCacheAt, _kLastServer]) {
      _db.execute('DELETE FROM metadata WHERE key = ?', [k]);
    }
  }
}

/// ترميز JSON آمن (لا يرمي على قيمٍ غير قابلة للترميز — يُسقطها).
String jsonencodeSafe(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '{}';
  }
}

class LicenseException implements Exception {
  const LicenseException(this.message);
  final String message;
  @override
  String toString() => message;
}
