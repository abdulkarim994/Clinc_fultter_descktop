/// ناقل Supabase الحقيقي فوق واجهة SyncTransport — النداءان الحرفيان:
///   POST /rest/v1/rpc/apply_changes  { ops: [...] }
///   POST /rest/v1/rpc/pull_changes   { p_lower, p_page_txid, p_page_seq,
///                                      p_upto, p_limit }
/// بترويسات apikey + Authorization: Bearer (رمز الوصول). عند 401 يُجبَر تحديث
/// الجلسة مرة واحدة ثم يعاد النداء (سلوك supabase-js). المحرك لا يتغير بحرف:
/// الخادم المزيف في الاختبارات أثبت العقد نفسه (0010/0011) وهذا يطابقه.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sync/archive/cold_archive.dart' show ArchiveTransport;
import '../sync/audit_push.dart' show AuditTransport;
import '../sync/retention.dart' show TombstonePurge;
import '../sync/transport.dart';

class TransportException implements Exception {
  TransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'TransportException($statusCode): $message';
}

class SupabaseTransport
    implements
        SyncTransport,
        ArchiveTransport,
        TombstonePurge,
        AuditTransport,
        StorageTransport,
        LicenseTransport,
        NotificationsTransport {
  SupabaseTransport({
    required this.baseUrl,
    required this.anonKey,
    required this.accessToken,
    this.onUnauthorized,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String anonKey;

  /// رمز الوصول الحالي (يُحدَّث استباقياً في خدمة المصادقة).
  final Future<String?> Function() accessToken;

  /// إجبار تحديث الجلسة عند 401 — يعيد الرمز الجديد أو null.
  final Future<String?> Function()? onUnauthorized;

  final http.Client _http;
  final Duration timeout;

  Future<Object?> _rpc(String fn, Map<String, Object?> params) async {
    Future<http.Response> call(String? token) => _http
        .post(
          Uri.parse('$baseUrl/rest/v1/rpc/$fn'),
          headers: {
            'apikey': anonKey,
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode(params),
        )
        .timeout(timeout);

    var res = await call(await accessToken());
    if (res.statusCode == 401 && onUnauthorized != null) {
      final fresh = await onUnauthorized!();
      if (fresh != null && fresh.isNotEmpty) res = await call(fresh);
    }
    // فك UTF-8 صريح من البايتات — حمولات عربية لا تعتمد على ترويسة charset.
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode >= 400) {
      String msg = body;
      try {
        final b = jsonDecode(body);
        if (b is Map) msg = '${b['message'] ?? b['error'] ?? body}';
      } catch (_) {}
      throw TransportException(msg, statusCode: res.statusCode);
    }
    return body.isEmpty ? null : jsonDecode(body);
  }

  /// م71 — الحذف الفعلي لشواهد القبور القديمة (RPC purge_expired القائم
  /// منذ زمن بلا مستدعٍ). يعيد {purged: n}.
  @override
  Future<int> purgeExpired({required int retainDays}) async {
    final data = await _rpc('purge_expired', {'p_retain_days': retainDays});
    if (data is Map) return (data['purged'] as num?)?.toInt() ?? 0;
    return 0;
  }

  /// م70 — نداء الأرشفة الباردة: يطلب حذف صفوف قديمة من النافذة الساخنة.
  /// الخادم يتحقق بنفسه من الملكية والكيانات وأرضية العمر (المهاجرة 0020)
  /// — القيم هنا مجرد طلب، والضمانة خادمية.
  @override
  Future<int> archiveRows(
    List<Map<String, String>> items, {
    required int minAgeDays,
    int? callerTxid,
  }) async {
    final data = await _rpc('archive_rows', {
      'p_items': items,
      'p_min_age_days': minAgeDays,
      // م133 — صيغة العنصر الواعي بالعدم (Dart 3.12) بطلب المحلل.
      'p_caller_txid': ?callerTxid,
    });
    return data is num ? data.toInt() : int.tryParse('$data') ?? 0;
  }

  @override
  Future<List<ApplyAck>> applyChanges(List<WireOp> ops) async {
    final data = await _rpc('apply_changes', {
      'ops': [for (final o in ops) o.toWire()],
    });
    final results = data is Map
        ? (data['results'] as List? ?? const [])
        : const [];
    return [
      for (final r in results.whereType<Map>())
        ApplyAck(
          opId: '${r['op_id']}',
          id: '${r['id']}',
          serverSeq: (r['server_seq'] as num?)?.toInt(),
        ),
    ];
  }

  @override
  Future<PullPage> pullChanges({
    required int lower,
    int? pageTxid,
    required int pageSeq,
    int? upto,
    required int limit,
  }) async {
    final data = await _rpc('pull_changes', {
      'p_lower': lower,
      'p_page_txid': pageTxid,
      'p_page_seq': pageSeq,
      'p_upto': upto,
      'p_limit': limit,
    });
    final map = data is Map ? data : const {};
    final rows = (map['rows'] as List? ?? const []).whereType<Map>();
    return PullPage(
      rows: [
        for (final r in rows)
          PullRow(
            entity: '${r['entity']}',
            id: '${r['id']}',
            payload: r['payload'] is Map
                ? Map<String, Object?>.from(r['payload'] as Map)
                : const {},
            clinicId: r['clinic_id'],
            hlc: r['_hlc'] as String?,
            deleted:
                r['_deleted'] == true ||
                r['_deleted'] == 1 ||
                r['_deleted'] == 't',
            origin: r['_origin'] as String?,
            serverSeq: (r['server_seq'] as num?)?.toInt() ?? 0,
            txid: (r['txid'] as num?)?.toInt() ?? 0,
          ),
      ],
      safe: (map['safe'] as num?)?.toInt() ?? 0,
      // م65 — أفق الضغط: يحسبه الخادم كأدنى مؤشر مطبَّق بين أجهزة الحساب.
      // غيابه (خادم أقدم) يُبقيه null ⇒ يظل الضغط معطّلاً — فشل آمن مقصود.
      horizon: (map['horizon'] as num?)?.toInt(),
      // م73 — أفق الأرشيف: أعلى txid حُذف بالأرشفة الباردة. غيابه (خادم
      // قبل المهاجرة 0022) يُبقيه null ⇒ لا كشف فجوة، والسلوك كما كان.
      archiveHorizon: (map['archive_horizon'] as num?)?.toInt(),
    );
  }

  /// م73 — تبليغ حالة الجهاز (مرة يومياً): يخبر الخادم بمؤشر هذا الجهاز
  /// كي لا تحذف الأرشفة صفوفاً لم تصله بعد. أفضل جهد — فشله لا يعطّل شيئاً
  /// (الخادم عندئذٍ يرى الجهاز «قديم المؤشر» فيصبح أكثر تحفظاً لا أقل).
  @override
  Future<void> reportSyncState(String deviceId, int cursorTxid) async {
    await _rpc('report_sync_state', {
      'p_device_id': deviceId,
      'p_cursor_txid': cursorTxid,
    });
  }

  /// م79 — دفع قيود سجلّ التدقيق. أفضل جهد: فشله لا يعطّل مزامنة، والقيود
  /// تبقى محلياً بعلامة `pushed = 0` وتُعاد في الدورة التالية.
  @override
  Future<int> pushAudit(List<Map<String, Object?>> events) async {
    final data = await _rpc('push_audit', {'p_events': events});
    return (data is num) ? data.toInt() : 0;
  }

  // ── م134 — حصة التخزين (المرحلة ٣) ────────────────────────────────────────
  //  قناتان مع النظام المعتمد على الخادم: قراءة الحصة، وتبليغ القياس. كلاهما
  //  محصورٌ بـauth.uid() داخل الدالة، فلا يقرأ جهازٌ حصة غيره ولا يبلّغ عنه.

  /// حصة المستخدم واستهلاكه المبلَّغ: {used_bytes, file_count, quota_bytes}.
  @override
  Future<Map<String, Object?>> getMyStorage() async {
    final data = await _rpc('get_my_storage', const {});
    return data is Map ? data.cast<String, Object?>() : const {};
  }

  // ── م135 — الترخيص (المرحلة ٥) ────────────────────────────────────────────

  @override
  Future<Map<String, Object?>> verifyLicense(
    Map<String, Object?> device,
  ) async {
    final data = await _rpc('verify_license', {'p_device': device});
    return data is Map ? data.cast<String, Object?>() : const {};
  }

  @override
  Future<Map<String, Object?>> activateCode(
    String code,
    Map<String, Object?> device,
  ) async {
    final data = await _rpc('activate_code', {
      'p_code': code,
      'p_device': device,
    });
    return data is Map ? data.cast<String, Object?>() : const {};
  }

  @override
  Future<Map<String, Object?>> getMySubscription() async {
    final data = await _rpc('get_my_subscription', const {});
    return data is Map ? data.cast<String, Object?>() : const {};
  }

  @override
  Future<List<Map<String, Object?>>> listPublicPlans() async {
    final data = await _rpc('list_public_plans', const {});
    if (data is List) {
      return [
        for (final e in data)
          if (e is Map) e.cast<String, Object?>(),
      ];
    }
    return const [];
  }

  /// تبليغ قياس الجهاز (self). يعيد الحالة المحدَّثة نفسها.
  @override
  Future<Map<String, Object?>> reportMyStorage(
    int usedBytes,
    int fileCount,
  ) async {
    final data = await _rpc('report_my_storage', {
      'p_used_bytes': usedBytes,
      'p_file_count': fileCount,
    });
    return data is Map ? data.cast<String, Object?>() : const {};
  }

  // ── المرحلة هـ — الإشعارات داخل التطبيق ───────────────────────────────────

  /// إشعارات المستخدم غير المقروءة (الأقدم أولاً). تفكيكٌ دفاعيّ: كلّ عنصرٍ
  /// خريطةٌ أو يُتخطّى.
  @override
  Future<List<Map<String, Object?>>> getMyNotifications() async {
    final data = await _rpc('get_my_notifications', const {});
    if (data is List) {
      return [
        for (final e in data)
          if (e is Map) e.cast<String, Object?>(),
      ];
    }
    return const [];
  }

  @override
  Future<void> markNotificationRead(String id) async {
    await _rpc('mark_notification_read', {'p_id': id});
  }

  @override
  Future<Map<String, Object?>> getAppUpdate() async {
    final data = await _rpc('get_app_update', const {});
    return data is Map ? data.cast<String, Object?>() : const {};
  }
}
