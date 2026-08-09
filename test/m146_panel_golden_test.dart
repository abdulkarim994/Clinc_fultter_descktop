/// م146 — لقطاتٌ ذهبية للوح «زيارة جديدة» الجانبي (عقد التصميم «د»).
///
/// الغرض مزدوج:
///  1) توليد صورٍ حقيقية للتصميم (بخطوط التطبيق) يراجعها المشرف والمالك
///     قبل الدمج — تُولَّد محلياً بـ:
///     GOLDENS=1 flutter test test/m146_panel_golden_test.dart --update-goldens
///  2) حارس اللاتمرير: على 1366×768 بأسوأ حالة (تركيبات + دين معاً) يجب
///     ألا يفيض أي RenderFlex (الفيض يُسقط الاختبار تلقائياً) وأن يبقى
///     زر الحفظ داخل حدود الشاشة بلا تمرير.
///
/// اللقطات تقفز في CI (لا متغير GOLDENS) — مقارنة البكسل عبر أجهزةٍ
/// مختلفة هشّة، والحارس الوظيفي (اللاتمرير) يُشغَّل دائماً.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show EventChannel, FontLoader, LogicalKeyboardKey, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

final _goldens = Platform.environment.containsKey('GOLDENS');

/// تحميل خطوط التطبيق الحقيقية كي لا تُرسم اللقطات بمربعات Ahem.
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Qomra', [
    'Qomra-Regular.ttf',
    'Qomra-Medium.ttf',
    'Qomra-Bold.ttf',
  ]);
  await load('Cairo', [
    'Cairo-Regular.ttf',
    'Cairo-SemiBold.ttf',
    'Cairo-Bold.ttf',
  ]);
  // خط الأيقونات من كاش فلاتر — بدونه تُرسم الأيقونات مربعاتٍ فارغة في
  // اللقطات. المسار يُحلّ من FLUTTER_ROOT (تضبطه أداة flutter test)، وإن
  // غاب الملف نتجاوز بهدوء: الأيقونات تلزم اللقطات المحلية فقط، وحارس
  // اللاتمرير على CI لا يحتاجها.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final iconsFile = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconsFile.existsSync()) {
      final iconsLoader = FontLoader('MaterialIcons');
      final iconBytes = iconsFile.readAsBytesSync();
      iconsLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
      await iconsLoader.load();
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(() async {
    await _loadAppFonts();
    // كتم قناتَي connectivity_plus — لا تنفيذ لهما في بيئة الاختبار،
    // واستثناءاتهما غير المتزامنة تُفشل اختبارات اللقطات دون داعٍ.
    binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (args, events) => events.success(const ['wifi']),
      ),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => const ['wifi'],
    );
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('m146_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1600, 1000),
  }) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = size;
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
      'centerName': 'عيادة الصفوة',
      'clinics': ['الصفوة', 'النخبة'],
      'services': ['حشو', 'قلع', 'تركيبات', 'تنظيف'],
      'payments': ['كاش', 'تحويل'],
      'servicePrices': {'حشو': 150, 'تركيبات': 900},
      // التحاليل الثلاثية مفعّلة كي تظهر في اللقطات.
      'analyses3': {'price': 50, 'enabled': true},
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
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pickDebt(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('rec-debt-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
  }

  Future<void> pickService(WidgetTester tester, String s) async {
    await tester.tap(find.byKey(const Key('rec-service')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(s).last);
    await tester.pump(const Duration(milliseconds: 260));
  }

  testWidgets('لقطة: الحالة الافتراضية 1600×1000', (tester) async {
    await boot(tester);
    await openPanel(tester);
    await expectLater(
      find.byType(DentalApp),
      matchesGoldenFile('goldens/m146_panel_default.png'),
    );
  }, skip: !_goldens);

  testWidgets('لقطة: تركيبات مفتوحة 1600×1000', (tester) async {
    await boot(tester);
    await openPanel(tester);
    await pickService(tester, 'تركيبات');
    await expectLater(
      find.byType(DentalApp),
      matchesGoldenFile('goldens/m146_panel_pros.png'),
    );
  }, skip: !_goldens);

  testWidgets('لقطة: دين + تحاليل معاً 1600×1000', (tester) async {
    await boot(tester);
    await openPanel(tester);
    await pickDebt(tester);
    await tester.tap(find.byKey(const Key('rec-analysis-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await expectLater(
      find.byType(DentalApp),
      matchesGoldenFile('goldens/m146_panel_debt_analysis.png'),
    );
  }, skip: !_goldens);

  testWidgets('لقطة + حارس اللاتمرير: أسوأ حالة على 1366×768', (tester) async {
    await boot(tester, size: const Size(1366, 768));
    await openPanel(tester);
    await pickService(tester, 'تركيبات');
    await pickDebt(tester);
    // أي RenderFlex overflow يُسقط الاختبار هنا تلقائياً.
    // زر الحفظ يجب أن يبقى داخل حدود الشاشة بلا تمرير.
    final saveRect = tester.getRect(find.byKey(const Key('rec-save')));
    expect(saveRect.bottom, lessThanOrEqualTo(768),
        reason: 'زر الحفظ خرج عن الشاشة — ميزانية اللاتمرير انكسرت');
    if (_goldens) {
      await expectLater(
        find.byType(DentalApp),
        matchesGoldenFile('goldens/m146_panel_worstcase_768.png'),
      );
    }
  });
}
