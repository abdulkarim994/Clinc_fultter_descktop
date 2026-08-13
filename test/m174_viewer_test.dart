/// م174 — عارض الأشعة المطوَّر ومحدد العيادة المنسدل:
///   • أسهم لوحة المفاتيح (كمبيوتر): يمين = السابق، يسار = التالي.
///   • سحب الإصبع (هاتف): قذفة أفقية حين لا تكبير تنقل بين الصور.
///   • ختم التاريخ تحت العنوان، وزر الحفظ للهاتف يظهر بالهاتف فقط.
///   • «مقارنة»: اختيار صورة ثانية ⇒ قالب قبل/بعد بختمَي تاريخ،
///     الأقدم «قبل» تلقائياً وزر التبديل يعكس، وأزرار التصدير الثلاثة.
///   • محدد العيادة بشاشة الحجز قائمةٌ تحت السهم لا ورقة سفلية.
library;

import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_compare_screen.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

/// PNG صالح 1×1 (نفس ثابت اختبارات م173).
final Uint8List kPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOoaOr5'
  'DwAFggKGrvU4EwAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m174_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpViewer(WidgetTester t,
      {bool desktop = false, int start = 0}) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize =
        desktop ? const Size(1400, 900) : const Size(420, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: MaterialApp(
          // RTL لكل المسارات المدفوعة (شاشة المقارنة تُدفع فوق العارض).
          builder: (ctx, child) => Directionality(
              textDirection: TextDirection.rtl, child: child!),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: XrayViewerScreen(
              keys_: const ['k1', 'k2', 'k3'],
              startIndex: start,
              bytesOf: (k) => kPng,
              nameOf: (k) => 'صورة-$k',
              dateOf: (k) => 'تاريخ-$k',
              tsOf: (k) => switch (k) { 'k1' => 100, 'k2' => 200, _ => 300 },
              patientName: 'سالم',
              centerName: 'عيادة الصفوة',
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 150));
  }

  group('م174 — العارض', () {
    testWidgets('أسهم لوحة المفاتيح: يسار = التالي ويمين = السابق',
        (t) async {
      await pumpViewer(t, desktop: true, start: 0);
      expect(find.textContaining('(1/3)'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(find.textContaining('(2/3)'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(find.textContaining('(1/3)'), findsOneWidget);
      // عند أول صورة: يمين لا يغادر الحد.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(find.textContaining('(1/3)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('سحب الإصبع (هاتف): قذفة لليسار = التالية', (t) async {
      await pumpViewer(t, start: 0);
      expect(find.textContaining('(1/3)'), findsOneWidget);
      await t.fling(
          find.byType(InteractiveViewer), const Offset(-250, 0), 1200);
      await t.pumpAndSettle();
      expect(find.textContaining('(2/3)'), findsOneWidget);
      // قذفة لليمين تعود للسابقة.
      await t.fling(
          find.byType(InteractiveViewer), const Offset(250, 0), 1200);
      await t.pumpAndSettle();
      expect(find.textContaining('(1/3)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('ختم التاريخ ظاهر وزر الحفظ للهاتف فقط', (t) async {
      await pumpViewer(t);
      expect(find.byKey(const Key('xv-date')), findsOneWidget);
      expect(find.text('تاريخ-k1'), findsOneWidget);
      expect(find.byKey(const Key('xv-save')), findsOneWidget);
      // الكمبيوتر: لا زر حفظ للهاتف.
      await pumpViewer(t, desktop: true);
      expect(find.byKey(const Key('xv-save')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('المقارنة: الأقدم «قبل» تلقائياً والتبديل يعكس',
        (t) async {
      // نبدأ من k2 (طابع 200) ونقارن مع k1 (طابع 100) ⇒ k1 قبل.
      await pumpViewer(t, start: 1);
      await t.tap(find.byKey(const Key('xv-compare')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('xv-cmp-pick-k1')));
      await t.pumpAndSettle();
      expect(find.byType(XrayCompareScreen), findsOneWidget);
      expect(find.text('قبل'), findsOneWidget);
      expect(find.text('بعد'), findsOneWidget);
      // RTL: لوحة «قبل» يمين «بعد»، وتاريخ الأقدم (k1) في لوحة قبل.
      final beforeX = t.getCenter(find.text('قبل')).dx;
      final afterX = t.getCenter(find.text('بعد')).dx;
      expect(beforeX, greaterThan(afterX));
      final d1X = t.getCenter(find.text('تاريخ-k1')).dx;
      final d2X = t.getCenter(find.text('تاريخ-k2')).dx;
      expect(d1X, greaterThan(d2X),
          reason: 'الأقدم k1 تحت لوحة قبل (يمين)');
      // التبديل يعكس مواضع التاريخين.
      await t.tap(find.byKey(const Key('xc-swap')));
      await t.pumpAndSettle();
      final d1X2 = t.getCenter(find.text('تاريخ-k1')).dx;
      final d2X2 = t.getCenter(find.text('تاريخ-k2')).dx;
      expect(d2X2, greaterThan(d1X2), reason: 'بعد التبديل k2 صار قبل');
      // أزرار التصدير الثلاثة (هاتف).
      expect(find.byKey(const Key('xc-save')), findsOneWidget);
      expect(find.byKey(const Key('xc-share')), findsOneWidget);
      expect(find.byKey(const Key('xc-pdf')), findsOneWidget);
      // الترويسة: المركز والمريض.
      expect(find.text('عيادة الصفوة'), findsWidgets);
      expect(find.text('سالم'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('م174 — محدد العيادة المنسدل بشاشة الحجز', () {
    testWidgets('القائمة تنبثق تحت السهم وتختار بلا ورقة سفلية',
        (t) async {
      debugForceDesktopUi = false;
      t.view.physicalSize = const Size(420, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final s = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = s.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      s.read(reposProvider).settings.set('app.config', {
        'centerName': 'م',
        'clinics': ['الصفوة', 'كاريزما'],
        'services': ['حشو'],
        'payments': ['كاش'],
      });
      s.dispose();
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: AppointmentsTab()),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 350));

      // فتح القائمة: العناصر تظهر (لا ترويسة ورقةٍ سفلية).
      await t.tap(find.byKey(const Key('appt-clinic-pill')));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'الورقة السفلية أزيلت (قرار المالك) — قائمة منسدلة');
      expect(find.byKey(const Key('appt-clinic-كاريزما')), findsOneWidget);
      // العنصر يظهر أسفل زر المحدد (تحت السهم).
      final pillY =
          t.getCenter(find.byKey(const Key('appt-clinic-pill'))).dy;
      final itemY =
          t.getCenter(find.byKey(const Key('appt-clinic-كاريزما'))).dy;
      expect(itemY, greaterThan(pillY));

      final c = ProviderScope.containerOf(
        t.element(find.byType(AppointmentsTab)),
        listen: false,
      );
      await t.tap(find.byKey(const Key('appt-clinic-كاريزما')));
      await t.pumpAndSettle();
      expect(c.read(apptClinicProvider), 'كاريزما');
      expect(t.takeException(), isNull);
    });
  });
}
