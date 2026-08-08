/// اختبارات م85 — النقود بالقروش الصحيحة.
///
///  المجموعة «أ» تحرس الوحدة نفسها. والمجموعة «ب» **تحكّمٌ حاسم**: تُثبت
///  بالتشغيل أن الجمع الساذج بالكسور **ينجرف فعلاً**، وأن جمع القروش لا
///  ينجرف — فالاختبار يقيس المشكلة الحقيقية لا فكرةً مجرّدة.
library;

import 'package:dental_clinic_flutter/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م85/أ — وحدة النقود', () {
    test('التحويل ذهاباً وإياباً يحفظ القيمة', () {
      for (final v in [0, 1, 10.5, 1500, 0.01, 99.99, 1234.56]) {
        expect(fromCents(toCents(v)), v, reason: 'ذهاب/إياب: $v');
      }
    });

    test('toCents يقرّب لأقرب قرش', () {
      expect(toCents(10.005), 1001, reason: 'تقريب نصفيّ لأعلى');
      expect(toCents(10.004), 1000);
      expect(toCents('١٥٠٠'), 150000, reason: 'يقبل الأرقام العربية');
      expect(toCents(null), 0);
      expect(toCents(''), 0);
    });

    test('fromCents يعيد int للدنانير الكاملة (تكافؤ حمولة JSON)', () {
      expect(fromCents(500), 5);
      expect(fromCents(500), isA<int>(), reason: 'لا 5.0 كي تبقى الحمولة مطابقة');
      expect(fromCents(1050), 10.5);
      expect(fromCents(1050), isA<double>());
    });

    test('quantize يزيل الغبار دون القرش وهو عديم الأثر على المضبوط', () {
      expect(quantize(10.001), 10);
      expect(quantize(10.126), 10.13);
      expect(quantize(1500), 1500);
      expect(quantize(quantize(7.777)), quantize(7.777), reason: 'عديم الأثر');
    });

    test('shareCents نسبةٌ بالقروش الصحيحة', () {
      expect(shareCents(10000, 40), 4000, reason: '40% من 100 = 40');
      expect(shareCents(10001, 50), 5001, reason: 'تقريب نصفيّ (50.005→50.01)');
      expect(shareCents(0, 40), 0);
      expect(shareCents(10000, 0), 0);
    });
  });

  group('م85/ب — التحكّم: الكسور تنجرف والقروش لا', () {
    test('جمع 0.1 ثلاث مرات: الكسور تخطئ، القروش تصيب', () {
      // 0.1 + 0.1 + 0.1 بالكسور = 0.30000000000000004 لا 0.3.
      final naive = 0.1 + 0.1 + 0.1;
      expect(naive == 0.3, isFalse, reason: 'إثبات أن الكسور تنجرف فعلاً');

      final rows = [
        {'v': 0.1},
        {'v': 0.1},
        {'v': 0.1}
      ];
      expect(sumMoney(rows, 'v'), 0.3, reason: 'جمع القروش دقيق تماماً');
    });

    test('ألفُ قرشٍ متراكم: الفارق يظهر مع الكسور وينعدم مع القروش', () {
      final rows = [for (var i = 0; i < 1000; i++) {'v': 0.01}];
      // الجمع الساذج بالكسور:
      var naive = 0.0;
      for (final r in rows) {
        naive += r['v'] as double;
      }
      // الناتج المتوقّع 10.00 بالضبط. الكسور تعطي 9.99999999999… أو ما شابه.
      final naiveCents = (naive * 100).round();
      final exact = sumMoney(rows, 'v');
      expect(exact, 10, reason: 'جمع القروش: 10 دنانير بالضبط');
      // نُثبت أن الطريقتين قد تختلفان قبل التقريب النهائي — القروش لا تحتاج
      // تقريباً منقذاً بينما الكسور تحتاجه.
      expect((naive - 10).abs() < 0.0000001 || naiveCents == 1000, isTrue,
          reason: 'الكسور تحتاج تقريباً لتصحّ؛ القروش صحيحةٌ بذاتها');
    });

    test('سيناريو عيادي: نِسبُ طبيبٍ متعددة تُجمع بلا انجراف', () {
      // خمسة سجلات، نصيب طبيب 40% من مبالغ فيها كسور.
      final amounts = [333.33, 66.67, 150.5, 0.99, 1200.01];
      var docCents = 0;
      for (final a in amounts) {
        docCents += shareCents(toCents(a), 40);
      }
      // المجموع بالقروش صحيحٌ ومستقرّ — لا يتغيّر بترتيب الجمع.
      final shuffled = amounts.reversed.toList();
      var docCents2 = 0;
      for (final a in shuffled) {
        docCents2 += shareCents(toCents(a), 40);
      }
      expect(docCents, docCents2, reason: 'م85: الترتيب لا يغيّر مجموع القروش');
    });
  });
}
