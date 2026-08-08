/// ============================================================================
///  Sync transport — the injectable server boundary
/// ============================================================================
///
///  The Vue engine called `supabase.rpc('apply_changes' | 'pull_changes')`
///  directly. The Dart port routes BOTH RPCs through this interface so:
///    • the engine is fully testable against an in-memory fake server
///      (the two-device convergence proof), and
///    • M5 plugs in a SupabaseTransport with zero engine changes.
///
///  Wire contracts are verbatim from push.js / pull.js:
///
///  apply_changes(ops):
///    op  = `{ op_id: "<entity>:<id>:<hlc>", entity, action, row }`
///    ack = { results: [ { op_id, id, server_seq } ] }
///
///  pull_changes(p_lower, p_page_txid, p_page_seq, p_upto, p_limit):
///    row = { entity, id, payload, clinic_id, _hlc, _deleted, _origin,
///            server_seq, txid }
///    out = { rows, safe }   // safe = commit-safe txid watermark (pinned)
library;

typedef JsonMap = Map<String, Object?>;

class WireOp {
  const WireOp({
    required this.opId,
    required this.entity,
    required this.action,
    required this.row,
    required this.pushedHlc,
  });

  final String opId;
  final String entity;
  final String action; // 'upsert' | 'delete'
  final JsonMap row;

  /// Client-side only (never sent): the HLC at push time, used to clear
  /// `_dirty` conditionally on ack.
  final String pushedHlc;

  JsonMap toWire() => {
    'op_id': opId,
    'entity': entity,
    'action': action,
    'row': row,
  };
}

class ApplyAck {
  const ApplyAck({required this.opId, required this.id, this.serverSeq});

  final String opId;
  final String id;
  final int? serverSeq;
}

class PullRow {
  const PullRow({
    required this.entity,
    required this.id,
    required this.payload,
    this.clinicId,
    this.hlc,
    required this.deleted,
    this.origin,
    required this.serverSeq,
    required this.txid,
  });

  final String entity;
  final String id;
  final JsonMap payload;
  final Object? clinicId;
  final String? hlc;
  final bool deleted;
  final String? origin;
  final int serverSeq;
  final int txid;
}

class PullPage {
  const PullPage({
    required this.rows,
    required this.safe,
    this.horizon,
    this.archiveHorizon,
  });

  final List<PullRow> rows;

  /// Commit-safe txid watermark for this drain window.
  final int safe;

  /// م65 — أفق الضغط الآمن لكل الأجهزة: أدنى `server_seq` طبّقته **كل**
  /// أجهزة الحساب. الشواهد الأقدم منه بلغت الجميع فيجوز تقليمها.
  ///
  /// اختياري عمداً: الخوادم التي لا ترجعه (أو النسخ الأقدم) تتركه `null`
  /// فيبقى الأفق صفراً ويظل الضغط معطّلاً — وهو الفشل الآمن الصحيح، إذ
  /// تقليم شاهدة لم تبلغ جهازاً بعدُ يعني بعث صف محذوف.
  final int? horizon;

  /// م73 — **أفق الأرشيف**: أعلى `txid` حُذف فعلاً من الخادم بالأرشفة
  /// الباردة. لا يُخلط بـ[horizon] أعلاه: ذاك أدنى مؤشر مطبَّق (لضغط
  /// الشواهد)، وهذا أعلى ما اختفى (لكشف الفجوة).
  ///
  /// الجهاز الذي يجد مؤشره **تحت** هذا الرقم يعلم أن صفوفاً أُرشفت قبل أن
  /// يصلها، فيستدعي الاسترجاع من تلقائه. غيابه (خادم أقدم) ⇒ null ⇒ لا
  /// كشف فجوة ولا استرجاع تلقائي — فشل آمن يبقي السلوك القديم.
  final int? archiveHorizon;
}

abstract interface class SyncTransport {
  Future<List<ApplyAck>> applyChanges(List<WireOp> ops);

  Future<PullPage> pullChanges({
    required int lower,
    int? pageTxid,
    required int pageSeq,
    int? upto,
    required int limit,
  });
}

/// م134 — قناة حصة التخزين (المرحلة ٣). منفصلة عن SyncTransport كي يبقى
/// النقلُ المزيّف (الوضع المحلي) وخوادمُ أقدمُ سليمةً بلا تنفيذٍ لها؛ من
/// يدعمها يُنفّذها (SupabaseTransport)، ومن لا فالمقياس يعمل محلياً وحده.
abstract interface class StorageTransport {
  /// {used_bytes, file_count, quota_bytes} للمستخدم الحالي.
  Future<Map<String, Object?>> getMyStorage();

  /// تبليغ قياس الجهاز — يعيد الحالة المحدَّثة.
  Future<Map<String, Object?>> reportMyStorage(int usedBytes, int fileCount);
}

/// م135 — قناة الترخيص (المرحلة ٥). التحقّق من الاشتراك وتفعيله بالكود.
/// كلاهما محصورٌ بـauth.uid() داخل الدالة على الخادم.
abstract interface class LicenseTransport {
  /// verify_license(device) — يعيد حمولة الترخيص الكاملة:
  /// {enforce, status, plan_code, features, expires_at, server_time,
  ///  session_epoch, trial{enabled,days}, device_allowed, storage{...}}.
  Future<Map<String, Object?>> verifyLicense(Map<String, Object?> device);

  /// activate_code(code, device) — يعيد حمولة verify_license بعد التفعيل،
  /// أو يرمي عند كودٍ غير صالح/مستخدَم/محدود المعدّل.
  Future<Map<String, Object?>> activateCode(
    String code,
    Map<String, Object?> device,
  );

  /// المرحلة د: get_my_subscription — تفاصيل إضافية لشاشة الاشتراك:
  /// {status, plan_code, plan_name, trial, starts_at, expires_at,
  ///  code_prefix, last_verified, last_sync, device_count}.
  Future<Map<String, Object?>> getMySubscription();

  /// المرحلة د: list_public_plans — الباقات النشطة للمقارنة (code/name/features).
  Future<List<Map<String, Object?>>> listPublicPlans();
}

/// المرحلة هـ — قناة الإشعارات داخل التطبيق (بلا Firebase/دفع). ثلاثة نداءات
/// خادميّة محصورةٌ بـauth.uid() داخل دوالّها. منفصلةٌ عن SyncTransport كي يبقى
/// النقلُ المزيّف (الوضع المحلي) وخوادمُ أقدمُ سليمةً بلا تنفيذٍ لها؛ من
/// يدعمها يُنفّذها (SupabaseTransport)، ومن لا فالمستدعي يتحقق `t is
/// NotificationsTransport` ويصمت محلياً.
abstract interface class NotificationsTransport {
  /// get_my_notifications() — مصفوفة الإشعارات غير المقروءة للمستخدم الحالي،
  /// كلٌّ `{id,title,body,kind,data,created_at}` و`data`={image_url?,
  /// action_label?, action_url?}. الأقدم أولاً.
  Future<List<Map<String, Object?>>> getMyNotifications();

  /// mark_notification_read(p_id) — يعلّم إشعاراً مقروءاً (self).
  Future<void> markNotificationRead(String id);

  /// get_app_update() — {enabled bool, version text, url text, notes text}.
  Future<Map<String, Object?>> getAppUpdate();
}
