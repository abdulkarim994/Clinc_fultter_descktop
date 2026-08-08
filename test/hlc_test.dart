/// اختبارات ثوابت الساعة المنطقية الهجينة HLC — أول جزء منقول من عقود
/// المزامنة (م2 بدأ هنا لأن المستودعات تعتمد tick() في الحذف الناعم).
library;

import 'package:dental_clinic_flutter/data/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hlc.tick', () {
    test('is strictly monotonic and carries the device suffix', () {
      final c = Hlc();
      final a = c.tick('dev1');
      final b = c.tick('dev1');
      expect(isNewer(b, a), isTrue);
      expect(isNewer(a, b), isFalse);
      expect(a.endsWith(':dev1'), isTrue);
    });

    test('falls back to "local" for an empty device id', () {
      final c = Hlc();
      expect(c.tick(null).endsWith(':local'), isTrue);
      expect(c.tick('').endsWith(':local'), isTrue);
    });
  });

  group('Hlc.receive', () {
    // م77 — كان هذا الاختبار يؤكّد **تبنّي** ساعة عام 5138 بوصفه سلوكاً
    // صحيحاً («wall clock cannot pass it»)، فكان يُثبّت العلة لا يكشفها:
    // أي محاولة لإصلاح الاختطاف الدائم كانت سترتطم باختبار أحمر. عُكس
    // الحكم هنا إلى الصواب — الساعة البعيدة تُرفض.
    test('م77 — ساعة بعيدة إلى حدّ غير معقول تُرفض ولا تُختطف ساعتنا', () {
      final c = Hlc();
      const futureMs = 99999999999999; // عام 5138
      c.receive('$futureMs:5:other');

      expect(c.driftRejections, 1, reason: 'سُجّل الرفض');
      expect(c.lastRejectedHlc, '$futureMs:5:other');

      final t = c.tick('dev1');
      expect(hlcMillis(t), lessThan(futureMs),
          reason: 'م77: ساعتنا لم تُختطف إلى المستقبل');
      expect(hlcMillis(t),
          closeTo(DateTime.now().millisecondsSinceEpoch, 60000),
          reason: 'بقيت الساعة عند الزمن الجداري الحقيقي');
    });

    test('م77 — الانحراف المشروع يُقبل: الحارس ليس حاجزاً', () {
      final c = Hlc();
      // فارق منطقة زمنية قصوى + تأخّر NTP: ساعات قليلة أمامنا، مشروعة.
      final legit = DateTime.now().millisecondsSinceEpoch + 6 * 3600 * 1000;
      c.receive('$legit:5:other');

      expect(c.driftRejections, 0, reason: 'لا رفض لانحراف معقول');
      final t = c.tick('dev1');
      expect(hlcMillis(t), legit,
          reason: 'الساعة المشروعة تُتبنّى كما كانت دائماً');
      expect(isNewer(t, '$legit:5:other'), isTrue);
    });

    test('م77 — الرفض يمسّ الزمن وحده ولا يُسقط شيئاً', () {
      final c = Hlc();
      c.receive('99999999999999:5:other');
      // لا استثناء ولا تعطيل: تقدّمت الساعة إلى الزمن الجداري لا أبعد.
      expect(c.getState().ms,
          closeTo(DateTime.now().millisecondsSinceEpoch, 60000));
    });

    test('ignores null/empty', () {
      final c = Hlc();
      c.receive(null);
      c.receive('');
      expect(c.getState().ms, 0);
    });
  });

  group('restore()', () {
    test('only ever moves the clock forward', () {
      final c = Hlc();
      c.restore((ms: 1000, counter: 4));
      expect(c.getState(), (ms: 1000, counter: 4));
      c.restore((ms: 500, counter: 99)); // stale snapshot — ignored
      expect(c.getState(), (ms: 1000, counter: 4));
      c.restore((ms: 1000, counter: 9)); // same ms — max counter
      expect(c.getState(), (ms: 1000, counter: 9));
    });
  });

  group('isNewer total order', () {
    test('millis, then counter, then device id', () {
      expect(isNewer('2:0:a', '1:9:z'), isTrue);
      expect(isNewer('1:1:a', '1:0:z'), isTrue);
      expect(isNewer('1:0:b', '1:0:a'), isTrue);
      expect(isNewer('1:0:a', '1:0:a'), isFalse);
      expect(isNewer('1:0:a', null), isTrue);
      expect(isNewer(null, '1:0:a'), isFalse);
    });
  });

  test('persister is debounced and receives the latest state', () async {
    final c = Hlc();
    final seen = <HlcState>[];
    c.setPersister(seen.add);
    c.tick('d');
    c.tick('d');
    c.tick('d');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen.length, 1); // coalesced burst
    expect(seen.single.ms, c.getState().ms);
  });

  test('hlcMillis parses the wall component', () {
    expect(hlcMillis('1234:7:dev'), 1234);
    expect(hlcMillis(null), 0);
    expect(hlcMillis('garbage'), 0);
  });
}
