/// اختبارات م40 — معايرة الخط على قاعدة Vue:
///   • مقياس النص الفعلي = خيار المستخدم × معامل المعايرة 1.12
///     (جسم Vue الأساس 18px — «عادي» يعادل حجم الأصل الفعلي).
///   • خيارات «حجم الخط» بقيم Vue الحرفية 0.85/1/1.2/1.45.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/font_calibration.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show AppShellScreen;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m40_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('معامل المعايرة 1.12 (قاعدة Vue)', () {
    expect(kVueFontCalibration, 1.12);
  });

  testWidgets('المقياس الفعلي = الخيار × المعايرة ويتغير مع الخيار',
      (tester) async {
    final seed = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
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

    await tester.pumpWidget(ProviderScope(
      overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      child: const DentalApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final ctx = tester.element(find.byType(AppShellScreen));
    // «عادي» (1.0): المقياس الفعلي = 1.12.
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(11.2, .01));

    // «كبير» (قيمة Vue 1.2): المقياس الفعلي = 1.344.
    final container = ProviderScope.containerOf(ctx);
    container.read(fontScaleProvider.notifier).state = 1.2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final ctx2 = tester.element(find.byType(AppShellScreen));
    expect(MediaQuery.textScalerOf(ctx2).scale(10),
        closeTo(13.44, .01));
  });
}
