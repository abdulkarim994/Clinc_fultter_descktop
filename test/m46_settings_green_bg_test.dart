/// اختبار م46 (v24) — هيدر الإعدادات نسخة هيدر عبدالكريم حرفياً:
///   • الشريط العلوي (رجوع + «الإعدادات») وحده بتدرج brandGradient،
///     يبدأ من أول بكسل (خلف شريط النظام الشفاف) — بلا فاصل.
///   • حشواته حشوات هيدر الصدفة نفسها (إطار الحالة + 10) فارتفاعه محدود.
///   • جسم الشاشة فاتح كما كان (لا تدرج يغطي الشاشة) والمجموعات فوقه.
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m46_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('هيدر الإعدادات بتدرج الهوية من الصفر وجسم فاتح', (tester) async {
    // إطار حالة وهمي بارتفاع 40 منطقية — كهاتف حقيقي.
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
    seed.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
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

    await tester.tap(find.byTooltip('الإعدادات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // الهيدر: تدرج الهوية الحرفي من أول بكسل — متصل بشريط النظام.
    final header = find.byKey(const Key('settings-header'));
    expect(header, findsOneWidget);
    final headerBox = tester.widget<Container>(header);
    expect(
      (headerBox.decoration as BoxDecoration).gradient,
      BrandColors.brandGradient,
      reason: 'نفس تدرج هيدر عبدالكريم حرفياً',
    );
    final rect = tester.getRect(header);
    expect(rect.top, 0, reason: 'من أول بكسل — بلا فاصل مع الشريط');
    expect(
      rect.height,
      greaterThan(40),
      reason: 'يشمل منطقة إطار الحالة (40) + محتواه',
    );

    // شريط فقط لا خلفية: ارتفاعه محدود (أقل من ثلث الشاشة).
    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      rect.height,
      lessThan(screenH / 3),
      reason: 'الهيدر شريط علوي وحده — الخلفية ليست متدرجة',
    );

    // الجسم فاتح كما كان: لا حاوية تدرج تغطي شاشة الإعدادات كاملة.
    final gradients = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient ==
              BrandColors.brandGradient &&
          w.key != const Key('settings-header'),
    );
    for (final e in gradients.evaluate()) {
      final h = (e.renderObject as RenderBox?)?.size.height ?? 0;
      expect(h, lessThan(screenH * .9), reason: 'لا تدرج يغطي جسم الإعدادات');
    }

    // العنوان أبيض داخل الهيدر + زر الرجوع + المجموعات ظاهرة.
    final title = tester.widget<Text>(find.text('الإعدادات').last);
    expect(title.style?.color, Colors.white);
    expect(
      find.descendant(of: header, matching: find.byType(BackButton)),
      findsOneWidget,
    );
    expect(find.byKey(const Key('group-center')), findsOneWidget);
    expect(find.byKey(const Key('group-clinic')), findsOneWidget);
  });
}
