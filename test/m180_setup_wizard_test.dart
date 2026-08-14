/// اختبارات م180/ج — معالج الإعداد ثلاثي الخطوات (قرار المالك):
/// المركز والعيادات ⇒ «حفظ ومتابعة» ⇒ المعالجات وأسعارها ⇒ «حفظ ومتابعة»
/// ⇒ المختبرات وأنواعها ⇒ «حفظ وإنهاء» ⇒ شاشة البدء بالسلوك القديم.
///
/// العقد المحروس هنا: **علم الإكمال يُختم في الخطوة الأخيرة وحدها** —
/// فمن انقطع في المنتصف يعود للمعالج لا للتطبيق.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m180c_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> bootFresh(WidgetTester tester) async {
    final seed = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    seed.dispose();
    await tester.pumpWidget(ProviderScope(
      overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      child: const DentalApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Map<String, Object?> readCfg() {
    final chk = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(chk.dispose);
    final v = chk.read(reposProvider).settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  /// علم الإكمال الخام للـ uid الفعلي للجلسة (لا للبريد): الحكم على
  /// «هل خُتم الإعداد؟» دون تمريره عبر isSetupComplete الذي يرحّل ويختم.
  bool setupFlag(WidgetTester tester) {
    final c = ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
    final auth = c.read(authProvider);
    final uid = auth is SignedIn ? auth.user.uid : '';
    return isSetupFlagSet(c.read(localDbProvider), uid);
  }

  testWidgets('الخطوات الثلاث بمحتوى حقيقي تكتب المفاتيح كلها ثم تُنهي',
      (tester) async {
    await bootFresh(tester);
    // ── الخطوة ١: المركز والعيادات ──
    expect(find.byKey(const Key('gate-step-dot-0')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('gate-center-name')), 'مركز الصفوة');
    await tester.enterText(
        find.byKey(const Key('gate-clinic-0')), 'عيادة أ');
    await tester.tap(find.byKey(const Key('gate-add-clinic')));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('gate-clinic-1')), 'عيادة ب');
    await tester.tap(find.byKey(const Key('gate-submit')));
    await settle(tester);

    // ── الخطوة ٢: المعالجات وأسعارها ──
    expect(find.byKey(const Key('gate-svc-name-0')), findsOneWidget);
    expect(setupFlag(tester), isFalse,
        reason: 'لا ختم قبل الخطوة الأخيرة');
    await tester.enterText(
        find.byKey(const Key('gate-svc-name-0')), 'حشو');
    await tester.enterText(find.byKey(const Key('gate-svc-price-0')), '150');
    await tester.enterText(
        find.byKey(const Key('gate-svc-name-1')), 'تنظيف');
    await tester.enterText(find.byKey(const Key('gate-svc-price-1')), '80');
    // حذف الصف الثالث المبذور.
    await tester.tap(find.byKey(const Key('gate-svc-name-2')));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('gate-svc-name-2')), 'تركيبات');
    await tester.tap(find.byKey(const Key('gate-services-next')));
    await settle(tester);

    // ── الخطوة ٣: المختبرات وأنواعها ──
    expect(find.byKey(const Key('gate-add-lab')), findsOneWidget);
    expect(setupFlag(tester), isFalse);
    await tester.tap(find.byKey(const Key('gate-add-lab')));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('gate-lab-name-0')), 'مخبر النور');
    await tester.enterText(
        find.byKey(const Key('gate-labtype-0-0')), 'زيركون');
    await tester.enterText(
        find.byKey(const Key('gate-labprice-0-0')), '300');
    await tester.tap(find.byKey(const Key('gate-add-labtype-0')));
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('gate-labtype-0-1')), 'بورسلان');
    await tester.enterText(
        find.byKey(const Key('gate-labprice-0-1')), '200');
    await tester.tap(find.byKey(const Key('gate-labs-finish')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // ── النتيجة: الصدفة + كل المفاتيح مكتوبة + الختم ──
    expect(find.byType(AppShellScreen), findsOneWidget);
    final cfg = readCfg();
    expect(cfg['centerName'], 'مركز الصفوة');
    expect(cfg['clinics'], ['عيادة أ', 'عيادة ب']);
    expect(cfg['services'], ['حشو', 'تنظيف', 'تركيبات']);
    expect((cfg['servicePrices'] as Map)['حشو'], 150);
    expect((cfg['servicePrices'] as Map)['تنظيف'], 80);
    expect(cfg['labs'], ['مخبر النور']);
    final types = (cfg['labTypesByLab'] as Map)['مخبر النور'] as List;
    expect(types.length, 2);
    expect((types[0] as Map)['name'], 'زيركون');
    expect((types[0] as Map)['defaultPrice'], 300);
    expect((types[1] as Map)['name'], 'بورسلان');
    expect(setupFlag(tester), isTrue);
  });

  testWidgets('المختبرات اختيارية: «حفظ وإنهاء» بقائمة فارغة يُنهي الإعداد',
      (tester) async {
    await bootFresh(tester);
    await tester.enterText(
        find.byKey(const Key('gate-center-name')), 'مركز');
    await tester.enterText(find.byKey(const Key('gate-clinic-0')), 'ع1');
    await tester.tap(find.byKey(const Key('gate-submit')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('gate-services-next')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('gate-labs-finish')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(AppShellScreen), findsOneWidget);
    final cfg = readCfg();
    expect(cfg.containsKey('labs'), isFalse, reason: 'لا مفتاح فارغ');
    // المعالجات الافتراضية المبذورة كُتبت كما هي.
    expect((cfg['services'] as List).length, 3);
    expect(setupFlag(tester), isTrue);
  });

  testWidgets('الخطوة ٢ إلزامية: تفريغ كل المعالجات يمنع المتابعة',
      (tester) async {
    await bootFresh(tester);
    await tester.enterText(
        find.byKey(const Key('gate-center-name')), 'مركز');
    await tester.enterText(find.byKey(const Key('gate-clinic-0')), 'ع1');
    await tester.tap(find.byKey(const Key('gate-submit')));
    await settle(tester);
    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('gate-svc-name-$i')), '');
    }
    await tester.tap(find.byKey(const Key('gate-services-next')));
    await settle(tester);
    expect(find.byKey(const Key('gate-error')), findsOneWidget);
    expect(find.byKey(const Key('gate-add-lab')), findsNothing,
        reason: 'لا انتقال للخطوة الثالثة');
  });
}
