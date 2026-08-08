/// اختبارات م99 (واجهة) — قسم «كشف مالي»: التنقّل إليه، الإجمالي، ورقائق
/// الفلترة متعددة الاختيار تعيد الحساب حيّاً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m99ui_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'clinics': ['ع1', 'ع2'],
    'services': ['حشو'],
    'payments': ['كاش', 'تحويل'],
  };

  Future<void> boot(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
    await c
        .read(authProvider.notifier)
        .login('doc@clinic.ly', 'secret12', true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', config());
    final today = getCurrentDate();
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: today,
        amount: 100,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'هدى',
        date: today,
        amount: 400,
        clinic: 'ع2',
        service: 'حشو',
        payment: 'تحويل',
      ),
    );
    c.dispose();
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
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('المالية'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const Key('fin-seg-statement')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('st-total'))).data!;

  // م109 — الرقائق انتقلت لورقة الفلاتر السفلية (رأسٌ بصفٍّ واحد).
  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('st-filters')), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 60)); // خارج الورقة
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('التنقّل للكشف المالي يعرض الإجمالي 500 وأدواته', (tester) async {
    await boot(tester);
    expect(find.byKey(const Key('st-search')), findsOneWidget);
    // م109: زرا المدى والفلاتر بدل زرّي من/إلى وصفوف الرقائق.
    expect(find.byKey(const Key('st-range')), findsOneWidget);
    expect(find.byKey(const Key('st-filters')), findsOneWidget);
    expect(find.byKey(const Key('st-print')), findsOneWidget);
    expect(total(tester), contains('500'));
  });

  testWidgets('رقاقة عيادة ع2 (من ورقة الفلاتر) تحصر الإجمالي في 400', (
    tester,
  ) async {
    await boot(tester);
    await openFilters(tester);
    await tester.tap(
      find.byKey(const Key('st-clinic-ع2')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await closeSheet(tester);
    // شارة عدّ الفلاتر المفعلة ظاهرة على الزر.
    expect(find.byKey(const Key('st-filters-count')), findsOneWidget);
    expect(
      total(tester),
      contains('400'),
      reason: 'م99: الفلترة متعددة الاختيار تعيد الحساب حيّاً',
    );
  });

  testWidgets('رقاقة فئة «تحويل» (من الورقة) تُبقي 400 فقط', (tester) async {
    await boot(tester);
    await openFilters(tester);
    await tester.ensureVisible(find.byKey(const Key('st-cat-تحويل')));
    await tester.tap(
      find.byKey(const Key('st-cat-تحويل')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await closeSheet(tester);
    expect(total(tester), contains('400'));
  });
}
