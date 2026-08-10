/// م161 — لقطاتٌ للمراجعة (GOLDENS=1): قسم المختبر الجديد بهوية الخزينة —
/// قائمة البطاقات الصفّية بقيمة الشهر، وشاشة المختبر بجدولها وصف الإجمالي.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/labs/labs_tab.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

final _goldens = Platform.environment.containsKey('GOLDENS');

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(
          ByteData.view(File('assets/fonts/$f').readAsBytesSync().buffer)));
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m161_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'عيادة الصفوة',
        'doctorPct': 50,
        'clinics': ['الصفوة', 'كاريزما'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'labs': ['مخبر النور', 'مخبر الفجر'],
        'clinicRates': {
          'clinics': {
            'الصفوة': {'treatments': {}, 'prosthetics': 40},
            'كاريزما': {'treatments': {}, 'prosthetics': 40},
          },
        },
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  void seed(ProviderContainer c) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate();
    void pros(String name, String clinic, String lab, String type, num units,
        num lab$, num total) {
      repos.prosthetics.upsert({
        'id': '$name-$lab-$type',
        'date': today,
        'name': name,
        'clinic': clinic,
        'clinic_id': clinic,
        'service': 'تركيبات',
        'total': total,
        'labValue': lab$,
        'labName': lab,
        'prosType': type,
        'prosUnits': units,
        'payment': 'كاش',
        'isDebt': 0,
        '_t': 'p',
      });
    }

    pros('محمد علي', 'الصفوة', 'مخبر النور', 'زيركون', 3, 300, 1500);
    pros('خالد يوسف', 'كاريزما', 'مخبر النور', 'ببك', 2, 500, 2000);
    pros('سارة محمود', 'الصفوة', 'مخبر النور', 'Zirconia', 4, 700, 3000);
    pros('ليلى حسن', 'الصفوة', 'مخبر الفجر', 'زيركون', 1, 250, 900);
  }

  Future<ProviderContainer> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: ov());
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', config());
    seed(c);
    c.dispose();
    return ProviderContainer(overrides: ov());
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  testWidgets('المختبر على الكمبيوتر — القائمة والجدول', (t) async {
    debugForceDesktopUi = true;
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', config());
    seed(c0);
    c0.dispose();
    await t.pumpWidget(ProviderScope(
        overrides: ov(), child: const DentalApp()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const Key('desk-tab-extra')));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('extra-labs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('labs-desk-tile-مخبر النور')));
    await t.pumpAndSettle();
    await shot(t, 'm161_desktop_labs');
  }, skip: !_goldens);

  testWidgets('قسم المختبر — القائمة ثم شاشة مختبر', (t) async {
    final c = await boot(t);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: LabsTab()),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await shot(t, 'm161_labs_landing');
    await t.tap(find.byKey(const Key('lab-مخبر النور')));
    await t.pumpAndSettle();
    await shot(t, 'm161_lab_detail');
  }, skip: !_goldens);
}
