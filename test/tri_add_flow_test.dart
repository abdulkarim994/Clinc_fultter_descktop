// اختبارات نقية بلا قاعدة لدالة triAnalysisFor في record_saver.dart —
// تتحقق من كل بوابات null (تعديل / غير مؤشر / معطل / سعر صفر أو سالب)،
// والحالة الموجبة (اسم ثابت + سعر من الإعداد + تطبيع طريقة الدفع).

import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    show triAnalysisFor;
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show kTriAnalysesName;
import 'package:flutter_test/flutter_test.dart';

/// مساعد يبني خريطة إعدادات بالميزة مفعّلة وسعرٍ محدد.
Map<String, Object?> _cfg({required num price, bool enabled = true}) => {
      'analyses3': {
        'enabled': enabled,
        'price': price,
      },
    };

void main() {
  group('triAnalysisFor — بوابات null', () {
    // بوابة الإنشاء: creating == false يعيد null مهما كانت بقية الشروط.
    test('وضع التعديل (creating=false) يعيد null', () {
      final result = triAnalysisFor(
        creating: false,
        checked: true,
        cfg: _cfg(price: 150),
        payment: 'كاش',
      );
      expect(result, isNull);
    });

    // بوابة العلامة: checked == false يعيد null.
    test('غير مؤشر (checked=false) يعيد null', () {
      final result = triAnalysisFor(
        creating: true,
        checked: false,
        cfg: _cfg(price: 150),
        payment: 'كاش',
      );
      expect(result, isNull);
    });

    // بوابة التفعيل: الميزة معطّلة يعيد null.
    test('الميزة معطّلة (enabled=false) يعيد null', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: 150, enabled: false),
        payment: 'كاش',
      );
      expect(result, isNull);
    });

    // بوابة السعر: سعر صفر يعيد null.
    test('سعر صفر يعيد null', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: 0),
        payment: 'كاش',
      );
      expect(result, isNull);
    });

    // بوابة السعر: سعر سالب يعيد null.
    test('سعر سالب يعيد null', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: -10),
        payment: 'كاش',
      );
      expect(result, isNull);
    });

    // إعدادات فارغة (الميزة غير موجودة) يعيد null.
    test('إعدادات فارغة (لا مفتاح analyses3) تعيد null', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: const {},
        payment: 'كاش',
      );
      expect(result, isNull);
    });
  });

  group('triAnalysisFor — الحالة الموجبة', () {
    // الحالة السعيدة: تعيد AnalysisInput بالاسم الثابت والسعر من الإعداد.
    test('تعيد AnalysisInput بالاسم الثابت والسعر الصحيح', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: 200),
        payment: 'كاش',
      );
      expect(result, isNotNull);
      expect(result!.name, equals(kTriAnalysesName));
      expect(result.price, equals(200));
    });

    // تطبيع طريقة الدفع: 'تحويل' يبقى 'تحويل'.
    test('طريقة الدفع تحويل تُحفظ تحويل', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: 100),
        payment: 'تحويل',
      );
      expect(result!.payment, equals('تحويل'));
    });

    // تطبيع طريقة الدفع: أي قيمة أخرى تصير 'كاش'.
    test('أي طريقة دفع غير تحويل تُطبَّع كاش', () {
      for (final pay in ['كاش', 'بطاقة', 'أجل', '', 'شيك']) {
        final result = triAnalysisFor(
          creating: true,
          checked: true,
          cfg: _cfg(price: 50),
          payment: pay,
        );
        expect(result!.payment, equals('كاش'),
            reason: 'payment="$pay" يجب أن يُطبَّع كاش');
      }
    });

    // السعر يُقرأ من الإعداد لا من مدخل خارجي.
    test('السعر يُقرأ من الإعداد (250) بدقة', () {
      final result = triAnalysisFor(
        creating: true,
        checked: true,
        cfg: _cfg(price: 250),
        payment: 'كاش',
      );
      expect(result!.price, equals(250));
    });
  });
}
