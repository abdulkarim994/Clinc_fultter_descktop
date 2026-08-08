/// خط أنابيب صور الأشعة السحابي — نقل image.service (مسار الرفع الحقيقي)
/// وxray-delete-queue.service:
///
///  • تصريف الرفع المعلق: لكل صف xrays بحالة pending — رفعٌ يعيد المفتاح
///    الفعلي الذي سكّه العامل (قد يختلف عن المؤقت)، **يُحجز فوراً** في
///    البيانات الوصفية كي لا تكرر أي محاولة لاحقة الرفع (إصلاح التكرار
///    الموثق في الأصل)، ثم تحقق-قبل-التنظيف (HEAD معلوماتي + مقارنة SHA-256
///    الكاملة؛ **التعارض القاطع وحده يُفشل** ويبقي العنصر معلقاً)، ثم إعادة
///    تخطيط: بايتات وصفّ ومصغرة تحت المفتاح الفعلي + شاهدة الصف المؤقت +
///    علامة «استُبدل» + إعادة تخطيط config عبر معالج قابل للحقن (نظير
///    setXrayKeyRemapHandler).
///  • حارسا الحذف والاستبدال (دائمان في metadata بسقف 5000): يصفّيان القراءة
///    كي لا «يبعث» جهاز قديم مفتاحاً محذوفاً عبر دمج الإعدادات.
///  • طابور حذف R2: حذفٌ أوفلاين يُصفّ ويُصرَّف عند الاتصال؛ 404/410 نجاح.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../../data/cloud/r2_client.dart' show XrayRemote;
import '../../data/db/local_db.dart';
import '../../data/sync/db_sync.dart' show getMetaValue, setMetaValue;
import '../../data/repositories/repositories.dart';
import 'storage_meter.dart' show StorageMeter;
import 'xray_store.dart';

const _deletedGuardKey = 'dental_deleted_xray_keys';
const _supersededKey = 'dental_superseded_xray_keys';
const _pendingDeletesKey = 'dental_xray_pending_deletes';
const _reservedPrefix = 'xray.upload.reserved.';
const _guardMax = 5000;

List<String> _readList(LocalDb db, String key) {
  try {
    final raw = '${getMetaValue(db, key) ?? ''}';
    if (raw.isEmpty) return [];
    final arr = jsonDecode(raw);
    return arr is List ? [for (final k in arr) '$k'] : [];
  } catch (_) {
    return [];
  }
}

void _writeList(LocalDb db, String key, List<String> arr) {
  var out = arr;
  if (out.length > _guardMax) out = out.sublist(out.length - _guardMax);
  setMetaValue(db, key, jsonEncode(out));
}

// ── حارسا الحذف والاستبدال ─────────────────────────────────────────────────

void markXrayDeleted(LocalDb db, String key) {
  if (key.isEmpty) return;
  final set = {..._readList(db, _deletedGuardKey), key};
  _writeList(db, _deletedGuardKey, set.toList());
}

void markXraySuperseded(LocalDb db, String key) {
  if (key.isEmpty) return;
  final set = {..._readList(db, _supersededKey), key};
  _writeList(db, _supersededKey, set.toList());
}

bool isXrayDeleted(LocalDb db, String key) =>
    _readList(db, _deletedGuardKey).contains(key) ||
    _readList(db, _supersededKey).contains(key);

/// filterDeletedKeys — تصفية القراءة ضد الحارسين (لا يُبعث محذوف أبداً).
List<String> filterDeletedKeys(LocalDb db, List<String> keys) {
  final deleted = _readList(db, _deletedGuardKey).toSet();
  final superseded = _readList(db, _supersededKey).toSet();
  return [
    for (final k in keys)
      if (!deleted.contains(k) && !superseded.contains(k)) k,
  ];
}

// ── طابور حذف R2 ───────────────────────────────────────────────────────────

void enqueuePendingDelete(LocalDb db, String key) {
  if (key.isEmpty || key.startsWith('data:')) return;
  final q = _readList(db, _pendingDeletesKey);
  if (!q.contains(key)) _writeList(db, _pendingDeletesKey, [...q, key]);
}

List<String> pendingDeletes(LocalDb db) => _readList(db, _pendingDeletesKey);

class XrayPipeline {
  XrayPipeline({
    required this.db,
    required this.repos,
    required this.store,
    required this.remote,
    this.remapConfigKey,
    this.verifyChecksum = true,
    this.meter,
  });

