/// اختبار م56 (v35) — حصة العيادة من دفعات ديون التركيبات تُحسب في
/// **شهر الدفع** (مرآة حصة الطبيب ومطابقة للخزينة):
///   • سيناريو اللقطة حرفياً: تركيبة 5,000 بمعمل 1,000 ونسبة 40٪،
///     دفعة أولى 1,000 في يوليو (كلها للمعمل)، والمتبقي 4,000 في أغسطس
///     ⇒ تقرير أغسطس: طبيب 1,600 **وعيادة 2,400** (كانت 0 — علة المرحلة).
///   • مجموع الأشهر = الحصة الكاملة بلا تكرار ولا فقد.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m56_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('دفعة المتبقي في شهر لاحق: عيادتها تظهر في شهر الدفع كالخزينة',
      () {
    final repos = c.read(reposProvider);
    const config = <String, Object?>{
      'doctorPct': 40,
      'clinics': ['الصفوة'],
      'payments': ['كاش'],
    };
    const snap = <String, Object?>{'doctorPct': 40, 'isPros': true};

    // ── يوليو: تركيبة بدين + دفعة أولى 1,000 (كما يكتبها التطبيق) ──
    repos.prosthetics.upsertLocal({
      'id': 'pr1', 'date': '2026-07-10', 'name': 'محمد',
      'patient_name': 'محمد', 'total': 5000, 'labValue': 1000,
      '_rateSnapshot': snap,
      'doctorShare': 1600, 'clinicShare': 2400,
      'payment': 'دين', 'clinic': 'الصفوة', 'clinic_id': 'الصفوة',
      'isDebt': true, '_t': 'p',
    });
    repos.debts.upsertLocal({
      'id': 'd1', 'date': '2026-07-10', 'name': 'محمد',
      'patient_name': 'محمد', 'type': 'prosthetic',
      'status': 'partial', 'total': 5000, 'totalAmount': 5000,
      'labValue': 1000, 'labPaid': 1000,
      'paidAmount': 1000, 'remaining': 4000,
      'doctorEarned': 0, 'payment': 'كاش',
      'clinic': 'الصفوة', 'clinic_id': 'الصفوة',
      'service': 'زيركون', 'prostheticId': 'pr1',
      'installments': [
        {'id': 'i1', 'amount': 1000, 'date': '2026-07-10',
         'payment': 'كاش', 'recordId': 'fp1'},
      ],
      '_t': 'd',
    });
    repos.records.upsertLocal({
      'id': 'fp1', 'date': '2026-07-10', 'name': 'محمد',
      'patient_name': 'محمد', 'amount': 1000,
      '_fullAmount': 1000, '_labAmount': 1000, '_docAmount': 0,
      '_rateSnapshot': snap, 'clinic': 'الصفوة',
      'clinic_id': 'الصفوة', 'service': 'تركيبات (دفعة أولى)',
      'payment': 'كاش', 'isDebt': 0, 'isPros': 0,
      'isDebtPayment': 1, 'debtId': 'd1',
    });

    // ── أغسطس: دفعة المتبقي 4,000 عبر مسار الدفع الحقيقي ──
    final debt = Map<String, Object?>.from(repos.debts.getById('d1')!);
    payDebtInstallment(repos, config, debt,
        amount: 4000, date: '2026-08-15', payment: 'كاش');

    List<Map<String, Object?>> all(dynamic repo) => [
          for (final r in repo.getAll()) Map<String, Object?>.from(r),
        ];
    final records = all(repos.records);
    final pros = all(repos.prosthetics);
    final debts = all(repos.debts);

    // ── تقرير أغسطس: طبيب 1,600 وعيادة 2,400 (أرقام اللقطة) ──
    final aug =
        getMonthlyReport(records, pros, debts, '2026-08', 40);
    expect(aug.prosDoctor, 1600, reason: 'حصة الطبيب بشهر الدفع');
    expect(aug.prosClinic, 2400,
        reason: 'حصة العيادة بشهر الدفع — كانت 0 (علة المرحلة)');
    expect(aug.clinicTotal, 2400);
    expect(aug.doctorTotal, 1600);

    // ── تقرير يوليو: الدفعة الأولى كلها للمعمل ⇒ طبيب 0 وعيادة 0 ──
    final jul =
        getMonthlyReport(records, pros, debts, '2026-07', 40);
    expect(jul.prosDoctor, 0);
    expect(jul.prosClinic, 0,
        reason: 'لا تُحتسب الحصة الكاملة قبل قبضها');

    // ── مجموع الأشهر = الحصة الكاملة (2,400) بلا تكرار ولا فقد ──
    expect(jul.prosClinic + aug.prosClinic, 2400);
    expect(jul.prosDoctor + aug.prosDoctor, 1600);

    // ── صف عيادة الصفوة في أرباح أغسطس يطابق ──
    final rows = monthlyClinicRows('2026-08',
        records: records,
        prosthetics: pros,
        debts: debts,
        clinics: const ['الصفوة'],
        doctorPct: 40);
    expect(rows, hasLength(1));
    expect(rows.single.clinicShare, 2400,
        reason: 'بطاقة الصفوة الشهرية تعرض 2,400');
    expect(rows.single.doctor, 1600);
  });

  test('تركيبة غير دين: حصة عيادتها كاملة في شهرها (بلا تغيير)', () {
    final repos = c.read(reposProvider);
    repos.prosthetics.upsertLocal({
      'id': 'pr2', 'date': '2026-07-05', 'name': 'سعاد',
      'patient_name': 'سعاد', 'total': 900, 'labValue': 300,
      'doctorShare': 240, 'clinicShare': 360,
      'payment': 'كاش', 'clinic': 'الصفوة', 'clinic_id': 'الصفوة',
      'isDebt': 0, '_t': 'p',
    });
    final rep = getMonthlyReport(
        const [],
        [
          for (final p in repos.prosthetics.getAll())
            Map<String, Object?>.from(p)
        ],
        const [],
        '2026-07',
        40);
    expect(rep.prosClinic, 360);
    expect(jsNumOr0(rep.prosDoctor), 240);
  });
}
