/// اختبارات م181/أ — «تركيبات» معالجة نظامية مقفلة بلا سعر (قرار المالك):
/// • معالج الإعداد: صفها مثبت (لا اسم يحرَّر ولا حقل سعر ولا حذف)،
///   تُكتب دائماً عند الحفظ، وإدخالها يدوياً كصف حر مرفوض.
/// • الإعدادات: لا حقل سعر لها (شارة «سعر متغيّر» مكانه) ولا زر حذف.
/// • هجرة التطهير: سعر مخزّن لها من عهدٍ سابق يُزال بشاهد قبرٍ عند
///   الإقلاع فلا يعيده الدمج من جهاز قديم.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/locked_services.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show AppShellScreen, purgedLockedServicePrices,
        resetLockedPricesPurgeGuard;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m181a_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('م181/أ — الحساب النقي للتطهير', () {
    test('سعر مخزّن للتركيبات يُزال وأسعار الباقي لا تُمس', () {
      final next = purgedLockedServicePrices({
        'servicePrices': {'تركيبات': 500, 'حشو': 100},
      });
      expect(next, isNotNull);
      final prices = next!['servicePrices'] as Map;
      expect(prices.containsKey('تركيبات'), isFalse);
      expect(prices['حشو'], 100, reason: 'أسعار الباقي لا تُمس');
    });

    test('إعدادات نظيفة ⇒ null (لا كتابة عبثية)', () {
      expect(purgedLockedServicePrices(const {}), isNull);
      expect(
          purgedLockedServicePrices({
            'servicePrices': {'حشو': 100},
          }),
          isNull);
    });
  });

  group('م181/أ — معالج الإعداد', () {
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
      // للخطوة ٢.
      await tester.enterText(
          find.byKey(const Key('gate-center-name')), 'مركز');
      await tester.enterText(find.byKey(const Key('gate-clinic-0')), 'ع1');
      await tester.tap(find.byKey(const Key('gate-submit')));
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

    testWidgets('الصف المثبت: بلا محرِّر اسم ولا سعر، ويُكتب دائماً',
        (tester) async {
      await bootFresh(tester);
      expect(find.byKey(const Key('gate-svc-locked-تركيبات')),
          findsOneWidget);
      expect(find.text(kVariablePriceLabel), findsOneWidget);
      // صفان حرّان فقط (0 و1) — لا ثالث.
      expect(find.byKey(const Key('gate-svc-name-2')), findsNothing);
      await tester.tap(find.byKey(const Key('gate-services-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final cfg = readCfg();
      final services = (cfg['services'] as List).cast<String>();
      expect(services.where((s) => s == 'تركيبات').length, 1,
          reason: 'تُكتب مرة واحدة دائماً');
      final prices = cfg['servicePrices'];
      expect(prices is Map && prices.containsKey('تركيبات'), isFalse,
          reason: 'لا سعر للتركيبات أبداً');
    });

    testWidgets('إدخال «تركيبات» يدوياً كصف حر مرفوض برسالة', (tester) async {
      await bootFresh(tester);
      await tester.enterText(
          find.byKey(const Key('gate-svc-name-0')), 'تركيبات');
      await tester.tap(find.byKey(const Key('gate-services-next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const Key('gate-error')), findsOneWidget);
      expect(find.byKey(const Key('gate-add-lab')), findsNothing,
          reason: 'لا انتقال للخطوة الثالثة');
    });
  });

  group('م181/أ — الإعدادات والإقلاع', () {
    Map<String, Object?> config() => {
          'centerName': 'مركز الاختبار',
          'clinics': ['ع1'],
          'services': ['حشو', 'تركيبات'],
          'payments': ['كاش'],
        };

    Future<void> boot(WidgetTester tester,
        {Map<String, Object?>? cfg}) async {
      final c = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', cfg ?? config());
      c.dispose();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Map<String, Object?> readCfg(WidgetTester tester) {
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      final v = c.read(reposProvider).settings.get('app.config');
      return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
    }

    testWidgets('بطاقة المعالجات: شارة «سعر متغيّر» بلا حقل سعر ولا حذف',
        (tester) async {
      await boot(tester);
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('group-clinic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
          find.byKey(const Key('svc-variable-تركيبات')), 120,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .last);
      await tester.pump();
      expect(find.byKey(const Key('svc-variable-تركيبات')), findsOneWidget);
      expect(find.byKey(const Key('svc-price-تركيبات')), findsNothing,
          reason: 'لا حقل سعر للتركيبات في الإعدادات');
      expect(find.byKey(const Key('svc-price-حشو')), findsOneWidget,
          reason: 'باقي المعالجات بحقولها كما هي');
    });

    testWidgets('هجرة الإقلاع تطهّر سعراً مخزّناً للتركيبات', (tester) async {
      resetLockedPricesPurgeGuard();
      await boot(tester, cfg: {
        ...config(),
        'servicePrices': {'تركيبات': 500, 'حشو': 100},
      });
      // بعد إطارات الإقلاع (الهجرة post-frame).
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppShellScreen), findsOneWidget);
      final cfg = readCfg(tester);
      final prices = cfg['servicePrices'] as Map;
      expect(prices.containsKey('تركيبات'), isFalse,
          reason: 'السعر المخزّن طُهّر عند الإقلاع (بلقطة أساس تولّد '
              'شاهد حذفٍ ورقيّاً فلا يعود بالدمج)');
      expect(prices['حشو'], 100);
    });
  });
}
