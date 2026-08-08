/// اختبارات م66/دفعة صفر-ب — رتابة الساعة المنطقية بعد استقبال HLC أقدم.
///
/// العيب الأصلي (SYNC-2): `receive` كانت تصفّر العدّاد حين يكون زمننا
/// المنطقي هو الأكبر (الحالة الغالبة عند كل سحب لصف كُتب قبل آخر حدث محلي).
/// النتيجة: حدثٌ لاحق أقدم من سابقه، وإعادة سلسلة HLC مستهلَكة حرفياً — ومع
/// op_id = entity:id:hlc يقرّها الخادم بلا تطبيق فتُفقد الكتابة بصمت.
library;

import 'package:dental_clinic_flutter/data/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م66 — رتابة HLC بعد استقبال أقدم', () {
    test('REPRO: حدث بعد استقبال HLC أقدم يبقى أحدث، ولا يتكرر', () {
      final c = Hlc();
      // نضع الزمن المنطقي أمام الجدار (كأي سحب من جهاز ساعته أسرع قليلاً).
      final futureMs = DateTime.now().millisecondsSinceEpoch + 60000;
      c.receive('$futureMs:0:devB');

      final t1 = c.tick('devA');
      final t2 = c.tick('devA');
      expect(isNewer(t2, t1), isTrue);

      // استقبال صف كُتب أبكر (زمن أقل) — الحالة الغالبة لكل سحب.
      c.receive('${futureMs - 5000}:0:devB');

      final t3 = c.tick('devA');
      final t4 = c.tick('devA');

      expect(isNewer(t3, t2), isTrue,
          reason: 'الرتابة صامدة: t3 أحدث من t2 لا أقدم');
      expect({t1, t2, t3, t4}.length, 4,
          reason: 'لا تكرار لأي سلسلة HLC');
    });

    test('استقبال متكرر لأقدم لا يعيد أبداً سلسلة سابقة', () {
      final c = Hlc();
      final base = DateTime.now().millisecondsSinceEpoch + 120000;
      c.receive('$base:0:devB');
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        seen.add(c.tick('devA'));
        c.receive('${base - (i + 1) * 100}:0:devB'); // أقدم في كل مرة
      }
      expect(seen.length, 50, reason: 'خمسون سلسلة فريدة بلا تكرار');
    });

    test('CONTROL: استقبال أحدث يقفز العدّاد فوق الوارد', () {
      final c = Hlc();
      final base = DateTime.now().millisecondsSinceEpoch + 60000;
      c.receive('$base:0:devB');
      final t1 = c.tick('devA');
      c.receive('${base + 5000}:9:devB'); // أحدث
      final t2 = c.tick('devA');
      expect(isNewer(t2, t1), isTrue);
      expect(hlcMillis(t2), base + 5000);
    });

    test('CONTROL: الحالات الأربع لا تكسر الترتيب الكلي', () {
      final c = Hlc();
      final ms = DateTime.now().millisecondsSinceEpoch + 30000;
      c.receive('$ms:0:z');
      var prev = c.tick('a');
      // خليط: أقدم، مساوٍ، أحدث بقليل، أقدم ثانيةً
      for (final r in ['${ms - 1000}:3:z', '$ms:7:z', '${ms + 1}:0:z',
                       '${ms - 9000}:2:z']) {
        c.receive(r);
        final t = c.tick('a');
        expect(isNewer(t, prev), isTrue, reason: 'رتابة عبر $r');
        prev = t;
      }
    });
  });
}
