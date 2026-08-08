/// اختبارات م98 — «كشف الحساب»: المدى التاريخي، الفلاتر، والأحدث أولاً.
///
///  الدالة النقية incomeByClinicRange هي قلب الميزة (الواجهة غلافٌ عليها):
///  تُختبَر هنا بمعطياتٍ في الذاكرة بلا قاعدة ولا واجهة — سريعةٌ وحاسمة.
///  وتُحرَس معها ضمانةُ م23: todayIncomeByClinic بقيت غلافاً أميناً.
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

JMap _rec({
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

void main() {
  group('م98/أ — المدى التاريخي', () {
    test('يشمل الحدّين ويستبعد ما خارجهما', () {
      final recs = [
        _rec(name: 'أ', amount: 100, date: '2026-07-28'),
        _rec(name: 'ب', amount: 200, date: '2026-07-30'),
        _rec(name: 'ج', amount: 400, date: '2026-08-01'),
        _rec(name: 'د', amount: 800, date: '2026-08-05'),
      ];
      final g = incomeByClinicRange(recs, const [],
          from: '2026-07-30', to: '2026-08-01');
      final total = g.fold<num>(0, (s, e) => s + e.total);
      expect(total, 600, reason: 'ب+ج فقط داخل [30..01]');
    });

    test('يوم واحد (من=إلى) يكافئ دخل ذلك اليوم', () {
      final recs = [
        _rec(name: 'أ', amount: 100, date: '2026-07-30'),
        _rec(name: 'ب', amount: 200, date: '2026-07-31'),
      ];
      final g = incomeByClinicRange(recs, const [],
          from: '2026-07-31', to: '2026-07-31');
      expect(g.fold<num>(0, (s, e) => s + e.total), 200);
    });
  });

  group('م98/ب — الأحدث إضافةً أولاً', () {
    test('الفرز تنازليّ على createdAt داخل العيادة', () {
      final recs = [
        _rec(name: 'قديم', amount: 100, date: '2026-08-01', createdAt: 10),
        _rec(name: 'أحدث', amount: 100, date: '2026-08-01', createdAt: 30),
        _rec(name: 'وسط', amount: 100, date: '2026-08-01', createdAt: 20),
      ];
      final g = incomeByClinicRange(recs, const [],
          from: '2026-08-01', to: '2026-08-01');
      final names = g.single.patients.map((p) => p.name).toList();
      expect(names, ['أحدث', 'وسط', 'قديم'],
          reason: 'م98: آخر ما أُضيف يتصدّر');
    });

    test('ترتيب مجموعات العيادات يتبع أحدثَ صفٍّ فيها', () {
      final recs = [
        _rec(name: 'x', amount: 100, date: '2026-08-01', clinic: 'ع1', createdAt: 5),
        _rec(name: 'y', amount: 100, date: '2026-08-01', clinic: 'ع2', createdAt: 50),
      ];
      final g = incomeByClinicRange(recs, const [],
          from: '2026-08-01', to: '2026-08-01');
      expect(g.first.clinic, 'ع2', reason: 'العيادة ذات أحدث حركة أولاً');
    });
  });

  group('م98/ج — الفلاتر', () {
    final recs = [
      _rec(name: 'أ', amount: 100, date: '2026-08-01', clinic: 'ع1', payment: 'كاش'),
      _rec(name: 'ب', amount: 200, date: '2026-08-01', clinic: 'ع1', payment: 'بطاقة'),
      _rec(name: 'ج', amount: 400, date: '2026-08-01', clinic: 'ع2', payment: 'كاش'),
    ];

    test('فلتر العيادة', () {
      final g = incomeByClinicRange(recs, const [],
          from: '2026-08-01', to: '2026-08-01', clinic: 'ع1');
      expect(g.length, 1);
      expect(g.single.total, 300);
    });

    test('فلتر طريقة الدفع', () {
      final g = incomeByClinicRange(recs, const [],
          from: '2026-08-01', to: '2026-08-01', payment: 'كاش');
      expect(g.fold<num>(0, (s, e) => s + e.total), 500, reason: 'أ+ج');
    });

    test('الفلتران يتراكبان', () {
      final g = incomeByClinicRange(recs, const [],
          from: '2026-08-01', to: '2026-08-01', clinic: 'ع1', payment: 'كاش');
      expect(g.single.total, 100, reason: 'كاش عيادة ع1 فقط');
    });
  });

  group('م98/د — قواعد م23 محفوظة في الدالة المعمَّمة', () {
    test('الدين غير المدفوع مستبعد، ودفعته محسوبة، والسالب/الصفر مُهمَل', () {
      final recs = [
        _rec(name: 'دَين', amount: 300, date: '2026-08-01', payment: 'دين'),
        _rec(
            name: 'دفعة',
            amount: 120,
            date: '2026-08-01',
            payment: 'دين',
            isDebtPayment: true),
        _rec(name: 'صفر', amount: 0, date: '2026-08-01'),
        _rec(name: 'سالب', amount: -50, date: '2026-08-01'),
        _rec(name: 'نقد', amount: 80, date: '2026-08-01'),
      ];
      final total = incomeByClinicRange(recs, const [],
              from: '2026-08-01', to: '2026-08-01')
          .fold<num>(0, (s, e) => s + e.total);
      expect(total, 200, reason: 'دفعة 120 + نقد 80 فقط');
    });

    test('todayIncomeByClinic بقيت غلافاً أميناً لليوم الحالي', () {
      final today = getCurrentDate();
      final recs = [
        _rec(name: 'اليوم', amount: 150, date: today),
        _rec(name: 'أمس', amount: 999, date: '2020-01-01'),
      ];
      final g = todayIncomeByClinic(recs, const []);
      expect(g.fold<num>(0, (s, e) => s + e.total), 150,
          reason: 'م23: اليوم فقط، بلا مساس');
    });
  });
}
