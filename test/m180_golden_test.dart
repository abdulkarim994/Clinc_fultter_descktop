/// م180 — لقطات للمراجعة (GOLDENS=1 محلياً فقط): شاشة الدخول الجديدة
/// (شعار DENTSHINE + المبدّل المنزلق + نسيت كلمة المرور)، وخطوتا معالج
/// الإعداد الجديدتان (المعالجات ثم المختبرات). عدة الخطوط من م154.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show ByteData, EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _goldens = Platform.environment.containsKey('GOLDENS');

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Qomra',
      ['Qomra-Regular.ttf', 'Qomra-Medium.ttf', 'Qomra-Bold.ttf']);
  await load(
      'Cairo', ['Cairo-Regular.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final l = FontLoader('MaterialIcons');
      l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await l.load();
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(() async {
    await _loadAppFonts();
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m180g_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpApp(WidgetTester t, {bool signedIn = false}) async {
    t.view.physicalSize = const Size(440, 1050);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    if (signedIn) {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      final auth = seed.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      seed.dispose();
    }
    await t.pumpWidget(ProviderScope(
      overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
        builder: (ctx, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const DentalApp(),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    // فخ اللقطات الذهبية (القسم 11): صور الأصول لا تُفكّ ترميزها داخل
    // إطار الاختبار — بلا precacheImage عبر runAsync يخرج الشعار فارغاً.
    await t.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/icon/icon-512.png'),
        t.element(find.byType(MaterialApp).first),
      );
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));

  testWidgets('لقطة م180 — شاشة الدخول (DENTSHINE + المبدّل)', (t) async {
    await pumpApp(t);
    await shot(t, 'm180_login_dentshine');
  }, skip: !_goldens);

  testWidgets('لقطة م180 — تبويب إنشاء الحساب', (t) async {
    await pumpApp(t);
    await t.tap(find.byKey(const Key('auth-tab-register')));
    await t.pumpAndSettle();
    await shot(t, 'm180_login_register_tab');
  }, skip: !_goldens);

  testWidgets('لقطة م180 — معالج الإعداد: المعالجات وأسعارها', (t) async {
    await pumpApp(t, signedIn: true);
    await t.enterText(
        find.byKey(const Key('gate-center-name')), 'عيادة الصفوة');
    await t.enterText(find.byKey(const Key('gate-clinic-0')), 'د.عبدالكريم');
    await t.tap(find.byKey(const Key('gate-submit')));
    await t.pumpAndSettle();
    await shot(t, 'm180_wizard_services');
  }, skip: !_goldens);

  testWidgets('لقطة م180 — معالج الإعداد: المختبرات وأنواعها', (t) async {
    await pumpApp(t, signedIn: true);
    await t.enterText(
        find.byKey(const Key('gate-center-name')), 'عيادة الصفوة');
    await t.enterText(find.byKey(const Key('gate-clinic-0')), 'د.عبدالكريم');
    await t.tap(find.byKey(const Key('gate-submit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('gate-services-next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('gate-add-lab')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('gate-lab-name-0')), 'مخبر النور');
    await t.enterText(find.byKey(const Key('gate-labtype-0-0')), 'زيركون');
    await t.enterText(find.byKey(const Key('gate-labprice-0-0')), '300');
    await t.pumpAndSettle();
    await shot(t, 'm180_wizard_labs');
  }, skip: !_goldens);
}
