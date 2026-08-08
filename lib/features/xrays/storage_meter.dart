/// م134 — مقياس حصة التخزين (المرحلة ٣ من مشروع التراخيص).
///
///  لماذا خريطة أحجام لا مسحُ ملفات: التطبيق **يحذف النسخة الكاملة محلياً
///  بعد رفعها** (يبقي المصغّرة فقط) توفيراً لمساحة الجهاز — فمسح الملفات
///  المحلية يُنقص الاستهلاك كذباً. الحقيقة أن ما رُفع إلى R2 باقٍ، فنمسك
///  خريطة {مفتاح → بايتات} في `metadata` (device-local، توأم عدّادات
///  النسخ)، والاستهلاك = مجموع قيمها. فالحذف نقصٌ دقيق لا تقريبي، والعدّاد
///  دائم الاتساق مع الخريطة (لا انجراف). ويعمل بلا اتصال؛ والحصة تُقرأ من
///  الخادم وتُخبَّأ بفترة سماح.
///
///  المحاسبة عند **نجاح الرفع** بالمفتاح النهائي (بعد أي إعادة تسمية
///  temp→server) والبايتات الفعلية المرفوعة — فلا خطأ إعادة تسمية ولا شحن
///  صورةٍ معلّقة لم تصل R2 بعد.
library;

import 'dart:convert';

import '../../data/db/local_db.dart';
import '../../data/sync/transport.dart' show StorageTransport;

const _kSizes = 'xray.storage.sizes'; // JSON {key: bytes} — مساهمة هذا الجهاز
const _kQuota = 'xray.storage.quota_bytes';
const _kQuotaAt = 'xray.storage.quota_fetched_at';
// إصلاح تبديل الحساب: الأساس المرجعي لاستهلاك الحساب **كاملاً** كما يراه
// الخادم (عبر كل الأجهزة). خريطة الأحجام أعلاه محليّة لهذا الجهاز فقط —
// وحساب جديد على الجهاز نفسه يبدأ بخريطةٍ فارغة (استهلاك محلي = صفر) ولو
// كان ممتلئاً على الخادم. فنبذر هذا الأساس عند الدخول ونحسب الاستهلاك
// الفعّال = الأكبر بين (الأساس الخادمي، المجموع المحلي) — فلا يُفتح الرفع
// لحسابٍ ممتلئ لمجرد أن جهازه الحالي لم يرفع شيئاً بعد.
const _kServerUsed = 'xray.storage.server_used';

/// الحصة الافتراضية بلا سحابة أو قبل أول جلب — 200 م.ب (أرضية الخادم نفسها)
/// فلا يُمنع الرفع بحصةٍ صفرية خاطئة، ولا يُفتح بلا حدٍّ فيُفاجأ المستخدم.
const int kDefaultQuotaBytes = 200 * 1024 * 1024;

/// تنسيق حجمٍ بالبايت إلى نص عربي مقروء (عشرية واحدة).
String humanBytesAr(int bytes) {
  if (bytes < 1024) return '$bytes ب';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} ك.ب';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} م.ب';
  return '${(mb / 1024).toStringAsFixed(2)} غ.ب';
}

/// عتبات التحذير — نفس عتبات اللوحة (80/90/100).
enum StorageLevel { ok, warn80, warn90, full }

/// حصيلة فحصٍ قبل الرفع.
class StorageCheck {
  const StorageCheck({
    required this.allowed,
    required this.usedBytes,
    required this.quotaBytes,
    required this.addBytes,
  });
  final bool allowed;
  final int usedBytes, quotaBytes, addBytes;

  int get afterBytes => usedBytes + addBytes;
  int get remainingBytes => (quotaBytes - usedBytes).clamp(0, quotaBytes);
}

class StorageMeter {
  // البارامتر باسم `cloud` (اسمٌ عام للمنادي) والحقل خاص — التجاهل مقصود.
  // ignore: prefer_initializing_formals
  StorageMeter(this._db, {StorageTransport? cloud}) : _cloud = cloud;

  final LocalDb _db;
  final StorageTransport? _cloud;