  final LocalDb db;
  final Repositories repos;
  final XrayStore store;
  final XrayRemote remote;

  /// م134 — مقياس الحصة (المرحلة ٣). اختياري: بلا سحابة يبقى null فلا حجب
  /// ولا محاسبة. حين يُمرَّر: يحرس الحصة قبل الرفع ويعدّ عند نجاحه بالبايتات
  /// الفعلية المرفوعة والمفتاح النهائي (بعد أي إعادة تسمية).
  final StorageMeter? meter;

  /// نظير setXrayKeyRemapHandler: (tempKey, serverKey, patientName) —
  /// يعيد تخطيط config.patientXrays/xrayMeta؛ فشله يبقي العنصر معلقاً
  /// (لا نترك الإعدادات تشير لمفتاح 404 على الأجهزة الأخرى).
  final void Function(String tempKey, String serverKey, String patientName)?
  remapConfigKey;

  final bool verifyChecksum;

  String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  String? _reserved(String id) {
    final v = getMetaValue(db, '$_reservedPrefix$id');
    final s = '${v ?? ''}';
    return s.isEmpty ? null : s;
  }

  /// verifyRemoteObject — HEAD معلوماتي + مقارنة SHA-256 كاملة عند التفعيل؛
  /// **القاطع وحده يفشل**، وكل تعذّرٍ «غير حاسم» ينجح (لا فقد صورة لعطل شبكة).
  Future<({bool ok, String reason})> _verify(
    String key,
    Uint8List localBytes,
  ) async {
    try {
      await remote.headObject(key); // معلوماتي فقط
    } catch (_) {
      /* HEAD غير مدعوم ⇒ غير حاسم */
    }
    if (verifyChecksum) {
      try {
        final blob = await remote.fetchBytes(key, thumb: false);
        if (blob == null) return (ok: true, reason: 'fetch-failed');
        if (_sha256Hex(blob) != _sha256Hex(localBytes)) {
          return (ok: false, reason: 'checksum-mismatch');
        }
        return (ok: true, reason: 'verified');
      } catch (_) {
        return (ok: true, reason: 'verify-error');
      }
    }
    return (ok: true, reason: 'head-only');
  }

  /// تصريف رفعة معلقة واحدة — _reconcilePendingItem حرفي الدلالات.
  /// يعيد true عند اكتمال التوفيق (لم يعد معلقاً).
  Future<bool> reconcileOne(Row row) async {
    final id = '${row['id']}';
    // إعادة قراءة الحالة الموثوقة (منع التكرار): قد يكون اكتمل في مسار آخر.
    final current = repos.xrays.getById(id);
    if (current == null || '${current['upload_status']}' != 'pending') {
      return true;
    }

    final bytes = store.fileBytes(id) ?? store.thumbnailBytes(id);
    if (bytes == null) return false; // لا بايتات محلية — يبقى معلقاً

    final patient = '${current['patient_name'] ?? ''}';

    var serverKey = _reserved(id);
    if (serverKey == null) {
      // م134 — حارس الحصة قبل الرفع: صورةٌ تتجاوز الحصة تبقى معلقةً بلا
      // رفع (لا نتخطّى حدّ R2 ولو امتلأ الطابور دون اتصال). الحجز يعني أنها
      // رُفعت سابقاً فلا تُحجب رجعياً.
      final m = meter;
      if (m != null && !m.check(bytes.length).allowed) {
        return false; // يبقى معلقاً حتى تحرَّر مساحة أو تُرقّى الحصة
      }
      serverKey = await remote.upload(
        bytes,
        id,
        patientName: patient,
        fileName: id.split('/').last,
        contentType: 'image/jpeg',
      );
      // الحجز الفوري — أي محاولة لاحقة تعيد استخدام المفتاح نفسه.
      setMetaValue(db, '$_reservedPrefix$id', serverKey);
      // محاسبة الاستهلاك بالبايتات الفعلية والمفتاح النهائي (رفعٌ جديد فقط،
      // لا عند إعادة استخدام حجزٍ سابق) + تبليغ الخادم أفضل جهد.
      m?.addUpload(serverKey.isEmpty ? id : serverKey, bytes.length);
      unawaited(m?.reportUp() ?? Future<void>.value());
    }
    final storageKey = serverKey.isEmpty ? id : serverKey;

    final v = await _verify(storageKey, bytes);
    if (!v.ok) {
      throw Exception(
        'upload verification failed (${v.reason}); keeping pending',
      );
    }

    final checksum = _sha256Hex(bytes);
    if (storageKey != id) {
      // بايتات ومصغرة وصف تحت المفتاح الفعلي.
      store.writeFileBytes(storageKey, bytes);
      final thumb = repos.xrays.getThumbnail(id);
      repos.xrays.upsertLocal({
        'id': storageKey,
        'patient_name': patient,
        'file_key': storageKey,
        'thumbnail_data': thumb,
        'upload_status': 'uploaded',
        'checksum': checksum,
        'created_at': current['created_at'],
        'clinic_id': current['clinic_id'],
        'patient_id': current['patient_id'],
      });
      // إعادة تخطيط الإعدادات أولاً — فشلها يبقي العنصر معلقاً.
      if (remapConfigKey != null) {
        remapConfigKey!(id, storageKey, patient);
      }
      // الصف المؤقت: شاهدة + علامة استُبدل (لا يظهر مكرراً مكسوراً أبداً).
      repos.xrays.delete(id);
      markXraySuperseded(db, id);
      store.deleteFile(id);
    } else {
      repos.xrays.markUploaded(id, checksum: checksum);
    }
    setMetaValue(db, '$_reservedPrefix$id', null);
    return true;
  }

