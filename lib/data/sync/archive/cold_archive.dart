/// م70 — الأرشفة الباردة التلقائية: نافذة ساخنة على الخادم، والتاريخ الكامل
/// في مكانين (أجهزة العيادة + حزم R2).
///
/// لماذا
/// ─────
/// كلفة Supabase تنمو بلا سقف لأن `sync_rows` يتراكم للأبد، بينما لا يحتاج
/// أي جهاز قائم صفوفاً قديمة من الخادم — المحرك offline-first وكل جهاز
/// يحتفظ بتاريخه كاملاً محلياً. القياس المعملي (دراسة م69): نافذة ساخنة
/// تحوّل الفاتورة من نموٍّ دائم إلى **حالة مستقرة ثابتة**. وم73 قلّصها إلى
/// 90 يوماً بعد بناء حارس الجهاز الغائب: 15.4 ← 8.1 م.ب للحساب.
///
/// التصميم
/// ───────
///   يُؤرشَف : records / xrays (أقدم من 90 يوماً — م73) + appointments الماضية
///             (أقدم من 120 يوماً). شواهد القبور القديمة ضمناً.
///   لا يُؤرشَف أبداً: patients (الهوية) · debts (مال معلّق — حتى المسدَّد
///             خارج النطاق تبسيطاً وأماناً) · settings (حيّ) · prosthetics
///             وqueue_patients (خارج v1).
///   لا يُؤرشَف: صف متسخ (_dirty=1 — تعديل لم يُدفع)، ولا موعد بتاريخ
///             مستقبلي مهما قدُم إنشاؤه.
///
/// خط السير — فشل مغلق في كل خطوة
/// ───────────────────────────────
///   انتقاء محلي ← حزمة NDJSON مضغوطة ← رفع عبر عامل R2 القائم
///   ← **إعادة قراءة الحزمة ومطابقة بصمة SHA-256** ← تحديث فهرس الأرشيف
///   والتحقق منه ← عندئذٍ فقط: RPC `archive_rows` يحذف من الخادم
///   ← تقديم علامة مائية محلية (لا إعادة رفع في الدورات التالية).
///   أي فشل في أي خطوة ⇒ لا حذف إطلاقاً، وإعادة المحاولة لاحقاً آمنة
///   (الحذف الخادمي idempotent، وتكرار حزمة أهون من فقد صف).
///
/// ضمانات الخادم مستقلة عن العميل (0020 + 0022): الملكية، وقائمة الكيانات
/// المسموحة، وأرضية عمر 90 يوماً، و**حارس المؤشر** — لا يُحذف صف لم تبلغه
/// كل الأجهزة النشطة، فجهاز غائب يوقف الأرشفة عند حدّه حتى يعود ويلحق.
///
/// الاسترجاع (جهاز جديد): ينزّل الفهرس ثم الحزم ويرطّب الصفوف عبر
/// `mergeRemoteRow` — مسار السحب نفسه: نظيف (_dirty=0)، يحترم HLC فلا
/// يكتب فوق أحدث محلي، ويطبّق شواهد القبور.
///
/// تعديل صف مؤرشَف من جهاز ما يُحييه upsert في `apply_changes` تلقائياً —
/// سلوك صحيح؛ يُعاد أرشفته حين يقدُم ثانيةً (العلامة المائية تلتقطه لأن
/// _mod الجديد أكبر منها).
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../../cloud/r2_client.dart' show XrayRemote;
import '../../db/local_db.dart';
import '../conflict.dart' show mergeRemoteRow;
import '../context.dart';
import '../db_sync.dart' show getMetaValue, mergeRow, setMetaValue;
import '../engine.dart' show EngineStatus;
import '../pull.dart' show archiveHorizonKey;

