/// ============================================================================
///  م79 — دافع سجلّ التدقيق: من الجهاز إلى جدول لا يقبل إلا الإضافة
/// ============================================================================
///
///  لماذا دافع مستقل ولم يُحمَّل على محرّك المزامنة
///  ─────────────────────────────────────────────
///  قيود التدقيق **ليست بيانات مستخدم**: لا تُدمَج، ولا تتعارض، ولا تُحذف،
///  ولا تحتاج ساعة منطقية ولا شواهد قبور. إدخالها في `sync_rows` كان
///  سيُخضعها لمحرّك دمج لا تحتاج منه شيئاً، ويُعرّضها لمسارات (الأرشفة
///  الباردة، تطهير الشواهد) **مصمَّمة لحذف القديم** — وهو نقيض الغرض.
///
///  فالمسار هنا أبسط بكثير: أرسِل، ثم علِّم المُرسَل. والمعرّف من العميل
///  يجعل الدفع عديم الأثر، فانقطاع الشبكة بين الإدراج والإقرار لا يُكرّر
///  شيئاً (`on conflict do nothing` على الخادم).
///
///  أفضل جهد بالكامل
///  ────────────────
///  فشل الدفع **لا يعطّل مزامنة ولا عملاً سريرياً**. القيود تبقى محلياً
///  بعلامة `pushed = 0` وتُعاد المحاولة في الدورة التالية. والجهاز الذي
///  يعمل بلا سحابة يحتفظ بسجلّه كاملاً محلياً — منقوص الحماية لا منقوص
///  المحتوى.
library;

import 'dart:convert';

import '../audit/audit_trail.dart' show markAuditPushed, unpushedAudit;
import '../db/local_db.dart';
import 'engine.dart' show EngineStatus;

/// عقد الدفع — منفصل عن `SyncTransport` كي لا تُكسر المزيّفات القائمة،
/// تماماً كما فُعل مع `ArchiveTransport` (م70).
abstract interface class AuditTransport {
  /// يدفع دفعةً ويُرجع **عدد المُدرَج فعلاً** (لا المُرسَل) — الفرق بينهما
  /// يكشف التكرار عند التشخيص.
  Future<int> pushAudit(List<Map<String, Object?>> events);
}

/// حجم الدفعة الواحدة. الخادم يرفض ما فوق 1000؛ نبقى دونه بهامش.
const int kAuditBatch = 250;

class AuditPusher {
  AuditPusher({required this.db, required this.transportOf});

  final LocalDb db;

  /// يُقرأ عند كل نبضة لا يُلتقط مرة — فضبط السحابة أو تبديل الحساب يسري
  /// فوراً، و`null` يعني الوضع المحلي ⇒ لا دفع (والقيود تتراكم محلياً).
  final AuditTransport? Function() transportOf;

  bool _busy = false;

  /// آخر عدد مُدرَج — للتشخيص والاختبار.
  int lastPushed = 0;

  /// يلتصق بنبضة اكتمال دورة المزامنة، كما يفعل جدولا الأرشفة والاحتفاظ.
  void onEngineStatus(EngineStatus s) {
    if (s.phase != 'complete' || !s.online) return;
    unawaitedPush();
  }

  void unawaitedPush() {
    if (_busy) return;
    _busy = true;
    pushOnce().whenComplete(() => _busy = false).catchError((_) => 0);
  }

  Future<int> pushOnce() async {
    final t = transportOf();
    if (t == null) return 0;

    final rows = unpushedAudit(db, limit: kAuditBatch);
    if (rows.isEmpty) return 0;

    final events = <Map<String, Object?>>[];
    final ids = <String>[];
    for (final r in rows) {
      final id = '${r['id'] ?? ''}';
      if (id.isEmpty) continue;
      ids.add(id);
      events.add({
        'id': id,
        'at': (r['at'] as num? ?? 0).toInt(),
        'actor_uid': r['actor_uid'],
        'device_id': r['device_id'],
        'action': '${r['action'] ?? ''}',
        'entity': r['entity'],
        'entity_id': r['entity_id'],
        'detail': _decodeDetail(r['detail']),
      });
    }
    if (events.isEmpty) return 0;

    final inserted = await t.pushAudit(events);
    // تُعلَّم مدفوعةً حتى لو أعاد الخادم صفراً: الصفر يعني «موجودة أصلاً»
    // (تكرار بعد انقطاع) لا «رُفضت» — والرفض يرمي استثناءً فلا نصل هنا.
    markAuditPushed(db, ids);
    lastPushed = inserted;
    return inserted;
  }

  Object? _decodeDetail(Object? raw) {
    final s = '${raw ?? ''}';
    if (s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }
}