  /// تصريف كل الرفع المعلق — فشل عنصرٍ لا يوقف البقية.
  Future<({int uploaded, int kept})> drainUploads() async {
    var uploaded = 0, kept = 0;
    for (final row in repos.xrays.getPendingUploads()) {
      try {
        (await reconcileOne(row)) ? uploaded++ : kept++;
      } catch (_) {
        kept++;
      }
    }
    return (uploaded: uploaded, kept: kept);
  }

  /// تصريف طابور الحذف — 404/410 نجاح داخل العميل؛ الفشل يبقي المفتاح.
  ///
  /// م142 — بعد أي حذفٍ ناجح من R2 نُبلّغ الخادم بقياسنا الحالي (reportUp)
  /// كي يعكس استهلاك الخادم النقصَ فور تأكيد حذف الكائن (كان الطابور يحذف
  /// من R2 بلا إعادة تبليغ فيبقى استهلاك الخادم متضخّماً حتى تقرير لاحق).
  Future<({int deleted, int kept})> drainDeletes() async {
    var deleted = 0;
    final remaining = <String>[];
    for (final key in pendingDeletes(db)) {
      try {
        await remote.delete(key);
        deleted++;
      } catch (_) {
        remaining.add(key);
      }
    }
    _writeList(db, _pendingDeletesKey, remaining);
    if (deleted > 0) {
      unawaited(meter?.reportUp() ?? Future<void>.value());
    }
    return (deleted: deleted, kept: remaining.length);
  }
}

