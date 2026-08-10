/// م155 — لقطاتٌ للمراجعة (GOLDENS=1 محلياً فقط): سجلاتٌ بهوية الخزينة —
/// بوابة الهاتف ببطاقاتها الصفّية الصغيرة + مدخل التحاليل الثابت، ونسخة
/// الكمبيوتر ببطاقات العيادات الصفّية وجدول التحاليل في اللوح التفصيلي.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show PatientsTab;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m155_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'عيادة الصفوة',
        'doctorPct': 50,
        'clinics': ['د.عبدالفتاح الدليمي', 'د.ملاذ رجب'],
        'services': ['حشو', 'قلع', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'clinicRates': {
          'clinics': {
            'د.عبدالفتاح الدليمي': {'treatments': {}, 'prosthetics': 40},
            'د.ملاذ رجب': {'treatments': {}, 'prosthetics': 40},
          },
        },
        'analyses3': {'enabled': true, 'price': 50, 'repeatMonths': 6},
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  void seed(ProviderContainer c) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate();
    String visit(String name, String cli, num amt, String pay,
        {String service = 'حشو', AnalysisInput? anal}) {
      return saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
            name: name,
            date: today,
            amount: amt,
            clinic: cli,
            service: service,
            payment: pay,
            labValue: service == 'تركيبات' ? 150 : 0,
            analysis: anal),
      ).entryId;
    }

    visit('محمد علي', 'د.عبدالفتاح الدليمي', 500, 'تحويل',
        anal: AnalysisInput(
            name: 'التحاليل الثلاثية', price: 50, payment: 'كاش'));
    visit('أحمد سالم', 'د.عبدالفتاح الدليمي', 200, 'كاش');
    visit('خالد يوسف', 'د.عبدالفتاح الدليمي', 800, 'تحويل',
        service: 'تركيبات');
    visit('وليد صالح', 'د.عبدالفتاح الدليمي', 600, 'كاش',
        service: 'تركيبات');
    visit('سارة محمود', 'د.ملاذ رجب', 350, 'كاش',
        anal: AnalysisInput(
            name: 'التحاليل الثلاثية', price: 50, payment: 'تحويل'));
    visit('ليلى حسن', 'د.ملاذ رجب', 150, 'تحويل');
  }

  Future<ProviderContainer> boot(WidgetTester t,
      {required Size size, required bool desktop}) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize = size;
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

  group('لقطات م155', () {
    testWidgets('بوابة السجلات في الهاتف — بطاقات صفّية بهوية الخزينة',
        (t) async {
      await boot(t, size: const Size(420, 900), desktop: false);
      await t.pumpWidget(ProviderScope(
        overrides: ov(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: PatientsTab()),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm155_mobile_records_landing');
      // الدخول لعيادة — القوائم كما هي سابقاً.
      await t.tap(find.byKey(const Key('clinic-card-د.عبدالفتاح الدليمي')));
      await t.pumpAndSettle();
      await shot(t, 'm155_mobile_clinic_patients');
    }, skip: !_goldens);

    testWidgets('سجلات الكمبيوتر — البطاقات الصفّية وجدول التحاليل واللوح',
        (t) async {
      await boot(t, size: const Size(1600, 1000), desktop: true);
      await t.pumpWidget(ProviderScope(
          overrides: ov(), child: const DentalApp()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('desk-tab-clinics')));
      await t.pump(const Duration(milliseconds: 400));
      // توسيع شريط العيادات — البطاقات الصفّية الجديدة.
      await t.tap(find.byKey(const Key('dr-clinic-strip-toggle')));
      await t.pumpAndSettle();
      await shot(t, 'm155_desktop_records_clinics');
      // جدول التحاليل الثلاثية في اللوح التفصيلي.
      await t.tap(find.byKey(const Key('dr-anal-registry-entry')));
      await t.pumpAndSettle();
      await shot(t, 'm155_desktop_analyses_table');
      // اختيار مريض — الملف يفتح يساراً كالعادة.
      await t.tap(find.text('أحمد سالم').first);
      await t.pumpAndSettle();
      await shot(t, 'm155_desktop_patient_profile');
      // عيادة واحدة مختارة (فلترة) + مريض واحد مفتوح — معاً.
      await t.tap(find.byKey(const Key('dr-clinic-card-د.عبدالفتاح الدليمي')));
      await t.pumpAndSettle();
      await t.tap(find.text('محمد علي').first);
      await t.pumpAndSettle();
      await shot(t, 'm155_desktop_clinic_and_patient');
    }, skip: !_goldens);
  });
}
