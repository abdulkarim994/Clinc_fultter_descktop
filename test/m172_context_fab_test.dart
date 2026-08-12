/// م172 — الأزرار العائمة السياقية (قرار المالك):
///   • بطاقة المريض: «+» في الزيارات فقط، «تسجيل دفعة» ذهبيةً في الديون
///     فقط إن وُجد دينٌ مفتوح (لا دين = لا زر)، «حجز موعد» دائري في
///     المواعيد (بدل زر المربع المزال)، زرا «تصوير/رفع» في الأشعة،
///     ولا زر في خطة العلاج.
///   • صدفة الهاتف: «+» في الرئيسية فقط، «إضافة حجز» في الحجوزات،
///     واختفاءٌ تام في بقية التبويبات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart'
    show apptBookDraftProvider;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m172_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// بطاقة مريضٍ هاتفية — [withDebt] يبذر ديناً مفتوحاً.
  Future<ProviderContainer> bootProfile(WidgetTester tester,
      {bool withDebt = false}) async {
    debugForceDesktopUi = false;
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'م',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش', 'تحويل'],
    });
    final repos = s.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم',
      'date': ymd(DateTime.now()),
      'amount': 100,
      'paid': 100,
      'payment': 'كاش',
      'clinic': 'ع1',
      '_t': 'r',
    });
    if (withDebt) {
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'سالم',
        'date': ymd(DateTime.now()),
        'amount': 200,
        'remaining': 150,
        'status': 'active',
        'clinic': 'ع1',
        '_t': 'd',
      });
    }
    s.dispose();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: PatientProfileScreen(patientName: 'سالم', clinic: 'ع1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return ProviderScope.containerOf(
      tester.element(find.byType(PatientProfileScreen)),
      listen: false,
    );
  }

  Future<void> goSection(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('psec-$id')));
    await tester.pumpAndSettle();
  }

  group('م172 — بطاقة المريض: الزر السياقي', () {
    testWidgets('الزيارات «+» فقط، وخطة العلاج بلا زر', (tester) async {
      await bootProfile(tester);
      // الافتراضي: الزيارات ⇒ زر الزيارة وحده.
      expect(find.byKey(const Key('pp-add-visit')), findsOneWidget);
      expect(find.byKey(const Key('pp-fab-pay')), findsNothing);
      expect(find.byKey(const Key('pp-fab-book')), findsNothing);
      // خطة العلاج ⇒ لا زر عائم إطلاقاً.
      await goSection(tester, 'plan');
      expect(find.byKey(const Key('pp-add-visit')), findsNothing);
      expect(find.byKey(const Key('pp-fab-pay')), findsNothing);
      expect(find.byKey(const Key('pp-fab-book')), findsNothing);
      expect(find.byKey(const Key('pp-fab-upload')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الديون: لا دين = لا زر، ودينٌ مفتوح = «تسجيل دفعة»',
        (tester) async {
      await bootProfile(tester);
      await goSection(tester, 'debts');
      expect(find.byKey(const Key('pp-fab-pay')), findsNothing,
          reason: 'لا دين مفتوحاً ⇒ لا يظهر شيء (قرار المالك)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('دينٌ مفتوح: الزر يظهر ونقره يفتح نافذة الدفعة مباشرة',
        (tester) async {
      await bootProfile(tester, withDebt: true);
      await goSection(tester, 'debts');
      expect(find.byKey(const Key('pp-fab-pay')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pp-fab-pay')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      // نافذة الدفعة الموحدة (v33) فُتحت مباشرة (دينٌ واحد).
      expect(find.textContaining('دفعة'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('المواعيد: «حجز موعد» دائري بدل المربع المزال',
        (tester) async {
      final c = await bootProfile(tester);
      await goSection(tester, 'appts');
      expect(find.byKey(const Key('pp-fab-book')), findsOneWidget);
      expect(find.byKey(const Key('pp-appt-book')), findsNothing,
          reason: 'زر المربع أزيل (قرار المالك)');
      await tester.tap(find.byKey(const Key('pp-fab-book')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.read(apptBookDraftProvider), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الأشعة: زرا «تصوير» و«رفع» متراصان (هاتف)',
        (tester) async {
      await bootProfile(tester);
      await goSection(tester, 'xrays');
      expect(find.byKey(const Key('pp-fab-camera')), findsOneWidget);
      expect(find.byKey(const Key('pp-fab-upload')), findsOneWidget);
      // التصوير فوق الرفع (dy أصغر).
      final camY =
          tester.getCenter(find.byKey(const Key('pp-fab-camera'))).dy;
      final upY =
          tester.getCenter(find.byKey(const Key('pp-fab-upload'))).dy;
      expect(camY, lessThan(upY));
      expect(tester.takeException(), isNull);
    });
  });

  group('م172 — صدفة الهاتف: الزر لكل تبويب', () {
    Future<void> bootShell(WidgetTester tester) async {
      debugForceDesktopUi = false;
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = s.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      s.read(reposProvider).settings.set('app.config', {
        'centerName': 'م',
        'clinics': ['ع1'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
      });
      s.dispose();
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
      await tester.pump(const Duration(milliseconds: 300));
      final ok = find.byKey(const Key('appt-notif-ok'));
      if (ok.evaluate().isNotEmpty) {
        await tester.tap(ok);
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('«+» في الرئيسية فقط ويختفي في السجلات والمالية',
        (tester) async {
      await bootShell(tester);
      expect(find.byKey(const Key('fab-add')), findsOneWidget);
      // السجلات ⇒ لا زر عائم.
      await tester.tap(find.text('السجلات'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-add')), findsNothing);
      expect(find.byKey(const Key('fab-book-appt')), findsNothing);
      // المالية ⇒ لا زر.
      await tester.tap(find.text('المالية'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-add')), findsNothing);
      expect(find.byKey(const Key('fab-book-appt')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الحجوزات: زر «إضافة حجز» يفتح معالج الموعد', (tester) async {
      await bootShell(tester);
      await tester.tap(find.text('الحجوزات'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-add')), findsNothing);
      expect(find.byKey(const Key('fab-book-appt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fab-book-appt')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      // معالج الموعد فُتح (حقل اسم المريض في الورقة).
      expect(find.text('حفظ الموعد'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
