// م178 — اختبارات المنطق السنوي النقي: yearReport وyearlyClinicRows
// وyoyPct. العقد الذهبي: السنة = مجموع أشهرها الاثني عشر حرفياً عبر
// getMonthlyReport نفسها — فنطابق التقرير السنوي بجمع الشهري يدوياً.
import 'package:flutter_test/flutter_test.dart';

import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';

typedef J = Map<String, Object?>;

J rec(String date, num amount,
        {String clinic = 'ع1',
        String payment = 'كاش',
        num? doctorPctSnap}) =>
    {
      'id': 'r-$date-$amount-$clinic',
      'date': date,
      'amount': amount,
      'clinic': clinic,
      'payment': payment,
      'doctorPct': ?doctorPctSnap,
    };

J pros(String date, num total, num labValue, num clinicShare,
        {String clinic = 'ع1'}) =>
    {
      'id': 'p-$date-$total',
      'date': date,
      'total': total,
      'labValue': labValue,
      'clinicShare': clinicShare,
      'clinic': clinic,
      'isDebt': 0,
    };

void main() {
  group('م178 — yearReport', () {
    final records = [
      rec('2026-01-10', 1000),
      rec('2026-01-20', 500, payment: 'تحويل'),
      rec('2026-03-05', 2000, clinic: 'ع2'),
      rec('2026-12-31', 300),
      // سنة أخرى — يجب ألا تدخل تقرير 2026.
      rec('2025-06-15', 9999),
    ];
    final prosthetics = [
      pros('2026-01-15', 800, 300, 250),
      pros('2025-02-10', 700, 200, 250),
    ];
    final debts = <J>[];

    test('السنة = مجموع أشهرها الاثني عشر حرفياً (العقد الذهبي)', () {
      final rep = yearReport('2026',
          records: records,
          prosthetics: prosthetics,
          debts: debts,
          doctorPct: 50);
      num rev = 0, doc = 0, clin = 0;
      for (var i = 0; i < 12; i++) {
        final m = '2026-${'${i + 1}'.padLeft(2, '0')}';
        final mr =
            getMonthlyReport(records, prosthetics, debts, m, 50);
        rev += mr.grandTotal;
        doc += mr.doctorTotal;
        clin += mr.clinicTotal;
      }
      expect(rep.revenue, rev);
      expect(rep.doctor, doc);
      expect(rep.clinic, clin);
      expect(rep.months.length, 12);
    });

    test('سنة 2025 لا تتلوث بأرقام 2026 والعكس', () {
      final r26 = yearReport('2026',
          records: records,
          prosthetics: prosthetics,
          debts: debts,
          doctorPct: 50);
      final r25 = yearReport('2025',
          records: records,
          prosthetics: prosthetics,
          debts: debts,
          doctorPct: 50);
      // 2026: سجلات 1000+500+2000+300 + تركيبة 800 = 4600.
      expect(r26.revenue, 4600);
      // 2025: سجل 9999 + تركيبة 700 = 10699.
      expect(r25.revenue, 10699);
    });

    test('المصروفات المحقونة تدخل شهرها والصافي = العيادة − المصروفات',
        () {
      final rep = yearReport('2026',
          records: records,
          prosthetics: prosthetics,
          debts: debts,
          doctorPct: 50,
          expensesOf: (m) => m == '2026-01' ? 400 : 0);
      expect(rep.expenses, 400);
      expect(rep.net, rep.clinic - 400);
      expect(rep.months[0].expenses, 400);
      expect(rep.months[1].expenses, 0);
      // صافي الشهر = حصة عيادته − مصروفاته.
      expect(rep.months[0].net,
          rep.months[0].clinic - rep.months[0].expenses);
    });

    test('اللقطات المجمدة (م170) تدخل شهرها التاريخي', () {
      final rep = yearReport('2026',
          records: const [],
          prosthetics: const [],
          debts: const [],
          doctorPct: 50,
          frozenRowsOf: (m) => m == '2026-02'
              ? const [ClinicProfitRow('محذوفة 🔒', 1500, 700, 800)]
              : const []);
      expect(rep.revenue, 1500);
      expect(rep.doctor, 700);
      expect(rep.clinic, 800);
      expect(rep.months[1].revenue, 1500);
      expect(rep.months[0].isEmpty, isTrue);
    });

    test('هامش الصافي % — و0 عند غياب الإيراد', () {
      final rep = yearReport('2026',
          records: [rec('2026-05-01', 1000)],
          prosthetics: const [],
          debts: const [],
          doctorPct: 50,
          expensesOf: (m) => m == '2026-05' ? 100 : 0);
      // إيراد 1000، عيادة 500، مصروفات 100 ⇒ صافٍ 400 ⇒ هامش 40%.
      expect(rep.marginPct, 40);
      final empty = yearReport('2024',
          records: const [],
          prosthetics: const [],
          debts: const [],
          doctorPct: 50);
      expect(empty.marginPct, 0);
      expect(empty.revenue, 0);
    });
  });

  group('م178 — yearlyClinicRows', () {
    test('تجميع العيادة عبر الأشهر والترتيب بالإيراد تنازلياً', () {
      final records = [
        rec('2026-01-10', 1000, clinic: 'ع1'),
        rec('2026-02-10', 2000, clinic: 'ع1'),
        rec('2026-03-10', 5000, clinic: 'ع2'),
      ];
      final rows = yearlyClinicRows('2026',
          records: records,
          prosthetics: const [],
          debts: const [],
          clinics: const ['ع1', 'ع2'],
          doctorPct: 50);
      expect(rows.length, 2);
      // ع2 أولاً (إيراد أعلى).
      expect(rows[0].name, 'ع2');
      expect(rows[0].revenue, 5000);
      expect(rows[1].name, 'ع1');
      expect(rows[1].revenue, 3000);
      // حصتا الطبيب والعيادة تتجمعان (50%).
      expect(rows[1].doctor, 1500);
      expect(rows[1].clinicShare, 1500);
    });

    test('اللقطات المجمدة تُجمع باسمها عبر الأشهر', () {
      final rows = yearlyClinicRows('2026',
          records: const [],
          prosthetics: const [],
          debts: const [],
          clinics: const [],
          doctorPct: 50,
          frozenRowsOf: (m) => (m == '2026-01' || m == '2026-02')
              ? const [ClinicProfitRow('قديمة 🔒', 100, 40, 60)]
              : const []);
      expect(rows.length, 1);
      expect(rows[0].name, 'قديمة 🔒');
      expect(rows[0].revenue, 200);
      expect(rows[0].doctor, 80);
      expect(rows[0].clinicShare, 120);
    });

    test('عيادة بلا أي أرقام لا يظهر صفها', () {
      final rows = yearlyClinicRows('2026',
          records: [rec('2026-01-10', 100, clinic: 'ع1')],
          prosthetics: const [],
          debts: const [],
          clinics: const ['ع1', 'خاملة'],
          doctorPct: 50);
      expect(rows.length, 1);
      expect(rows[0].name, 'ع1');
    });
  });

  group('م178 — yoyPct', () {
    test('نمو موجب وهبوط سالب', () {
      expect(yoyPct(120, 100), 20);
      expect(yoyPct(80, 100), -20);
    });
    test('لا أساس مقارنة ⇒ null', () {
      expect(yoyPct(120, 0), isNull);
      expect(yoyPct(120, -5), isNull);
    });
  });
}