/// مسترجِع المصغرات عند الطلب — نقل دلالات getThumbnailUrl +
/// restoreThumbnailFromR2 حرفياً:
///   • مفتاح بلا مصغرة محلية ⇒ جلب خلفي من R2 (المصغرة أولاً ثم النسخة
///     الكاملة تراجعاً — وتُولَّد منها مصغرة) وتخزين محلي بحت.
///   • الفشل يعلّم المفتاح فاشلاً (بلاطة حمراء) ولا يعاود تلقائياً؛
///   • عودة الاتصال تمنح الفاشل «فرصة جديدة» (يُمحى من المجموعة فيُعاد
///     الجلب عند أول عرض) — نفس فقرة isOnline في getThumbnailUrl.
class XrayThumbRestorer {
  XrayThumbRestorer({
    required this.store,
    required this.remote,
    this.onChange,
    this.retryCooldown = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final XrayStore store;
  final XrayRemote remote;

  /// نبضة تغيّر — تربطها الواجهة بعدّاد نسخة (نظير xrayVersion).
  final void Function()? onChange;

  /// م22 — تهدئة إعادة المحاولة: كان `request` يمسح علامة الفشل عند **كل
  /// إعادة بناء** وهو متصل فيعيد الجلب فوراً — فتتناوب البلاطة سبينراً
  /// دائماً ولا تظهر بلاطة الفشل إطلاقاً على شبكة معطوبة/بالغة البطء
  /// («بتضل شاشة تحميل»). الآن المفتاح الفاشل يبقى فاشلاً (بلاطة حمراء)
  /// حتى تنقضي التهدئة ثم يعاد جلبه تلقائياً.
  final Duration retryCooldown;
  final DateTime Function() _now;

  final Set<String> _inFlight = <String>{};
  final Map<String, DateTime> _failedAt = <String, DateTime>{};
  bool _lastOnline = false;

  bool isFailed(String key) => _failedAt.containsKey(key);
  bool isLoading(String key) => _inFlight.contains(key);

  /// نقطة دخول الواجهة عند غياب المصغرة محلياً (getThumbnailUrl):
  /// **حافة** عودة الاتصال (أوفلاين ← أونلاين) تمنح فرصة فورية — حرفية
  /// الأصل؛ أما وهو متصل باستمرار فالمفتاح الفاشل يعاد بعد التهدئة فقط
  /// (إعادة البناء المستمرة كانت تمسح الفشل فيدور السبينر أبداً).
  void request(String key, {required bool online}) {
    final reconnect = online && !_lastOnline;
    _lastOnline = online;
    final failedAt = _failedAt[key];
    if (online &&
        failedAt != null &&
        (reconnect || _now().difference(failedAt) >= retryCooldown)) {
      _failedAt.remove(key);
    }
    if (_failedAt.containsKey(key) || _inFlight.contains(key)) return;
    _inFlight.add(key);
    // جلب خلفي — لا انتظار في البناء.
    _restore(key);
  }

  Future<void> _restore(String key) async {
    try {
      // المصغرة أولاً؛ تراجعاً النسخة الكاملة (restoreThumbnailFromR2).
      var thumb = await remote.fetchBytes(key, thumb: true);
      if (thumb == null || thumb.isEmpty) {
        final full = await remote.fetchBytes(key, thumb: false);
        if (full == null || full.isEmpty) {
          throw Exception('empty');
        }
        // النسخة الكاملة تُحفظ للملف المحلي وتُولَّد منها مصغرة
        // (_generateThumbIfMissing).
        store.writeFileBytes(key, full);
        thumb = full;
      }
      store.writeThumbBytes(key, thumb);
      _failedAt.remove(key);
    } catch (_) {
      _failedAt[key] = _now();
    } finally {
      _inFlight.remove(key);
      onChange?.call();
    }
  }
}

/// ============================================================================
///  م24 — طابور رفع الصور التلقائي: توأم startUploadQueueListener حرفياً
/// ============================================================================
///
///  الأصل (image.service.js): نقطة دخول **أحادية الرحلة** لمعالجة طابور
///  الرفع كله — المستمعون المتزامنون (مستمع عودة الاتصال + مؤقت الثلاثين
///  ثانية + الزر اليدوي + «رفع الكل» من الإعدادات) يتشاركون التشغيلة
///  نفسها ولا يبدأ ثانٍ عملاً موازياً (جذر إصلاح سباق الرفع المزدوج).
///  البدء يصرف فوراً ثم يجدول المؤقت الدوري؛ الإيقاف عند الخروج/فقد
///  وضع السحابة.
class XrayUploadQueue {
  XrayUploadQueue({
    required this.drain,
    this.interval = const Duration(seconds: 30),
  });

  /// وحدة التصريف (رفعٌ ثم حذف معلق ثم نبضة واجهة) — تُحقن من providers.
  final Future<void> Function() drain;

  /// فاصل إعادة المحاولة الدوري — 30000ms حرفياً.
  final Duration interval;

  Timer? _timer;
  Future<void>? _run;

  bool get running => _timer != null;

  /// idempotent — نظير حارس `if (_onlineListener) return` في الأصل.
  void start() {
    if (_timer != null) return;
    drainNow();
    _timer = Timer.periodic(interval, (_) => drainNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// أحادية الرحلة: نداء أثناء تشغيلةٍ جارية يعيد وعدها نفسه.
  Future<void> drainNow() {
    final existing = _run;
    if (existing != null) return existing;
    final run = _drainOnce();
    _run = run;
    return run;
  }

  Future<void> _drainOnce() async {
    try {
      await drain();
    } catch (_) {
      /* أفضل جهد — الدورة القادمة تعيد */
    } finally {
      _run = null;
    }
  }
}
