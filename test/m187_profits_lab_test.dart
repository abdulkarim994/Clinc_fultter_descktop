/// اختبارات م187/ج — قيمة المختبرات في الأرباح.
///
/// بلاغ المالك: «الإجمالي بعد تحديد النسبة يبقى فرق قيمة المعمل».
/// وسببه بنيويّ لا خطأ حساب: قيمة المعمل تُخصم **قبل** تقسيم النِّسَب
/// (`net = القيمة − المعمل` ثم يُقسم)، فالإيراد يحويها والحصتان لا —
/// فيبقى الفرق بلا صفٍّ يفسّره.
///
/// **العقد المحروس هنا (وهو جوهر الإصلاح):**
///     صافي بعد المختبرات (الإيراد − المختبرات) = ربح الطبيب + ربح العيادة
/// فمتى صحّ هذا صار الجدول **متحقِّقاً من نفسه** بنظرة، ومتى انكسر فثمة
/// خطأٌ حقيقيٌّ في توزيع الحصص يجب أن يُكشف — لا أن يُخفى في فرقٍ صامت.
library;

import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

/// تركيبة غير دَينية: القيمة والمعمل والحصص المجمّدة كما يكتبها الحافظ.
JMap pros({
  required String id,
  required String date,
  String clinic = 'ع1',
  required num total,
  required num lab,
  required num doctorPct,
}) {
  final net = total - lab;
  final doc = (net * doctorPct / 100).round();
  return {
    'id': id,
    '_t': 'p',
    'date': date,
    'clinic': clinic,
    'clinic_id': clinic,
    'name': 'مريض $id',
    'total': total,
    'labValue': lab,
    'doctorShare': doc,
    'clinicShare': net - doc,
    'payment': 'كاش',
    'isDebt': 0,
    '_rateSnapshot': {'doctorPct': doctorPct},
  };
}

/// سجل عادي مقبوض (لا معمل فيه).
JMap rec({
  required String id,
  required String date,
  String clinic = 'ع1',
  required num amount,
  required num doctorPct,
}) => {
      'id': id,
      '_t': 'r',
      'date': date,
      'clinic': clinic,
      'clinic_id': clinic,
      'name': 'مريض $id',
      'amount': amount,
      'payment': 'كاش',
      'isDebt': 0,
      'isPros': 0,
      'isDebtPayment': 0,
      '_rateSnapshot': {'doctorPct': doctorPct},
    };

