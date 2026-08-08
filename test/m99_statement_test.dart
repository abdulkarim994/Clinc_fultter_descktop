/// اختبارات م99 — الكشف المالي: الفلترة متعددة الاختيار، البحث، والأحدث
/// أولاً، مع حفظ قواعد م23. المنطق النقي financialStatement هو قلب الميزة.
library;

import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

JMap _r({
  required String name,
  required num amount,
  required String date,
  String clinic = 'ع1',
  String payment = 'كاش',
  String service = 'حشو',
  int createdAt = 0,
  bool isDebtPayment = false,
}) =>
    {
      'name': name,
      'amount': amount,
      'date': date,
      'clinic': clinic,
      'payment': payment,
      'service': service,
      'createdAt': createdAt,
      if (isDebtPayment) 'isDebtPayment': true,
    };

num _grand(List<ClinicIncomeRangeGroup> g) =>
    g.fold<num>(0, (s, e) => s + e.total);

void main() {
  final recs = [
    _r(name: 'أحمد', amount: 100, date: '2026-08-01', clinic: 'ع1', payment: 'كاش', createdAt: 10),
    _r(name: 'هدى', amount: 200, date: '2026-08-01', clinic: 'ع1', payment: 'تحويل', createdAt: 30),
    _r(name: 'سالم', amount: 400, date: '2026-08-02', clinic: 'ع2', payment: 'كاش', createdAt: 40),
    _r(name: 'دفعة', amount: 50, date: '2026-08-02', clinic: 'ع2', payment: 'دين', createdAt: 50, isDebtPayment: true),
    _r(name: 'دَين', amount: 900, date: '2026-08-02', clinic: 'ع2', payment: 'دين'),
  ];
  final pros = [
    _r(name: 'تاج', amount: 700, date: '2026-08-01', clinic: 'ع1', payment: '', service: 'تركيبات', createdAt: 20),
  ];

  group('م99/أ — المدى والإجمالي', () {
    test('المدى الكامل: كل المقبوض بلا الدين غير المدفوع', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02');
      // 100+200+400+50 + تركيبات 700 = 1450 (الدين 900 مستبعد).
      expect(_grand(g), 1450);
    });

    test('يوم واحد يحصر النتائج', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-02', to: '2026-08-02');
      expect(_grand(g), 450, reason: '400 + دفعة 50');
    });
  });

  group('م99/ب — فلترة متعددة الاختيار', () {
    test('عيادات متعددة', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02', clinics: {'ع2'});
      expect(_grand(g), 450);
      expect(g.every((x) => x.clinic == 'ع2'), isTrue);
    });

    test('فئات متعددة: كاش + تركيبات معاً', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01',
          to: '2026-08-02',
          categories: {'كاش', 'تركيبات'});
      // كاش 100+400 + تركيبات 700 = 1200.
      expect(_grand(g), 1200);
    });

    test('فئة الدين تلتقط الدفعات فقط لا أصل الدين', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02', categories: {'دين'});
      expect(_grand(g), 50, reason: 'دفعة الدين فقط');
    });

    test('العيادة + الفئة تتراكبان', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01',
          to: '2026-08-02',
          clinics: {'ع1'},
          categories: {'تحويل'});
      expect(_grand(g), 200);
    });
  });

  group('م99/ج — البحث والفرز', () {
    test('البحث بالاسم يرشّح', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02', nameQuery: 'سالم');
      expect(_grand(g), 400);
      expect(g.single.patients.single.name, 'سالم');
    });

    test('الأحدث إضافةً أولاً داخل العيادة', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02', clinics: {'ع1'});
      // ع1: تركيبات(20) أحدث من هدى(30)؟ لا — هدى createdAt=30 الأحدث.
      final names = g.single.patients.map((p) => p.name).toList();
      expect(names.first, 'هدى', reason: 'createdAt 30 هو الأحدث');
      expect(names, ['هدى', 'تاج', 'أحمد']);
    });

    test('فئة الصف تظهر في payment (تركيبات/دين)', () {
      final g = financialStatement(recs, pros,
          from: '2026-08-01', to: '2026-08-02', clinics: {'ع1'},
          categories: {'تركيبات'});
      expect(g.single.patients.single.payment, 'تركيبات');
    });
  });
}