/// عقد نداء الأرشفة الخادمي — منفصل عن SyncTransport عمداً كي لا تُكسر
/// المزيّفات القائمة؛ SupabaseTransport ينفذ الاثنين، والوضع المحلي بلا
/// خادم لا ينفذه فتتعطل الميزة تلقائياً (بوابة coldArchiveProvider).
abstract interface class ArchiveTransport {
  /// يطلب حذف الصفوف المذكورة من النافذة الساخنة. يعيد عدد المحذوف فعلاً.
  ///
  /// [callerTxid] مؤشر هذا الجهاز — يدخل حساب حارس الخادم مع مؤشرات بقية
  /// الأجهزة، فلا يُحذف صف لم تبلغه كل الأجهزة النشطة (م73).
  Future<int> archiveRows(List<Map<String, String>> items,
      {required int minAgeDays, int? callerTxid});

  /// م73 — تبليغ مؤشر هذا الجهاز (يومياً). أفضل جهد.
  Future<void> reportSyncState(String deviceId, int cursorTxid);
}

class ArchivePolicy {
  const ArchivePolicy({
    this.recordsDays = 90,
    this.xraysDays = 90,
    this.appointmentsDays = 120,
    this.serverMinAgeDays = 90,
    this.maxRowsPerRun = 5000,
    this.intervalDays = 30,
  });

  /// م73 — النافذة الساخنة **90 يوماً** (كانت 210). القياس: 15.4 ← 8.1
  /// م.ب للحساب ⇒ 31 ← 59 عيادة على الخطة المجانية.
  ///
  /// ولماذا صار التقليص آمناً: النافذة تخصّ **الخادم** لا الجهاز — كل
  /// جهاز يحتفظ بتاريخه كاملاً محلياً (offline-first)، فالطبيب يفتح
  /// مريضاً من سنوات بلا إنترنت. وما كان يخيف — جهاز غائب تُؤرشف صفوف
  /// لم تصله — أغلقه حارس المؤشر الخادمي (المهاجرة 0022): الأرشفة تتوقف
  /// عند أدنى مؤشر بين الأجهزة النشطة وتستأنف حين يعود الغائب ويلحق.
  ///
  /// قابلة للضبط من الإعدادات (90/180/365) — انظر [ColdArchive.windowDays].
  final int recordsDays;
  final int xraysDays;

  /// المواعيد الماضية قيمتها التشغيلية شبه معدومة بعد أشهر — نافذة أقصر.
  final int appointmentsDays;

  /// أرضية الخادم — تُرسَل للـRPC الذي يفرض بنفسه GREATEST(قيمة, 90).
  final int serverMinAgeDays;

  /// سقف صفوف الدورة الواحدة: يحدّ حجم الحزمة (~ميغابايتات قليلة مضغوطة)
  /// والذاكرة؛ الباقي يلتقطه تشغيل تالٍ.
  final int maxRowsPerRun;

  /// أقصى تواتر للتشغيل التلقائي.
  final int intervalDays;
}

class ArchiveRunResult {
  const ArchiveRunResult({
    required this.ok,
    required this.archived,
    this.reason = '',
    this.bundleKey,
    this.bundleBytes = 0,
  });

  final bool ok;
  final int archived;
  final String reason;
  final String? bundleKey;
  final int bundleBytes;
}

class ArchiveRestoreResult {
  const ArchiveRestoreResult({
    required this.ok,
    required this.applied,
    required this.bundles,
    this.skippedBundles = 0,
    this.reason = '',
  });

  final bool ok;
  final int applied;
  final int bundles;
  final int skippedBundles;
  final String reason;
}

/// مفاتيح الحالة في sync_meta (لكل حساب عبر اللاحقة).
String _wmKey(String entity, String uid) => 'archive_wm_${entity}_$uid';
String _lastRunKey(String uid) => 'archive_last_run_$uid';

/// م77 — عدد الحزم الذي يعرف هذا الجهاز أن الفهرس بلغه. مرساة السلامة:
/// فهرسٌ يعود أقصر من هذا العدد **مبتور** لا «جديد».
String _idxCountKey(String uid) => 'archive_idx_bundles_$uid';

