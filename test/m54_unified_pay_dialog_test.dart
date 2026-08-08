/// اختبار م54 (v33) — نافذة تسجيل الدفعة الموحّدة في ملف المريض:
///   • نفس نافذة قسم الديون: منتقي التاريخ + قائمة طريقة الدفع + معاينة.
///   • اختيار «تحويل» يسجّل القسط وسجل الدفعة بطريقة «تحويل» (كانت
///     النسخة القديمة تثبّت «كاش» بالكود).
///   • دين تركيبات يعرض «المعمل المتبقي» وتحذير الخصم.
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m54_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(
    WidgetTester tester, {
    required Map<String, Object?> debt,
  }) async {
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
      'doctorPct': 40,
    });
    repos.debts.upsertLocal(debt);
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

    // إلى ملف المريض ← قسم الديون.
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
    // v55 — البطاقة المطوية: زر «دفعة» المدمج بالرأس يفتح النافذة.
    final payKey = Key('pay-${debt['id']}');
    await tester.ensureVisible(find.byKey(payKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(payKey), warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('دفعة «تحويل» من الملف تُسجَّل تحويلاً لا كاشاً', (tester) async {
    await boot(
      tester,
      debt: {
        'id': 'd1',
        'name': 'نوري',
        'patient_name': 'نوري',
        'clinic': 'ع1',
        'service': 'حشو',
        'date': '2026-07-20',
        'amount': 500,
        'total': 500,
        'totalAmount': 500,
        'paidAmount': 0,
        'remaining': 500,
        'status': 'unpaid',
        'installments': <Object?>[],
      },
    );

    // النافذة الموحّدة: التاريخ + طريقة الدفع + المتبقي.
    expect(find.byKey(const Key('inst-amount')), findsOneWidget);
    expect(find.byKey(const Key('inst-date')), findsOneWidget);
    expect(
      find.byKey(const Key('inst-payment')),
      findsOneWidget,
      reason: 'قائمة طريقة الدفع موجودة (كانت مفقودة في الملف)',
    );
    expect(find.text('المتبقي:'), findsOneWidget);

    // قيمة + اختيار «تحويل» + المعاينة تظهر.
    await tester.enterText(find.byKey(const Key('inst-amount')), '300');
    await settle(tester);
    expect(find.text('معاينة:'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inst-payment')));
    await settle(tester);
    await tester.tap(find.text('تحويل').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('inst-confirm')));
    await settle(tester);

    // القاعدة: القسط وسجل الدفعة كلاهما «تحويل».
    final chk = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    addTearDown(chk.dispose);
    final repos = chk.read(reposProvider);
    final debt = repos.debts.getById('d1')!;
    final inst = (debt['installments'] as List).whereType<Map>().first;
    expect(inst['payment'], 'تحويل', reason: 'القسط بطريقة الدفع المختارة');
    final payRec = repos.records.getAll().whereType<Map>().firstWhere(
      (r) => r['isDebtPayment'] == true || '${r['service']}'.contains('دفعة'),
    );
    expect(
      payRec['payment'],
      'تحويل',
      reason: 'سجل الدفعة تحويل لا كاش — علة المرحلة',
    );
    expect(debt['paidAmount'], 300);
    expect(debt['remaining'], 200);
  });

  testWidgets('دين تركيبات: تحذير المعمل والمعاينة المقسمة في الملف', (
    tester,
  ) async {
    await boot(
      tester,
      debt: {
        'id': 'd2',
        'name': 'نوري',
        'patient_name': 'نوري',
        'clinic': 'ع1',
        'service': 'زيركون',
        'date': '2026-07-20',
        'type': 'prosthetic',
        'prostheticId': 'pr9',
        'amount': 800,
        'total': 800,
        'totalAmount': 800,
        'paidAmount': 0,
        'remaining': 800,
        'status': 'unpaid',
        'labValue': 300,
        'labPaid': 0,
        'installments': <Object?>[],
      },
    );

    expect(
      find.text('المعمل المتبقي:'),
      findsOneWidget,
      reason: 'سطر المعمل للتركيبات (من نافذة المالية)',
    );
    expect(find.text('⚠ تُخصم أولاً من المعمل ثم الربح'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('inst-amount')), '400');
    await settle(tester);
    expect(find.text('للمعمل:'), findsOneWidget);
    expect(find.textContaining('ربح الطبيب'), findsOneWidget);
    expect(find.textContaining('ربح العيادة'), findsOneWidget);
  });
}
