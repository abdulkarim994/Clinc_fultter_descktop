// اختبارات نقية لدوال «التحاليل الثلاثية» (analyses3.dart) — بلا قاعدة بيانات
// ولا Riverpod ولا Flutter: نمرّر خرائط مباشرةً ونتحقق من منطق القراءة وحده.
//
// الغرض: التحقق من أن triAnalysesEnabled وtriAnalysesPrice يتصرفان بشكلٍ
// صحيحٍ في جميع الحالات الحدية (مفتاح غائب، قيم غريبة، أنواع فاسدة)، وأن
// لا استثناءَ يُرمى مهما كانت بيانات الإعداد.
library;

import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show kTriAnalysesCfgKey, triAnalysesEnabled, triAnalysesPrice;
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

void main() {
  // ── غياب مفتاح analyses3 كلياً ────────────────────────────────────────────

  group('غياب المفتاح كلياً', () {
    test('خريطة فارغة → معطّل وسعر 0', () {
      const cfg = <String, Object?>{};
      // الميزة معطّلة افتراضياً (المالك لم يفعّلها بعد).
      expect(triAnalysesEnabled(cfg), isFalse,
          reason: 'افتراضياً معطّلة حتى قرارٍ صريح');
      expect(triAnalysesPrice(cfg), 0, reason: 'السعر صفرٌ عند غياب المفتاح');
    });

    test('مفتاح analyses3 قيمته null → معطّل وسعر 0', () {
      const cfg = <String, Object?>{kTriAnalysesCfgKey: null};
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triAnalysesPrice(cfg), 0);
    });

    test('مفتاح analyses3 قيمته سلسلة نصية → معطّل وسعر 0 (بلا استثناء)', () {
      // نوعٌ غريب تماماً — الدوال تتجاهله بأمان.
      const cfg = <String, Object?>{kTriAnalysesCfgKey: 'غلط'};
      expect(() => triAnalysesEnabled(cfg), returnsNormally);
      expect(() => triAnalysesPrice(cfg), returnsNormally);
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triAnalysesPrice(cfg), 0);
    });

    test('مفتاح analyses3 قيمته عدد → معطّل وسعر 0 (بلا استثناء)', () {
      const cfg = <String, Object?>{kTriAnalysesCfgKey: 42};
      expect(() => triAnalysesEnabled(cfg), returnsNormally);
      expect(() => triAnalysesPrice(cfg), returnsNormally);
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triAnalysesPrice(cfg), 0);
    });
  });

  // ── حقل enabled بقيم مختلفة ────────────────────────────────────────────────

  group('enabled بقيم مختلفة', () {
    test('enabled: true → مفعّل', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 0, 'enabled': true},
      };
      expect(triAnalysesEnabled(cfg), isTrue);
    });

    test('enabled: false → معطّل', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 100, 'enabled': false},
      };
      expect(triAnalysesEnabled(cfg), isFalse);
    });

    test('enabled غائبٌ من الخريطة → معطّل (افتراضي آمن)', () {
      // الخريطة موجودة لكن enabled غير موجودة فيها.
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 500},
      };
      expect(triAnalysesEnabled(cfg), isFalse,
          reason: 'الغياب = false (enabled == true فقط يُفعّل)');
    });

    test('enabled: 1 (عدد لا bool) → معطّل (true فقط يُفعّل)', () {
      // الدالة تشترط == true صراحةً لا jsTruthy.
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 0, 'enabled': 1},
      };
      expect(triAnalysesEnabled(cfg), isFalse,
          reason: 'قيمة 1 ليست true من نوع bool');
    });

    test('enabled: "true" (سلسلة) → معطّل', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 0, 'enabled': 'true'},
      };
      expect(triAnalysesEnabled(cfg), isFalse);
    });
  });

  // ── حقل price بقيم مختلفة ──────────────────────────────────────────────────

  group('price بقيم مختلفة', () {
    test('price: 3500 (int) → 3500', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 3500, 'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 3500);
    });

    test('price: 1500.5 (double) → 1500.5', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 1500.5, 'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 1500.5);
    });

    test('price: "2000" (سلسلة رقمية) → 2000', () {
      // num.tryParse تحوّل السلسلة الرقمية بنجاح.
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': '2000', 'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 2000);
    });

    test('price: "فاسد" (سلسلة غير رقمية) → 0', () {
      // num.tryParse تُعيد null فيسقط إلى 0.
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 'فاسد', 'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 0,
          reason: 'السلسلة الفاسدة تُعيد صفراً لا استثناءً');
    });

    test('price غائبٌ من الخريطة → 0', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 0);
    });

    test('price: null → 0', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': null, 'enabled': true},
      };
      expect(triAnalysesPrice(cfg), 0);
    });
  });

  // ── خرائط بأنواع غريبة لا ترمي استثناءً ────────────────────────────────────

  group('مقاومة الأنواع الغريبة', () {
    test('analyses3 قائمة (بدل خريطة) → بلا استثناء، معطّل، سعر 0', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: [1, 2, 3],
      };
      expect(() => triAnalysesEnabled(cfg), returnsNormally);
      expect(() => triAnalysesPrice(cfg), returnsNormally);
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triAnalysesPrice(cfg), 0);
    });

    test('خريطة cfg نفسها بمفاتيح عشوائية لا ترمي استثناءً', () {
      final cfg = <String, Object?>{
        'foo': 123,
        'bar': [1, 2],
        'baz': null,
      };
      expect(() => triAnalysesEnabled(cfg), returnsNormally);
      expect(() => triAnalysesPrice(cfg), returnsNormally);
    });

    test('analyses3 خريطة بـ enabled وprice بأنواع مختلطة غريبة', () {
      final cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': [], 'enabled': {}},
      };
      // لا استثناء — القيم غير الصالحة تُعيد الافتراضات.
      expect(() => triAnalysesEnabled(cfg), returnsNormally);
      expect(() => triAnalysesPrice(cfg), returnsNormally);
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triAnalysesPrice(cfg), 0);
    });
  });
}
