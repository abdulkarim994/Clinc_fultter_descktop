/// ============================================================================
///  اختبارات تبويبَي «الخزينة» و«الديون» على سطح المكتب
/// ============================================================================
///
///  يتبع نمط desktop_shell_smoke_test.dart حرفياً:
///    • debugForceDesktopUi = true + physicalSize 1600×1000.
///    • تبويب الخزينة (Key('desk-tab-treasury')): الحالة الفارغة أو القائمة
///      تظهر دون أخطاء.
///    • تبويب الديون (Key('desk-tab-debts')): الحالة الفارغة أو القائمة
///      تظهر دون أخطاء.
///    • زرع دين واحد وتحقق من ظهوره في القائمة + اختياره يعرض التفاصيل.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/desktop/screens/treasury_desktop.dart';
import 'package:dental_clinic_flutter/features/desktop/screens/debts_desktop.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_fin_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  /// دالة بوت مشتركة — نفس نمط desktop_shell_smoke_test.dart.
  Future<void> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
    });
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
    await tester.pump(const Duration(milliseconds: 200));
  }

  // ── تبويب الخزينة ──────────────────────────────────────────────────────────

  testWidgets('تبويب الخزينة يعرض DesktopTreasuryScreen دون أخطاء',
      (tester) async {
    await boot(tester);

    // التبويب موجود في الشريط الجانبي.
    expect(find.byKey(const Key('desk-tab-treasury')), findsOneWidget);

    // فتح تبويب الخزينة.
    await tester.tap(find.byKey(const Key('desk-tab-treasury')));
    await tester.pump(const Duration(milliseconds: 300));

    // الشاشة تعرض DesktopTreasuryScreen.
    expect(find.byType(DesktopTreasuryScreen), findsOneWidget);

    // لا توجد بيانات — الحالة الفارغة ظاهرة (رسالة اختر عملية)
    // أو القائمة فارغة بلا أخطاء.
    expect(tester.takeException(), isNull);
  });

  testWidgets('تبويب الخزينة: الحالة الفارغة تظهر بالنص الصحيح', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('desk-tab-treasury')));
    await tester.pump(const Duration(milliseconds: 300));

    // نص الحالة الفارغة (القسم الأيسر عند عدم الاختيار).
    expect(find.text('اختر بنداً لعرض جدوله'), findsOneWidget);
  });

  // ── تبويب الديون ───────────────────────────────────────────────────────────

  testWidgets('تبويب الديون يعرض DesktopDebtsScreen دون أخطاء',
      (tester) async {
    await boot(tester);

    // التبويب موجود.
    expect(find.byKey(const Key('desk-tab-debts')), findsOneWidget);

    // فتح تبويب الديون.
    await tester.tap(find.byKey(const Key('desk-tab-debts')));
    await tester.pump(const Duration(milliseconds: 300));

    // الشاشة تعرض DesktopDebtsScreen.
    expect(find.byType(DesktopDebtsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('تبويب الديون: الحالة الفارغة تظهر بالنص الصحيح', (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('desk-tab-debts')));
    await tester.pump(const Duration(milliseconds: 300));

    // نص الحالة الفارغة (القسم الأيسر عند عدم الاختيار).
    expect(find.text('اختر ديناً لعرض التفاصيل'), findsOneWidget);
  });

  // ── اختبار ديناً واحداً مزروعاً ───────────────────────────────────────────

  testWidgets('الدين المزروع يظهر في قائمة الديون وعند اختياره تظهر التفاصيل',
      (tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // تهيئة المستودعات مع دين واحد مزروع.
    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc2@clinic.ly', 'secret12');
    await auth.login('doc2@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
    });

    // زرع دين واحد (نفس أسلوب اختبارات الديون الموجودة).
    const debtId = 'test-debt-001';
    c.read(reposProvider).debts.upsert({
      'id': debtId,
      'name': 'أحمد اختبار',
      'clinic': 'ع1',
      'service': 'حشو',
      'payment': 'دين',
      'totalAmount': 500.0,
      'paidAmount': 100.0,
      'remaining': 400.0,
      'status': 'active',
      'date': '2026-08-01',
      'installments': <Object?>[],
    });
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
    await tester.pump(const Duration(milliseconds: 200));

    // فتح تبويب الديون.
    await tester.tap(find.byKey(const Key('desk-tab-debts')));
    await tester.pump(const Duration(milliseconds: 300));

    // الدين يظهر في القائمة.
    expect(find.text('أحمد اختبار'), findsWidgets);

    // النقر على صف الدين يعرض التفاصيل يساراً.
    await tester.tap(find.byKey(Key('desk-debt-card-$debtId')));
    await tester.pump(const Duration(milliseconds: 300));

    // اسم المريض يظهر في التفاصيل.
    expect(find.byKey(const Key('desk-debt-detail-name')), findsOneWidget);
    expect(
      (tester.widget(find.byKey(const Key('desk-debt-detail-name')))
              as Text)
          .data,
      contains('أحمد اختبار'),
    );

    // لا استثناءات.
    expect(tester.takeException(), isNull);
  });
}
