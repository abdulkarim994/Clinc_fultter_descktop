/// اختبارات م23 — «دخل اليوم» بتعريف المالك (2026-07-27):
/// لقطة الهاتف أظهرت الرأس 6,310 بينما كشف «دخل اليوم» نفسه يجمع 7,500 —
/// الفارق 1,190 هو دفعتا التركيبات (500+1,200) محسوبتين في الرأس بحصة
/// الطبيب فقط (150+360=510 عبر _docAmount) — وهذا سلوك صيغة الأصل حرفياً.
/// قرار المالك: **الدخل = إجمالي المقبوض فعلياً اليوم** — فصار الرأس يجمع
/// مجاميع مجموعات الكشف نفسها (todayIncomeByClinic) مصدراً واحداً، ويستحيل
/// تناقضهما بعد اليوم.
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/archive/month_stats.dart'
    show isProsDebtPay;
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = getCurrentDate();

  /// بيانات اللقطة حرفياً.
  final debts = <Map<String, Object?>>[
    // دين تركيبات (فكفم) — دفعاته تدخل الكشف كاملة.
    {'id': 'dp_fakfam', 'type': 'prosthetic', 'name': 'فكفم'},
    // دين عادي (نبنبخ).
    {'id': 'dr_nbn', 'name': 'نبنبخ'},
  ];
  final records = <Map<String, Object?>>[
    // حشوان عصب (محمد علي) — تحويل، عيادتان.
    {'id': 'r1', 'date': today, 'name': 'محمد علي', 'clinic': 'الصفوة',
      'service': 'حشو عصب', 'amount': 1500, 'payment': 'تحويل'},
    {'id': 'r2', 'date': today, 'name': 'محمد علي', 'clinic': 'كاريزما',
      'service': 'حشو عصب', 'amount': 1500, 'payment': 'تحويل'},
    // دفعتا تركيبات (فكفم) — الرأس القديم كان يحسب حصة الطبيب فقط.
    {'id': 'r3', 'date': today, 'name': 'فكفم', 'clinic': 'الصفوة',
      'service': 'تركيبات', 'amount': 500, 'payment': 'كاش',
      'isDebtPayment': true, 'debtId': 'dp_fakfam', '_docAmount': 150},
    {'id': 'r4', 'date': today, 'name': 'فكفم', 'clinic': 'الصفوة',
      'service': 'تركيبات', 'amount': 1200, 'payment': 'تحويل',
      'isDebtPayment': true, 'debtId': 'dp_fakfam', '_docAmount': 360},
    // ثلاث دفعات دين عادية (نبنبخ).
    {'id': 'r5', 'date': today, 'name': 'نبنبخ', 'clinic': 'الصفوة',
      'service': 'حشو عصب', 'amount': 1000, 'payment': 'كاش',
      'isDebtPayment': true, 'debtId': 'dr_nbn'},
    {'id': 'r6', 'date': today, 'name': 'نبنبخ', 'clinic': 'الصفوة',
      'service': 'حشو عصب', 'amount': 800, 'payment': 'كاش',
      'isDebtPayment': true, 'debtId': 'dr_nbn'},
    {'id': 'r7', 'date': today, 'name': 'نبنبخ', 'clinic': 'الصفوة',
      'service': 'حشو عصب', 'amount': 1000, 'payment': 'كاش',
      'isDebtPayment': true, 'debtId': 'dr_nbn'},
    // أصل دين جديد اليوم — غير مقبوض: مستبعد من الدخل حتماً.
    {'id': 'r8', 'date': today, 'name': 'مؤجل', 'clinic': 'الصفوة',
      'service': 'خلع', 'amount': 999, 'payment': 'دين', 'isDebt': true},
    // مقبوض أمس — خارج اليوم.
    {'id': 'r9', 'date': '2020-01-01', 'name': 'قديم', 'clinic': 'الصفوة',
      'service': 'حشو', 'amount': 5000, 'payment': 'كاش'},
  ];
  final pros = <Map<String, Object?>>[];

  test('الرأس = الكشف = 7,500 (المقبوض كاملاً؛ لا حصة الطبيب)', () {
    final sheetTotal = todayIncomeByClinic(records, pros)
        .fold<num>(0, (s, g) => s + g.total);
    expect(sheetTotal, 7500, reason: 'كشف اليوم يجمع المقبوض كاملاً');
    expect(todayIncome(records, pros, debts), 7500,
        reason: 'تعريف المالك: الرأس يساوي الكشف');
    expect(todayIncome(records, pros, debts), sheetTotal,
        reason: 'مصدر واحد — يستحيل التناقض');
  });

  test('تفصيل الكشف بالعيادات كما في اللقطة: الصفوة 6,000 وكاريزما 1,500',
      () {
    final groups = todayIncomeByClinic(records, pros);
    final byClinic = {for (final g in groups) g.clinic: g.total};
    expect(byClinic['الصفوة'], 6000);
    expect(byClinic['كاريزما'], 1500);
  });

  test('الصيغة القديمة كانت تعطي 6,310 حرفياً (توثيق سبب التناقض)', () {
    // إعادة تركيب الصيغة القديمة: نقدي + حصة طبيب التركيبات ودفعات
    // ديونها + دفعات الديون العادية.
    final tRec = records.where((r) =>
        r['date'] == today &&
        !jsTruthy(r['isDebt']) &&
        !jsTruthy(r['isPros']) &&
        !jsTruthy(r['isDebtPayment']) &&
        r['payment'] != 'دين');
    final tPdP = records.where(
        (r) => r['date'] == today && isProsDebtPay(r, debts));
    final tDebtPays = records.where((r) =>
        r['date'] == today &&
        jsTruthy(r['isDebtPayment']) &&
        !isProsDebtPay(r, debts));
    final old = tRec.fold<num>(0, (s, r) => s + jsNumOr0(r['amount'])) +
        tPdP.fold<num>(0, (s, r) => s + pdDocAmt(r)) +
        tDebtPays.fold<num>(0, (s, r) => s + jsNumOr0(r['amount']));
    expect(old, 6310, reason: '3000 + (150+360) + 2800 — رقم اللقطة');
  });
}