void main() {
  const month = '2026-08';
  const pct = 40;

  group('م187/ج — العقد: صافي بعد المختبرات = مجموع الحصتين', () {
    test('تركيبة بمعمل: الفرق كان قيمة المعمل — والصافي يطابق الحصتين', () {
      final prosthetics = [
        pros(
            id: 'p1',
            date: '$month-05',
            total: 3000,
            lab: 1200,
            doctorPct: pct),
      ];
      final rep = getMonthlyReport(const [], prosthetics, const [], month, pct);

      // ما كان يحيّر المالك: الإجمالي لا يساوي مجموع الحصتين.
      expect(rep.grandTotal, 3000);
      expect(rep.prosLabCost, 1200);
      expect(rep.grandTotal - (rep.doctorTotal + rep.clinicTotal), 1200,
          reason: 'الفرق = قيمة المعمل بالضبط (لا خطأ حساب)');

      // والعقد الجديد: بعد خصم المختبرات يتطابق تماماً.
      expect(rep.grandTotal - rep.prosLabCost,
          rep.doctorTotal + rep.clinicTotal,
          reason: 'م187: صافي بعد المختبرات = الطبيب + العيادة');
      expect(rep.doctorTotal, 720); // 1800 × 40٪
      expect(rep.clinicTotal, 1080);
    });

    test('خلطة سجلات وتركيبات: العقد يصمد على المجموع', () {
      final records = [
        rec(id: 'r1', date: '$month-02', amount: 500, doctorPct: pct),
        rec(id: 'r2', date: '$month-03', amount: 700, doctorPct: pct),
      ];
      final prosthetics = [
        pros(
            id: 'p1',
            date: '$month-05',
            total: 2000,
            lab: 800,
            doctorPct: pct),
        pros(
            id: 'p2',
            date: '$month-07',
            total: 1500,
            lab: 500,
            doctorPct: pct),
      ];
      final rep =
          getMonthlyReport(records, prosthetics, const [], month, pct);
      expect(rep.prosLabCost, 1300);
      expect(rep.grandTotal - rep.prosLabCost,
          rep.doctorTotal + rep.clinicTotal);
    });

    test('بلا تركيبات: المختبرات صفر والإجمالي يساوي الحصتين مباشرة', () {
      final rep = getMonthlyReport(
          [rec(id: 'r1', date: '$month-02', amount: 900, doctorPct: pct)],
          const [],
          const [],
          month,
          pct);
      expect(rep.prosLabCost, 0);
      expect(rep.grandTotal, rep.doctorTotal + rep.clinicTotal);
    });
  });

  group('م187/ج — صفوف العيادات تحمل قيمة معملها', () {
    test('كل عيادة بمعملها، والعيادة بلا تركيبات تبقى صفراً', () {
      final prosthetics = [
        pros(
            id: 'p1',
            date: '$month-05',
            clinic: 'عيادة أ',
            total: 2000,
            lab: 800,
            doctorPct: pct),
      ];
      final records = [
        rec(
            id: 'r1',
            date: '$month-06',
            clinic: 'عيادة ب',
            amount: 600,
            doctorPct: pct),
      ];
      final rows = monthlyClinicRows(month,
          records: records,
          prosthetics: prosthetics,
          debts: const [],
          clinics: const ['عيادة أ', 'عيادة ب'],
          doctorPct: pct);
      final a = rows.firstWhere((r) => r.name == 'عيادة أ');
      final b = rows.firstWhere((r) => r.name == 'عيادة ب');
      expect(a.lab, 800);
      expect(b.lab, 0, reason: 'لا تركيبات ⇒ لا معمل');
      // العقد على مستوى العيادة أيضاً.
      expect(a.revenue - a.lab, a.doctor + a.clinicShare);
      expect(b.revenue - b.lab, b.doctor + b.clinicShare);
    });
  });

  group('م187/ج — التقرير السنوي', () {
    test('مختبرات السنة = مجموع أشهرها، وafterLab يطابق الحصتين', () {
      final prosthetics = [
        pros(
            id: 'p1', date: '2026-03-05', total: 1000, lab: 400,
            doctorPct: pct),
        pros(
            id: 'p2', date: '2026-09-11', total: 2000, lab: 600,
            doctorPct: pct),
      ];
      final rep = yearReport('2026',
          records: const [],
          prosthetics: prosthetics,
          debts: const [],
          doctorPct: pct);
      expect(rep.lab, 1000, reason: '400 + 600');
      expect(rep.afterLab, rep.doctor + rep.clinic);
      // وتفصيل الأشهر يحمل معمله في شهره وحده.
      expect(rep.months[2].lab, 400); // آذار
      expect(rep.months[8].lab, 600); // أيلول
      expect(rep.months[0].lab, 0);
      expect(rep.months[2].afterLab,
          rep.months[2].doctor + rep.months[2].clinic);
    });

    test('لقطة عيادة محذوفة (م170) بلا معمل ⇒ صفر ولا تكسر المجموع', () {
      final rep = yearReport('2026',
          records: const [],
          prosthetics: const [],
          debts: const [],
          doctorPct: pct,
          frozenRowsOf: (m) => m == '2026-05'
              ? const [ClinicProfitRow('عيادة مُزالة', 900, 360, 540)]
              : const []);
      expect(rep.revenue, 900);
      expect(rep.lab, 0,
          reason: 'م187: اللقطات المجمّدة لا تحمل قيمة معمل — موثَّق');
      expect(rep.afterLab, rep.doctor + rep.clinic);
    });
  });
}