/// م77 — تمييز الحالات الثلاث التي كان `null` يبتلعها جميعاً.
enum ArchiveIndexRead { ok, absent, failed }
String _enabledKey(String uid) => 'archive_enabled_$uid';
String _windowKey(String uid) => 'archive_window_days_$uid';
String _reportKey(String uid) => 'archive_report_day_$uid';
String _restoredKey(String uid) => 'archive_auto_restored_$uid';

class ColdArchive {
  ColdArchive({
    required this.ctx,
    required this.remote,
    required this.transport,
    this.policy = const ArchivePolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncContext ctx;
  final XrayRemote remote;
  final ArchiveTransport transport;
  final ArchivePolicy policy;
  final DateTime Function() _now;

  LocalDb get _db => ctx.db;
  String get _uid => _db.getOwnerUid() ?? 'local';

  String get _indexKey => 'archive/$_uid/index.json';

  // ── حالة التفعيل والتوقيت ─────────────────────────────────────────────────

  bool get enabled => '${getMetaValue(_db, _enabledKey(_uid)) ?? ''}' != '0';

  set enabled(bool v) =>
      setMetaValue(_db, _enabledKey(_uid), v ? '1' : '0', _uid);

  int get lastRunMs =>
      int.tryParse('${getMetaValue(_db, _lastRunKey(_uid)) ?? ''}') ?? 0;

  /// م73 — النافذة الفعّالة: إعداد المستخدم إن وُجد، وإلا الافتراضي.
  /// تُقرأ حيّةً عند كل تشغيل فيسري التغيير فوراً بلا إعادة تشغيل.
  int get windowDays {
    final v = int.tryParse('${getMetaValue(_db, _windowKey(_uid)) ?? ''}');
    if (v == null || v < policy.serverMinAgeDays) return policy.recordsDays;
    return v;
  }

  set windowDays(int d) =>
      setMetaValue(_db, _windowKey(_uid), '$d', _uid);

  /// مؤشر هذا الجهاز (آخر txid آمن بلغه السحب).
  int get _cursor =>
      (num.tryParse('${getMetaValue(_db, "sync.cursor.txid") ?? ''}') ?? 0)
          .toInt();

  bool get due =>
      _now().millisecondsSinceEpoch - lastRunMs >
      policy.intervalDays * 24 * 60 * 60 * 1000;

  int _watermark(String entity) =>
      int.tryParse('${getMetaValue(_db, _wmKey(entity, _uid)) ?? ''}') ?? 0;

  // ── الانتقاء ──────────────────────────────────────────────────────────────

  String _dateCutoff(int days) {
    final d = _now().subtract(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// الصفوف المؤهلة، الأقدم أولاً، بسقف الدورة. القواعد في رأس الملف.
  List<({String entity, Row row})> selectEligible() {
    final nowMs = _now().millisecondsSinceEpoch;
    final out = <({String entity, Row row})>[];
    final oc = _db.ownerClause();

    void pick(String entity, int windowDays, {bool requirePastDate = false}) {
      final cutoffMod = nowMs - windowDays * 24 * 60 * 60 * 1000;
      final cutoffDate = _dateCutoff(windowDays);
      final wm = _watermark(entity);
      // ملاحظة _mod > 0: صف بلا _mod (صفر) لا نستطيع إثبات قدمه — يُترك.
      final dateGuard = requirePastDate
          // موعد: تاريخ الحمولة نفسه يجب أن يكون قديماً — لا يكفي قدم
          // آخر تعديل، وإلا أُرشف موعد مستقبلي أُنشئ قبل شهور.
          ? "AND IFNULL(date,'') <> '' AND date <= ?"
          // سجل: التاريخ إن وُجد يجب ألا يكون حديثاً؛ غيابه لا يمنع
          // (قِدم _mod يكفي حينها).
          : "AND (IFNULL(date,'') = '' OR date <= ?)";
      final hasDateCol = entity != 'xrays';
      final rows = _db.query(
        'SELECT * FROM $entity '
        'WHERE IFNULL(_dirty,0) = 0 AND _mod > ? AND _mod <= ? '
        '${hasDateCol ? dateGuard : ''}${oc.sql} '
        'ORDER BY _mod ASC LIMIT ?',
        [
          wm,
          cutoffMod,
          if (hasDateCol) cutoffDate,
          ...oc.params,
          policy.maxRowsPerRun,
        ],
      );
      for (final r in rows) {
        final m = mergeRow(r);
        if (m != null) out.add((entity: entity, row: m));
      }
    }

    final w = windowDays;
    pick('records', w);
    pick('xrays', w);
    pick('appointments', policy.appointmentsDays, requirePastDate: true);

    out.sort((a, b) => (a.row['_mod'] as num? ?? 0)
        .compareTo(b.row['_mod'] as num? ?? 0));
    if (out.length > policy.maxRowsPerRun) {
      out.removeRange(policy.maxRowsPerRun, out.length);
    }
    return out;
  }

  // ── التحزيم ───────────────────────────────────────────────────────────────

  /// صورة السلك للصف — مرآة buildOp في push.dart: الحقول الداخلية لا
  /// تسافر، والمصغّرة تُسقَط **دائماً** من الحزم (الاسترجاع يرطّبها من
  /// العامل عبر `?v=thumb` — مسار _restore القائم).
  Map<String, Object?> wireRow(String entity, Row row) {
    final p = Map<String, Object?>.from(row);
    p.remove('data');
    p.remove('_dirty');
    p.remove('server_seq');
    if (entity == 'xrays') p.remove('thumbnail_data');
    p['id'] = row['id'];
    return p;
  }

  Uint8List buildBundle(List<({String entity, Row row})> items) {
    final lines = [
      for (final it in items)
        jsonEncode({'entity': it.entity, 'row': wireRow(it.entity, it.row)}),
    ];
    return Uint8List.fromList(gzip.encode(utf8.encode(lines.join('\n'))));
  }

  // ── التشغيل ───────────────────────────────────────────────────────────────

  bool _running = false;

  // ── م73: التبليغ اليومي وكشف الفجوة ──────────────────────────────────────

  /// يبلّغ الخادم بمؤشر هذا الجهاز — مرة يومياً تكفي لنافذة بالأشهر،
  /// وتكلفتها نداء واحد (~380 بايت). أفضل جهد: فشله يجعل الخادم يرى
  /// الجهاز أقدمَ مؤشراً فيصبح **أكثر** تحفظاً لا أقل.
  Future<void> reportStateIfDue() async {
    final today = _dateStr(_now());
    if ('${getMetaValue(_db, _reportKey(_uid)) ?? ''}' == today) return;
    try {
      await transport.reportSyncState(ctx.deviceId, _cursor);
      setMetaValue(_db, _reportKey(_uid), today, _uid);
    } catch (_) {/* الدورة التالية تعيد */}
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// كشف الفجوة: مؤشر هذا الجهاز تحت أعلى txid أُرشف ⇒ صفوف اختفت من
  /// الخادم قبل أن تصله. يسترجع تلقائياً **مرة واحدة لكل أفق** (المفتاح
  /// يحفظ الأفق المعالَج) كي لا يتكرر التنزيل كل دورة.
  Future<ArchiveRestoreResult?> restoreIfGap([int? horizonOverride]) async {
    final archiveHorizon = horizonOverride ??
        int.tryParse('${getMetaValue(_db, archiveHorizonKey) ?? ''}');
    if (archiveHorizon == null || archiveHorizon <= 0) return null;
    if (_cursor >= archiveHorizon) return null;
    final done =
        int.tryParse('${getMetaValue(_db, _restoredKey(_uid)) ?? ''}') ?? -1;
    if (done >= archiveHorizon) return null;
    final r = await restore();
    // لا نسجّل إلا عند النجاح الكامل — استرجاع ناقص يجب أن يُعاد.
    if (r.ok) setMetaValue(_db, _restoredKey(_uid), '$archiveHorizon', _uid);
    return r;
  }

  Future<ArchiveRunResult> run({bool manual = false}) async {
    if (_running) {
      return const ArchiveRunResult(
          ok: false, archived: 0, reason: 'أرشفة أخرى جارية');
    }
    _running = true;
    try {
      return await _runInner(manual: manual);
    } finally {
      _running = false;
    }
  }

  Future<ArchiveRunResult> _runInner({required bool manual}) async {
    final items = selectEligible();
    if (items.isEmpty) {
      // «لا شيء مؤهل» نجاحٌ — ويُحدَّث آخر تشغيل كي لا يعاد الفحص يومياً.
      setMetaValue(
          _db, _lastRunKey(_uid), '${_now().millisecondsSinceEpoch}', _uid);
      return const ArchiveRunResult(
          ok: true, archived: 0, reason: 'لا صفوف مؤهلة للأرشفة');
    }

    final bytes = buildBundle(items);
    final digest = sha256.convert(bytes).toString();
    final ts = _now().toUtc();
    final stamp = ts
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first;
    final key = 'archive/$_uid/${stamp}_${items.length}.ndjson.gz';

    // ١) الرفع — عبر عامل R2 القائم نفسه (contentType يمرّره العامل كما هو).
    final String storedKey;
    try {
      storedKey = await remote.upload(bytes, key,
          fileName: key.split('/').last, contentType: 'application/gzip');
    } catch (e) {
      return ArchiveRunResult(
          ok: false, archived: 0, reason: 'فشل رفع الحزمة: $e');
    }

    // ٢) التحقق: إعادة قراءة الحزمة من R2 ومطابقة البصمة — لا ثقة بنجاح
    //    الرفع وحده (درس REVOKE الصامت: تحقق دائماً بعد كل عملية).
    final echo = await remote.fetchBytes(storedKey, thumb: false);
    if (echo == null || sha256.convert(echo).toString() != digest) {
      return const ArchiveRunResult(
          ok: false,
          archived: 0,
          reason: 'الحزمة لم تُقرأ مطابقةً من R2 — لن يُحذف شيء');
    }

    // ٣) الفهرس — خريطة الاسترجاع. تحديثه **قبل** الحذف: حزمة بلا فهرس
    //    قابلة للاكتشاف بالسرد لاحقاً، أما حذف بلا حزمة مفهرسة فمخاطرة.
    final perEntity = <String, int>{};
    for (final it in items) {
      perEntity[it.entity] = (perEntity[it.entity] ?? 0) + 1;
    }
    // م77 — الفشل المغلق يشمل **قراءة** الفهرس أيضاً، لا كتابته وحدها.
    // كان إخفاق القراءة يُقرأ «أول تشغيل» فيُبنى فهرس يتيم فوق السليم ثم
    // تُحذف الصفوف. الآن: لا يُحذف شيء ما لم نقرأ الفهرس بثقة.
    final read = await _fetchIndexGuarded();
    if (read.status == ArchiveIndexRead.failed) {
      return const ArchiveRunResult(
          ok: false,
          archived: 0,
          reason: 'تعذّرت قراءة فهرس الأرشيف بثقة — لن يُحذف شيء. '
              'الحزمة مرفوعة على R2 وإعادة المحاولة لاحقاً آمنة');
    }
    final idx = read.idx ?? {'v': 1, 'bundles': <Object?>[]};
    (idx['bundles'] as List).add({
      'key': storedKey,
      'rows': items.length,
      'entities': perEntity,
      'bytes': bytes.length,
      'sha256': digest,
      'at': ts.toIso8601String(),
    });
    try {
      final idxBytes =
          Uint8List.fromList(utf8.encode(const JsonEncoder().convert(idx)));
      final storedIdx = await remote.upload(idxBytes, _indexKey,
          fileName: 'index.json', contentType: 'application/json');
      final idxEcho = await remote.fetchBytes(storedIdx, thumb: false);
      if (idxEcho == null ||
          sha256.convert(idxEcho) != sha256.convert(idxBytes)) {
        return const ArchiveRunResult(
            ok: false, archived: 0, reason: 'تعذّر تثبيت فهرس الأرشيف');
      }
      // م77 — الفهرس مثبَّت ومُتحقَّق منه: ارفع المرساة المحلية. من هنا
      // فصاعداً أي فهرس أقصر من هذا العدد يُعدّ مبتوراً ويوقف الحذف.
      _rememberBundleCount((idx['bundles'] as List).length);
    } catch (e) {
      return ArchiveRunResult(
          ok: false, archived: 0, reason: 'فشل رفع الفهرس: $e');
    }

    // ٤) الحذف الخادمي — الآن فقط.
    final int deleted;
    try {
      deleted = await transport.archiveRows(
        [
          for (final it in items)
            {'entity': it.entity, 'id': '${it.row['id']}'},
        ],
        minAgeDays: policy.serverMinAgeDays,
        // م73 — مؤشر هذا الجهاز يدخل حارس الخادم مع مؤشرات الأجهزة الأخرى.
        callerTxid: _cursor,
      );
    } catch (e) {
      // الحزمة على R2 والفهرس مثبَّت — إعادة المحاولة لاحقاً آمنة تماماً.
      return ArchiveRunResult(
          ok: false, archived: 0, reason: 'فشل نداء الحذف الخادمي: $e');
    }

    // ٥) تقديم العلامات المائية — بعد اكتمال كل شيء.
    final maxMod = <String, int>{};
    for (final it in items) {
      final m = (it.row['_mod'] as num? ?? 0).toInt();
      if (m > (maxMod[it.entity] ?? 0)) maxMod[it.entity] = m;
    }
    maxMod.forEach((entity, m) {
      if (m > _watermark(entity)) {
        setMetaValue(_db, _wmKey(entity, _uid), '$m', _uid);
      }
    });
    setMetaValue(
        _db, _lastRunKey(_uid), '${_now().millisecondsSinceEpoch}', _uid);

    return ArchiveRunResult(
      ok: true,
      archived: deleted,
      bundleKey: storedKey,
      bundleBytes: bytes.length,
      reason: 'أُرشف ${items.length} صفاً (حذف الخادم $deleted)',
    );
  }

  /// عدد الحزم الذي بلغه الفهرس في آخر مرة رآه هذا الجهاز.
  int get _knownBundleCount =>
      int.tryParse('${getMetaValue(_db, _idxCountKey(_uid)) ?? ''}') ?? 0;

  void _rememberBundleCount(int n) {
    if (n > _knownBundleCount) {
      setMetaValue(_db, _idxCountKey(_uid), '$n', _uid);
    }
  }

  /// م77 — قراءة الفهرس **مع تمييز الفشل عن الغياب**.
  ///
  ///  العلة المُصلَحة
  ///  ──────────────
  ///  كان [_fetchIndex] يُرجع `null` في ثلاث حالات مختلفة جذرياً — «لا فهرس
  ///  بعد» و«فشلت القراءة» و«الفهرس فاسد» — لأن `R2Client.fetchBytes` يبتلع
  ///  كل خطأ ومهلة في `null`. والمستدعي كان يعامل `null` بوصفه «أول تشغيل»
  ///  فيبني فهرساً **يحوي الحزمة الجديدة وحدها**، ويرفعه فوق الفهرس السليم،
  ///  ويجتاز فحص الصدى الذاتي، **ثم يمضي إلى الحذف الخادمي**. فكل حزمة
  ///  أُرشفت سابقاً تصير غير قابلة للوصول من [restore] — وهو المسار الذي
  ///  يعتمد عليه جهاز بديل لاسترجاع كل ما تجاوز نافذة التسعين يوماً.
  ///  والمُطلِق إخفاق شبكة عابر واحد على شبكة عيادة.
  ///
  ///  زعم التوثيق أن الحزمة غير المفهرسة «تُكتشف بالسرد لاحقاً» — وهذا غير
  ///  ممكن: واجهة [XrayRemote] لا تملك دالة سرد أصلاً.
  ///
  ///  التمييز بلا تغيير الواجهة
  ///  ─────────────────────────
  ///  إضافة دالة إلى [XrayRemote] كانت ستكسر خمس مزيّفات في الاختبارات.
  ///  بدلها **مرساتان مستقلتان** تكفيان:
  ///    ١) ذاكرة الجهاز: إن كان يعرف أن الفهرس بلغ حزماً ثم عاد فارغاً أو
  ///       أقصر ⇒ فشل/بتر، مهما قال الطرف البعيد.
  ///    ٢) `headObject`: إن أكّد الخادم وجود الكائن بينما القراءة فارغة
  ///       ⇒ فشل قراءة قطعاً.
  ///  ولا يُعلَن «غياب» إلا حين تصمت المرساتان معاً — وهو الشكل الحقيقي
  ///  لأول تشغيل.
  ///
  ///  والفهرس **الفاسد صار فشلاً أيضاً** لا «ابدأ من جديد»: تحليلٌ متعذّر
  ///  لبايتات موجودة هو آخر ما يبرّر الدهس.
  Future<({ArchiveIndexRead status, Map<String, Object?>? idx})>
      _fetchIndexGuarded() async {
    final expected = _knownBundleCount;
    final raw = await remote.fetchBytes(_indexKey, thumb: false);

    if (raw == null || raw.isEmpty) {
      if (expected > 0) return (status: ArchiveIndexRead.failed, idx: null);
      final head = await remote.headObject(_indexKey);
      // م84 — «غياب» يتطلّب تأكيد الخادم صراحةً (404)، لا مجرّد إخفاق قراءة.
      //
      //  كان الشرط `if (head.ok) → failed; else → absent`، فأي HEAD يُخفق
      //  عابراً (5xx/مهلة/رمز منتهٍ) يُعيد ok:false فيُعلَن «غياب ⇒ أول
      //  تشغيل» على جهازٍ جديد (expected=0) — فيُدهس فهرسٌ سليم على الخادم
      //  وتُيتَّم كل الحزم السابقة. الآن: الوجود المجهول (لا ok ولا notFound)
      //  فشلٌ يُجهض المسار الهدّام، والغياب لا يُعلَن إلا بـ404 صريح.
      if (head.ok || !head.notFound) {
        return (status: ArchiveIndexRead.failed, idx: null);
      }
      return (status: ArchiveIndexRead.absent, idx: null);
    }

    Map<String, Object?>? parsed;
    try {
      final j = jsonDecode(utf8.decode(raw));
      if (j is Map && j['bundles'] is List) {
        parsed = Map<String, Object?>.from(j);
      }
    } catch (_) {/* يُعالَج أدناه بوصفه فشلاً لا بداية جديدة */}
    if (parsed == null) return (status: ArchiveIndexRead.failed, idx: null);

    final got = (parsed['bundles'] as List).length;
    if (got < expected) {
      // الفهرس أقصر مما يعرفه هذا الجهاز ⇒ مبتور أو من كتابة فاشلة سابقة.
      return (status: ArchiveIndexRead.failed, idx: null);
    }
    _rememberBundleCount(got);
    return (status: ArchiveIndexRead.ok, idx: parsed);
  }


  // ── الاسترجاع ────────────────────────────────────────────────────────────

  /// ترطيب جهاز جديد من الأرشيف. يعيد استعمال mergeRemoteRow (مسار السحب):
  /// نظيف، يحترم HLC (لا يكتب فوق أحدث محلي)، ويطبّق شواهد القبور.
  Future<ArchiveRestoreResult> restore() async {
    final read = await _fetchIndexGuarded();
    // م77 — التمييز يهمّ هنا بقدر ما يهمّ في مسار الحذف، ولسبب مختلف:
    // «لا أرشيف لهذا الحساب» رسالةٌ مطمئنة، وقولها لجهاز بديل عجز عن
    // قراءة الفهرس **تضليل**: يظنّ صاحبها أن لا تاريخ ليُسترجَع، بينما
    // التاريخ سليم على R2 والقراءة وحدها أخفقت. الفرق بين «لا شيء هنا»
    // و«تعذّر الوصول» هو الفرق بين قرارين مختلفين تماماً للمالك.
    if (read.status == ArchiveIndexRead.failed) {
      return const ArchiveRestoreResult(
          ok: false,
          applied: 0,
          bundles: 0,
          reason: 'تعذّر قراءة فهرس الأرشيف — لا يعني غياب أرشيف. '
              'تحقّق من الاتصال وعامل R2 ثم أعد المحاولة');
    }
    final idx = read.idx;
    if (idx == null) {
      return const ArchiveRestoreResult(
          ok: true, applied: 0, bundles: 0, reason: 'لا أرشيف لهذا الحساب');
    }
    final bundles = (idx['bundles'] as List).whereType<Map>().toList();
    var applied = 0;
    var skipped = 0;
    for (final b in bundles) {
      final key = '${b['key'] ?? ''}';
      final wantSha = '${b['sha256'] ?? ''}';
      if (key.isEmpty) {
        skipped++;
        continue;
      }
      final raw = await remote.fetchBytes(key, thumb: false);
      if (raw == null ||
          (wantSha.isNotEmpty &&
              sha256.convert(raw).toString() != wantSha)) {
        skipped++; // حزمة مفقودة/فاسدة لا تعطّل البقية — تُبلَّغ عدّاً.
        continue;
      }
      final String text;
      try {
        text = utf8.decode(gzip.decode(raw));
      } catch (_) {
        skipped++;
        continue;
      }
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        try {
          final obj = jsonDecode(line);
          if (obj is! Map) continue;
          final entity = '${obj['entity'] ?? ''}';
          final row = obj['row'];
          if (entity.isEmpty || row is! Map) continue;
          final st = mergeRemoteRow(
              ctx, entity, Map<String, Object?>.from(row));
          if (st != 'noop' && st != 'kept-local') applied++;
        } catch (_) {/* سطر فاسد لا يفسد الاسترجاع */}
      }
    }
    // تحديث الواجهة مسؤولية المستدعي (زر الإعدادات يقرع مزوّدي المراجعة).
    return ArchiveRestoreResult(
      ok: skipped == 0,
      applied: applied,
      bundles: bundles.length,
      skippedBundles: skipped,
      reason: skipped == 0
          ? 'استُرجع $applied صفاً من ${bundles.length} حزمة'
          : 'استُرجع $applied صفاً؛ $skipped حزمة تعذّرت — أعد المحاولة',
    );
  }
}

/// المشغّل التلقائي: يستمع لنهاية دورات المزامنة الناجحة ويشغّل الأرشفة
/// مرة كل [ArchivePolicy.intervalDays] كحد أقصى — بلا مؤقتات خاصة به.
class ArchiveScheduler {
  ArchiveScheduler({required this.archiveOf});

  /// يُقرأ عند كل نبضة (لا يُلتقط مرة) — فتغيير الإعداد/الحساب يسري فوراً،
  /// وnull يعني الوضع المحلي أو R2 غير مضبوط ⇒ لا عمل.
  final ColdArchive? Function() archiveOf;

  bool _busy = false;

  void onEngineStatus(EngineStatus s) {
    if (s.phase != 'complete' || _busy) return;
    final a = archiveOf();
    if (a == null) return;
    _busy = true;
    // خلفي بأفضل جهد — لا ينتظر ولا يفشل دورة المزامنة.
    Future(() async {
      try {
        // ١) التبليغ اليومي بالمؤشر — يعمل حتى لو أُوقفت الأرشفة، فهو ما
        //    يحمي هذا الجهاز من أرشفة جهاز آخر لصفوف لم تصله بعد.
        await a.reportStateIfDue();
        // ٢) كشف الفجوة واسترجاعها تلقائياً (مرة لكل أفق).
        await a.restoreIfGap();
        // ٣) الأرشفة عند الاستحقاق وبشرط التفعيل.
        if (a.enabled && a.due) await a.run();
      } catch (_) {/* التشغيل التالي يعيد المحاولة */} finally {
        _busy = false;
      }
    });
  }
}
