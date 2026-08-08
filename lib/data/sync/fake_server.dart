/// خادم مزامنة محلي في الذاكرة — يُستخدم في الاختبارات وفي «الوضع المحلي»
/// للتطبيق إلى أن يُوصل SupabaseTransport في م5.
///
/// يحاكي دلالات الخلفية الفعلية — يحاكي دلالات خلفية Supabase الفعلية
/// (apply_changes / pull_changes في supabase/migrations) بأمانة:
///   • سجل عمليات idempotent بمعرف op_id (إعادة الدفع لا تكرر التطبيق)
///   • حارس LWW بساعة HLC لكل صف (الأقدم لا يسحق الأحدث)
///   • server_seq و txid رتيبان عالمياً؛ pull يقسّم بنافذة [lower, safe) مثبتة
///     مع ترقيم keyset على (txid, server_seq)
library;

import 'hlc.dart' show isNewer, kMaxClockDriftMs;
import 'transport.dart';

/// م80 — انتهاء صلاحية الرمز (401) بوصفه صنفاً مستقلاً.
///
/// يُعرَّف هنا لا يُستورَد من `supabase_transport.dart`: تلك الطبقة تستورد
/// الآن من `data/sync/` (دافع التدقيق)، فالاستيراد المعاكس يُنشئ دورة.
/// والاختبار يحتاج تمييز «فشل عام» من «رمز منتهٍ» — مساران مختلفان تماماً.
class FakeAuthException implements Exception {
  FakeAuthException(this.message);
  final String message;
  final int statusCode = 401;
  @override
  String toString() => 'FakeAuthException(401): $message';
}

class SrvRow {
  SrvRow({
    required this.payload,
    required this.hlc,
    required this.deleted,
    this.origin,
    this.clinicId,
    required this.serverSeq,
    required this.txid,
  });

  Map<String, Object?> payload;
  String? hlc;
  bool deleted;
  String? origin;
  Object? clinicId;
  int serverSeq;
  int txid;
}

class FakeSyncServer implements SyncTransport {
  int _seq = 0;
  int _txid = 0;

  /// entity → id → row
  final Map<String, Map<String, SrvRow>> rows = {};

  /// applied_ops ledger (idempotent retry dedupe).
  final Set<String> appliedOps = {};

  /// Fault injection: fail the next N applyChanges calls.
  int failPushes = 0;

  /// Fault injection: fail the next N pullChanges calls.
  int failPulls = 0;

  // ── م80 — أمانة المحاكاة: ما كان الخادم الوهمي أودّ من الواقع فيه ──────
  //
  //  التدقيق رصد أن خُضرة الاختبارات تُثبت **أقلّ مما تبدو**: المزيّف كان
  //  متزامناً بلا تأخير، ويُرجع الصفوف مرتّبةً دائماً، ولا يكرّر شيئاً، ولا
  //  يميّز نوع الفشل. فأصنافٌ كاملة من أعطال الميدان **يستحيل** أن تظهر في
  //  الاختبار — لا لأنها غير موجودة بل لأن الأرضية لا تُنتجها.
  //
  //  الأعلام أدناه **مطفأة افتراضياً**: السلوك القديم يبقى كما هو حرفياً،
  //  فلا يتغيّر أي اختبار قائم. وتُشعَل في اختبارات المتانة وحدها.

  /// تأخير صناعي قبل كل ردّ — يكشف السباقات التي يخفيها الردّ الفوري.
  Duration latency = Duration.zero;

  /// يُرجع كل صفّ **مرتين** في الصفحة. الخادم الحقيقي يفعل ذلك عند حدود
  /// الصفحات حين تُحدِّث كتابةٌ متزامنة صفاً إلى txid الصفحة الجارية.
  bool duplicateRows = false;

  /// يعكس ترتيب صفوف الصفحة. مؤشّر السحب يفترض التصاعد على
  /// `(txid, server_seq)` — واستعلامٌ خادميّ بلا ترتيب صريح لا يضمنه.
  bool shuffleRows = false;

  /// يجعل إخفاق الدفع القادم انتهاءَ صلاحية رمز (401) لا عطلاً عاماً.
  /// المسار مختلف تماماً: 401 يستدعي تجديد الرمز وإعادة المحاولة.
  bool nextFailureIsAuth = false;

  /// عدد المرات التي طُلب فيها تجديد الرمز — يقرؤه الاختبار.
  int authFailures = 0;

  int get maxTxid => _txid;

  Future<void> _delay() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  Never _fail(String what) {
    if (nextFailureIsAuth) {
      nextFailureIsAuth = false;
      authFailures++;
      throw FakeAuthException('fake server: 401 unauthorized ($what)');
    }
    throw Exception('fake server: injected $what failure');
  }

