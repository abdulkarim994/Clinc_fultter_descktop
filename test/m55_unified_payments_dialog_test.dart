/// اختبار م55 (v34) — سجل الدفعات الموحّد في ملف المريض:
///   • نفس نافذة قسم الديون: معلومات الدين + شريط التقدم + دفعات مرقمة.
///   • **إلغاء دفعة بنقرتين خلال 3 ثوانٍ**: الأولى تسلّح «تأكيد»،
///     والثانية تحذف القسط وسجل دفعته وتعيد حساب المدفوع/المتبقي/الحالة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m55_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('سجل الدفعات من الملف: معلومات وإلغاء بنقرتين حتى القاعدة', (
    tester,
  ) async {
    final seed = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = seed.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش', 'تحويل'],
    });
    // دين بدفعتين + سجلا الدفعتين المرتبطان.
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'نوري',
      'patient_name': 'نوري',
      'clinic': 'ع1',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 1000,
      'total': 1000,
      'totalAmount': 1000,
      'paidAmount': 700,
      'remaining': 300,
      'status': 'partial',
      'installments': [
        {
          'id': 'i1',
          'amount': 400,
          'date': '2026-07-21',
          'payment': 'كاش',
          'recordId': 'pay1',
        },
        {
          'id': 'i2',
          'amount': 300,
          'date': '2026-07-22',
          'payment': 'تحويل',
          'recordId': 'pay2',
        },
      ],
    });
    repos.records.upsertLocal({
      'id': 'pay1',
      'name': 'نوري',
      'patient_name': 'نوري',
      'clinic': 'ع1',
      'service': 'دفعة دين — حشو',
      'date': '2026-07-21',
      'amount': 400,
      'payment': 'كاش',
      'isDebtPayment': true,
      'debtId': 'd1',
    });
    repos.records.upsertLocal({
      'id': 'pay2',
      'name': 'نوري',
      'patient_name': 'نوري',
      'clinic': 'ع1',
      'service': 'دفعة دين — حشو',
      'date': '2026-07-22',
      'amount': 300,
      'payment': 'تحويل',
      'isDebtPayment': true,
      'debtId': 'd1',
    });
    seed.dispose();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('patient-search')), 'نوري');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('patient-card-نوري')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('psec-debts')), warnIfMissed: false);
    await settle(tester);

    // v55 — «الدفعات» في الجزء الموسع: نوسّع رأس البطاقة أولاً.
    await tester.tap(find.byKey(const Key('pd-head-d1')), warnIfMissed: false);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('debt-payments-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('debt-payments-d1')));
    await settle(tester);

    // النافذة الموحّدة: معلومات الدين + النسبة + الدفعات المرقمة.
    expect(
      find.text('معلومات الدين'),
      findsOneWidget,
      reason: 'بطاقة المعلومات (من نافذة المالية)',
    );
    expect(find.text('70% مسدد'), findsWidgets);
    expect(find.text('الدفعات (2)'), findsOneWidget);
    expect(
      find.byKey(const Key('pay-cancel-i2')),
      findsOneWidget,
      reason: 'زر إلغاء لكل دفعة — كان مفقوداً في الملف',
    );

    // النقرة الأولى تسلّح «تأكيد» ولا تحذف.
    await tester.tap(find.byKey(const Key('pay-cancel-i2')));
    await tester.pump();
    expect(find.text('تأكيد'), findsOneWidget);
    ProviderContainer chk() => ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    var c = chk();
    expect(
      (c.read(reposProvider).debts.getById('d1')!['installments'] as List)
          .length,
      2,
      reason: 'لم يُحذف شيء بعد النقرة الأولى',
    );
    c.dispose();

    // النقرة الثانية تنفّذ الإلغاء.
    await tester.tap(find.byKey(const Key('pay-cancel-i2')));
    await settle(tester);
    expect(
      find.text('الدفعات (1)'),
      findsOneWidget,
      reason: 'القائمة تحدثت داخل النافذة',
    );

    c = chk();
    final debt = c.read(reposProvider).debts.getById('d1')!;
    final insts = (debt['installments'] as List)
        .whereType<Map>()
        .where((m) => m['_deleted'] != 1)
        .toList();
    expect(insts.map((m) => m['id']), ['i1'], reason: 'قسط i2 أُلغي');
    expect(debt['paidAmount'], 400, reason: 'المدفوع أعيد حسابه');
    expect(debt['remaining'], 600, reason: 'المتبقي أعيد حسابه');
    expect(debt['status'], 'partial');
    expect(
      c.read(reposProvider).records.getById('pay2'),
      isNull,
      reason: 'سجل الدفعة الملغاة حُذف',
    );
    expect(c.read(reposProvider).records.getById('pay1'), isNotNull);
    c.dispose();

    // البطاقة خلف النافذة تعكس المجاميع الجديدة بعد الإغلاق.
    await tester.tap(find.byKey(const Key('pays-close')));
    await settle(tester);
    expect(
      find.text('40% مسدد'),
      findsWidgets,
      reason: '400 من 1000 بعد الإلغاء',
    );
  });
}