  // ── خريطة الأحجام (مصدر الحقيقة) ──────────────────────────────────────────
  Map<String, int> _sizes() {
    final row = _db.queryFirst('SELECT value FROM metadata WHERE key = ?', [
      _kSizes,
    ]);
    final raw = '${row?['value'] ?? ''}';
    if (raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return {
          for (final e in m.entries)
            '${e.key}': int.tryParse('${e.value}') ?? 0,
        };
      }
    } catch (_) {
      /* تالف ⇒ فارغ */
    }
    return {};
  }

  void _saveSizes(Map<String, int> m) => _db.execute(
    "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
    "VALUES (?, ?, datetime('now'))",
    [_kSizes, jsonEncode(m)],
  );

  int _readInt(String key) {
    final row = _db.queryFirst('SELECT value FROM metadata WHERE key = ?', [
      key,
    ]);
    return int.tryParse('${row?['value'] ?? ''}') ?? 0;
  }

  void _writeInt(String key, int v) => _db.execute(
    "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
    "VALUES (?, ?, datetime('now'))",
    [key, '$v'],
  );

  /// مجموع مساهمة هذا الجهاز (خريطة الأحجام المحلية).
  int get _localSum {
    var sum = 0;
    for (final v in _sizes().values) {
      sum += v;
    }
    return sum;
  }

  /// الأساس المرجعي من الخادم (استهلاك الحساب كاملاً) — يُبذَر عند الدخول.
  int get _serverUsed => _readInt(_kServerUsed);

  /// الاستهلاك الفعّال = الأكبر بين الأساس الخادمي والمجموع المحلي. فحسابٌ
  /// ممتلئ على الخادم يظهر ممتلئاً فور الدخول ولو كان جهازه لم يرفع بعد،
  /// وجهازٌ رفع أكثر ممّا بُذِر (تقارير معلّقة) لا يُنقِص استهلاكه كذباً.
  int get usedBytes {
    final local = _localSum;
    final server = _serverUsed;
    return server > local ? server : local;
  }

  int get fileCount => _sizes().length;

  /// الحصة المخبَّأة — الافتراضية إن لم تُجلب بعد.
  int get quotaBytes {
    final q = _readInt(_kQuota);
    return q > 0 ? q : kDefaultQuotaBytes;
  }

  double get ratio =>
      quotaBytes <= 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);

  StorageLevel get level {
    final r = ratio;
    if (r >= 1.0) return StorageLevel.full;
    if (r >= 0.9) return StorageLevel.warn90;
    if (r >= 0.8) return StorageLevel.warn80;
    return StorageLevel.ok;
  }

  /// هل يُسمح بإضافة [addBytes]؟ الحجب عند بلوغ/تجاوز 100٪ فقط — 80/90
  /// تحذيرٌ لا منع.
  StorageCheck check(int addBytes) {
    final used = usedBytes;
    final quota = quotaBytes;
    return StorageCheck(
      allowed: used + addBytes <= quota,
      usedBytes: used,
      quotaBytes: quota,
      addBytes: addBytes,
    );
  }

  /// تسجيل رفعٍ ناجح بمفتاحه النهائي وبايتاته الفعلية (idempotent: إعادة
  /// المفتاح نفسه لا تضاعف). يزيد الأساس الخادمي بالفارق كي يتراكم الرفع
  /// المتتالي فوق ما بُذِر من الخادم (لا يُعاد ضبطه إلا بتحقّقٍ جديد).
  void addUpload(String key, int bytes) {
    if (key.isEmpty || bytes <= 0) return;
    final m = _sizes();
    final prev = m[key] ?? 0;
    m[key] = bytes;
    _saveSizes(m);
    final delta = bytes - prev;
    if (delta != 0) {
      _writeInt(_kServerUsed, (_serverUsed + delta).clamp(0, 1 << 62));
    }
  }

  /// حذف صورةٍ بمفتاحها — نقصٌ دقيق (يزيل حجمها من الخريطة وينقص الأساس).
  void removeKey(String key) {
    final m = _sizes();
    final removed = m.remove(key);
    if (removed != null) {
      _saveSizes(m);
      _writeInt(_kServerUsed, (_serverUsed - removed).clamp(0, 1 << 62));
    }
  }

  /// جلب الحصة **والاستهلاك الخادمي** وتخبئتهما (أفضل جهد — يبقى المخبَّأ
  /// عند الفشل). بذر الأساس الخادمي هنا هو ما يجعل حساباً ممتلئاً يظهر
  /// ممتلئاً فور الدخول على جهازٍ جديد. يُستدعى عند الدخول وقبل الرفع.
  Future<void> refreshQuota() async {
    final cloud = _cloud;
    if (cloud == null) return;
    try {
      final s = await cloud.getMyStorage();
      final q = int.tryParse('${s['quota_bytes'] ?? ''}') ?? 0;
      if (q > 0) {
        _writeInt(_kQuota, q);
        _writeInt(_kQuotaAt, DateTime.now().millisecondsSinceEpoch);
      }
      // الأساس الخادمي: نبذره متى ورد المفتاح (حتى لو صفراً — يمحو أساساً
      // بائتاً لحسابٍ سابق). لا يُنقِص المجموع المحلي (usedBytes = الأكبر).
      if (s.containsKey('used_bytes')) {
        final u = int.tryParse('${s['used_bytes'] ?? ''}') ?? 0;
        _writeInt(_kServerUsed, u < 0 ? 0 : u);
      }
    } catch (_) {
      /* يبقى المخبَّأ — فشل آمن */
    }
  }

  /// اسمٌ دلاليّ أوضح للنداء عند الدخول/التبديل (نفس refreshQuota).
  Future<void> refreshFromServer() => refreshQuota();

  /// تبليغ الخادم بقياسنا الحالي (أفضل جهد).
  Future<void> reportUp() async {
    final cloud = _cloud;
    if (cloud == null) return;
    try {
      await cloud.reportMyStorage(usedBytes, fileCount);
    } catch (_) {
      /* أفضل جهد */
    }
  }

  /// إعادة ضبطٍ كامل (تبديل حساب) — يُستدعى مع مسح بيانات الحساب.
  void reset() {
    for (final k in [_kSizes, _kQuota, _kQuotaAt, _kServerUsed]) {
      _db.execute('DELETE FROM metadata WHERE key = ?', [k]);
    }
  }

  /// حالة مُصدَّرة للاختبار/التشخيص.
  String debugJson() => jsonEncode({
    'used': usedBytes,
    'files': fileCount,
    'quota': quotaBytes,
    'ratio': ratio,
    'level': level.name,
  });
}
