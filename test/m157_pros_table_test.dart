/// م157 — جدول التركيبات الجديد: بناء الصفوف النقي (حالات الشهر +
/// دفعات ديون الشهور السابقة صفوفاً مستقلة موسومة «دفعة دين»)،
/// وتلميح الدفعات خارج الشهر، وصف الإجمالي الشامل.
library;

import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // شريحة شهر 2026-08: حالة غير دين + حالة دين أنشئت هذا الشهر،
  // ودفعة هذا الشهر لدينٍ من شهر 2026-07 (يجب أن تظهر صفاً مستقلاً).
  // كامل جدول الديون (يتجاوز قصّ الشهر): دين الشهر الماضي المدفوع عليه.
  List<Map<String, Object?>> allDebts() => [
        {
          'id': 'd-new',
          'type': 'prosthetic',
          'prostheticId': 'p-2',
          'date': '2026-08-03',
          'name': 'خالد',
          'clinic': 'ع1',
          'status': 'partial',
          'paidAmount': 800,
          'remaining': 1200,
          'installments': [
            {'date': '2026-08-03', 'amount': 500},
            {'date': '2026-09-01', 'amount': 300},
          ],
        },
        {
          'id': 'd-old',
          'type': 'prosthetic',
          'prostheticId': 'p-old',
          'date': '2026-07-10',
          'name': 'سالم',
          'clinic': 'ع1',
          'status': 'partial',
          'paidAmount': 900,
          'remaining': 600,
          'service': 'تركيبات',
          'installments': [
            {'date': '2026-07-10', 'amount': 500},
            {'date': '2026-08-05', 'amount': 400},
          ],
        },
      ];

  List<Map<String, Object?>> allPros() => [
        {
          'id': 'p-old',
          'date': '2026-07-10',
          'name': 'سالم',
          'clinic': 'ع1',
          'total': 1500,
          'labName': 'معمل النور',
          'prosType': 'Ifk',
          'prosUnits': 4,
          'isDebt': 1,
        },
      ];

  TreasurySlice slice() => TreasurySlice(
        '2026-08',
        records: [
          // دفعة دين تركيبات واردة هذا الشهر لحالة الشهر الماضي.
          {
            'id': 'pay-1',
            'date': '2026-08-05',
            'name': 'سالم',
            'clinic': 'ع1',
            'amount': 400,
            '_fullAmount': 400,
            'payment': 'كاش',
            'isDebtPayment': 1,
            'debtId': 'd-old',
          },
        ],
        prosthetics: [
          // غير دين — مدفوعة كاملة.
          {
            'id': 'p-1',
            'date': '2026-08-02',
            'name': 'محمد',
            'clinic': 'ع1',
            'total': 1500,
            'labValue': 300,
            'labName': 'معمل النور',
            'prosType': 'زيركون',
            'prosUnits': 3,
            'payment': 'كاش',
            'isDebt': 0,
          },
          // دين أنشئ هذا الشهر — عليه دفعة الشهرَ القادم (خارج الشهر).
          {
            'id': 'p-2',
            'date': '2026-08-03',
            'name': 'خالد',
            'clinic': 'ع1',
            'total': 2000,
            'labValue': 500,
            'labName': 'معمل الفجر',
            'prosType': 'ببك',
            'prosUnits': 2,
            'payment': 'دين',
            'isDebt': 1,
          },
        ],
        // جدول الديون الكامل يُمرَّر للشريحة كما في التطبيق (المستودع
        // يسلّم كل الديون والشريحة تقصّ ما يلزمها داخلياً).
        debts: allDebts(),
      );

  group('م157 — prosCaseRows', () {
    test('حالات الشهر + دفعة دين الشهر السابق صفاً مستقلاً موسوماً', () {
      final rows = prosCaseRows(slice(), 'ع1',
          allDebts: allDebts(), allPros: allPros(), doctorPct: 50);
      expect(rows.length, 3, reason: 'حالتان + دفعة دين مستقلة');

      final pay = rows.singleWhere((r) => r.isDebtPay);
      expect(pay.name, 'سالم');
      expect(pay.date, '2026-08-05', reason: 'تاريخ الدفعة لا الحالة');
      expect(pay.total, 400);
      expect(pay.paid, 400);
      expect(pay.remaining, 600, reason: 'المتبقي الحالي من الدين');
      expect(pay.lab, 'معمل النور',
          reason: 'حقول الحالة الأصلية عبر prostheticId');
      expect(pay.work, 'Ifk');
      expect(pay.units, 4);
    });

    test('غير الدين مدفوعة كاملة بلا متبقٍ', () {
      final rows = prosCaseRows(slice(), 'ع1',
          allDebts: allDebts(), allPros: allPros(), doctorPct: 50);
      final full = rows.singleWhere((r) => r.name == 'محمد');
      expect(full.paid, full.total);
      expect(full.remaining, 0);
      expect(full.otherMonthPays, isEmpty);
    });

    test('إشارة الدفعات خارج الشهر بتواريخها وقيمها', () {
      final rows = prosCaseRows(slice(), 'ع1',
          allDebts: allDebts(), allPros: allPros(), doctorPct: 50);
      final debtCase = rows.singleWhere((r) => r.name == 'خالد');
      expect(debtCase.paid, 800);
      expect(debtCase.remaining, 1200);
      expect(debtCase.otherMonthPays.length, 1,
          reason: 'دفعة 2026-09 وحدها خارج شهر العرض');
      expect(debtCase.otherMonthPays.single.date, '2026-09-01');
      expect(debtCase.otherMonthPays.single.amount, 300);
    });

    test('دفعة لحالةٍ أنشئت في نفس الشهر لا تتكرر صفاً مستقلاً', () {
      final s = TreasurySlice(
        '2026-08',
        records: [
          {
            'id': 'pay-x',
            'date': '2026-08-06',
            'name': 'خالد',
            'clinic': 'ع1',
            'amount': 300,
            '_fullAmount': 300,
            'payment': 'كاش',
            'isDebtPayment': 1,
            'debtId': 'd-new',
          },
        ],
        prosthetics: slice().pros,
        debts: allDebts(),
      );
      final rows = prosCaseRows(s, 'ع1',
          allDebts: allDebts(), allPros: allPros(), doctorPct: 50);
      expect(rows.where((r) => r.isDebtPay), isEmpty,
          reason: 'دين هذا الشهر مدفوعه ظاهر في صف حالته لا صفاً ثانياً');
    });
  });
}
