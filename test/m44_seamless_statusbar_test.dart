/// اختبار م44 — شريط النظام متصل بالهيدر بلا فاصل:
///   • النمط: شريط **شفاف** بأيقونات بيضاء (كان معتماً في v18 فظهر فاصل).
///   • هيدر الصدفة يبدأ من أول بكسل (y=0) وتشمل حشوته ارتفاع الشريط —
///     تدرج واحد متصل كالصورة المرجعية.
///   • ملف المريض: شريحة علوية بتدرج الهوية بارتفاع الشريط (تباين دائم).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m44_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('النمط: شفاف + أيقونات بيضاء (أندرويد وiOS)', () {
    expect(
      kDentalSystemUiStyle.statusBarColor,
      Colors.transparent,
      reason: 'الشفافية هي ما يصل الهيدر بلا فاصل',
    );
    expect(kDentalSystemUiStyle.statusBarIconBrightness, Brightness.light);
    expect(kDentalSystemUiStyle.statusBarBrightness, Brightness.dark);
  });

  testWidgets('الهيدر من أول بكسل وشريحة الملف بارتفاع الشريط', (tester) async {
    // إطار حالة وهمي بارتفاع 40 منطقية.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    tester.view.padding = const FakeViewPadding(
      top: 110,
      bottom: 0,
      left: 0,
      right: 0,
    );
    addTearDown(tester.view.reset);

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
      'payments': ['كاش'],
    });
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'ع1',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
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

    // هيدر الصدفة: حاويته المتدرجة تبدأ من قمة الشاشة تماماً (y=0)
    // فيرسم التدرج خلف الشريط الشفاف — لون واحد متصل.
    final headerFinder = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient == BrandColors.brandGradient,
    );
    expect(headerFinder, findsWidgets);
    final headerTop = tester.getTopLeft(headerFinder.first);
    expect(headerTop.dy, 0, reason: 'الهيدر يبدأ من أول بكسل');
    // حشوة الهيدر تستوعب الإطار (المحتوى تحت الشريط لا خلفه).
    final headerBox = tester.getRect(headerFinder.first);
    expect(
      headerBox.height,
      greaterThan(40),
      reason: 'ارتفاع الهيدر يشمل منطقة الشريط + محتواه',
    );

    // ملف المريض: شريحة التدرج العلوية بارتفاع الإطار (40).
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final cap = find.byKey(const Key('pp-statusbar-cap'));
    expect(cap, findsOneWidget);
    final capRect = tester.getRect(cap);
    expect(capRect.top, 0);
    expect(
      capRect.height,
      closeTo(40, .5),
      reason: 'الشريحة بارتفاع شريط النظام تماماً',
    );
    final capBox = tester.widget<Container>(cap);
    expect(
      (capBox.decoration as BoxDecoration).gradient,
      BrandColors.brandGradient,
      reason: 'شريحة الملف بتدرج الهوية نفسه',
    );
  });
}