  /// يقصّ ختماً تتجاوز أجزاؤه الزمنية الحاضرَ بأكثر من حدّ الانحراف إلى
  /// «الآن»، مبقياً العدّاد والجهاز. مرآةٌ لـ`apply_changes` بعد م84.
  String? _clampFutureHlc(String? hlc) {
    if (hlc == null || hlc.isEmpty) return hlc;
    final parts = hlc.split(':');
    final ms = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    if (ms == null) return hlc;
    final now = DateTime.now().millisecondsSinceEpoch;
    // الكشف بحدّ الانحراف، والقصّ إلى **الآن** لا إلى السقف: القصّ إلى
    // (الآن+الحدّ) يترك الختم في المستقبل يوماً كاملاً فيظلّ يحجب التعديلات.
    if (ms <= now + kMaxClockDriftMs) return hlc;
    final counter = parts.length > 1 ? parts[1] : '0';
    final device = parts.length > 2 ? parts[2] : '';
    return '$now:$counter:$device';
  }

  @override
  Future<List<ApplyAck>> applyChanges(List<WireOp> ops) async {
    await _delay();
    if (failPushes > 0) {
      failPushes--;
      _fail('push');
    }
    final acks = <ApplyAck>[];
    for (final op in ops) {
      final byId = rows.putIfAbsent(op.entity, () => {});
      final id = '${op.row['id']}';
      final existing = byId[id];
      // م84 — قصّ الختم المستقبلي البعيد عند الاستقبال (مرآة `apply_changes`).
      //
      //  جهازٌ بساعة خاطئة يدفع ختماً في سنة 2100، فيَحجب حارسُ LWW **كل**
      //  تعديلٍ سليمٍ لاحق (ختمه أصغر) بصمت: الخادم يبقى على القيمة المسمومة،
      //  والعميل يمسح علم الاتساخ فيظنّ نفسه متزامناً — تباعُدٌ دائم حتى تبلغ
      //  ساعة الحائط ذلك الزمن. (رُصد بالتشغيل.) القصّ إلى الحاضر يمنع
      //  التلوّث من المصدر بلا فقد بيانات — فالصف يَلحق بالحاضر لا بالمستقبل.
      final opHlc = _clampFutureHlc(op.row['_hlc'] as String?);

      if (appliedOps.contains(op.opId)) {
        // Idempotent retry: already applied — ack with the current seq.
        acks.add(ApplyAck(
            opId: op.opId, id: id, serverSeq: existing?.serverSeq));
        continue;
      }
      appliedOps.add(op.opId);

      // Server-side HLC LWW: apply only when strictly newer than stored.
      if (existing == null || isNewer(opHlc, existing.hlc)) {
        _seq++;
        _txid++;
        // الختم المقصوص يُكتب في الحمولة أيضاً كي يقرأه العميل متّسقاً.
        final storedPayload = Map<String, Object?>.from(op.row);
        if (opHlc != null) storedPayload['_hlc'] = opHlc;
        byId[id] = SrvRow(
          payload: storedPayload,
          hlc: opHlc,
          deleted: op.action == 'delete' ||
              op.row['_deleted'] == 1 ||
              op.row['_deleted'] == true,
          origin: op.row['_origin'] as String?,
          clinicId: op.row['clinic_id'],
          serverSeq: _seq,
          txid: _txid,
        );
      }
      // Rejected-as-older ops are STILL acked (the client clears its dirty
      // flag and converges by pulling the server's newer row) — the exact
      // LWW contract of apply_changes.
      acks.add(
          ApplyAck(opId: op.opId, id: id, serverSeq: byId[id]!.serverSeq));
    }
    return acks;
  }

  @override
  Future<PullPage> pullChanges({
    required int lower,
    int? pageTxid,
    required int pageSeq,
    int? upto,
    required int limit,
  }) async {
    await _delay();
    if (failPulls > 0) {
      failPulls--;
      _fail('pull');
    }
    // Commit-safe watermark: everything committed so far is safe.
    final safe = upto ?? (_txid + 1);

    final all = <({String entity, String id, SrvRow row})>[];
    rows.forEach((entity, byId) {
      byId.forEach((id, row) {
        all.add((entity: entity, id: id, row: row));
      });
    });
    all.sort((a, b) {
      final t = a.row.txid.compareTo(b.row.txid);
      return t != 0 ? t : a.row.serverSeq.compareTo(b.row.serverSeq);
    });

    final out = <PullRow>[];
    for (final e in all) {
      final r = e.row;
      if (r.txid < lower || r.txid >= safe) continue;
      // keyset: strictly after (pageTxid, pageSeq)
      if (pageTxid != null &&
          (r.txid < pageTxid ||
              (r.txid == pageTxid && r.serverSeq <= pageSeq))) {
        continue;
      }
      out.add(PullRow(
        entity: e.entity,
        id: e.id,
        payload: r.payload,
        clinicId: r.clinicId,
        hlc: r.hlc,
        deleted: r.deleted,
        origin: r.origin,
        serverSeq: r.serverSeq,
        txid: r.txid,
      ));
      if (out.length >= limit) break;
    }
    // م80 — تشويهات الواقع، مطفأة افتراضياً.
    var page = out;
    if (duplicateRows && page.isNotEmpty) {
      page = [for (final r in page) ...[r, r]];
    }
    if (shuffleRows && page.length > 1) {
      page = page.reversed.toList();
    }
    return PullPage(rows: page, safe: safe);
  }
}
