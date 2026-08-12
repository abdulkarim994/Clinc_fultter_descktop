/// م168 — لقطاتٌ للمراجعة (GOLDENS=1 محلياً فقط): «الاختفاء الشامل»
/// للتحاليل الثلاثية عند الإيقاف — تباين ظاهر/مخفي على الشاشات المعنية:
/// إدخال اليوم المكتبي (العمود والفلتر)، خزينة الهاتف (البند والجدول —
/// شهرٌ تاريخي يبقى وشهرٌ بعد الإيقاف يختفي)، بوابة السجلات (مدخل
/// السجل)، ونموذج «زيارة جديدة» (خيار التحليل). عدة الخطوط من م154.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/finance/treasury_section.dart';
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m168_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  // إعداد قاعدي — كتلة analyses3 تُمرَّر بحسب سيناريو اللقطة.
  Map<String, Object?> config({Map<String, Object?>? tri}) => {
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
        'analyses3': ?tri,
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  // بذر الزيارات — تحاليل اليوم تُكتب بإعدادٍ مفعّل (شرط مسار الحفظ)،
  // ثم يكتب كل سيناريو إعداده النهائي فوقه قبل اللقطة.
  void seed(ProviderContainer c, {required bool withAnal}) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate();
    final seedCfg = config(
        tri: {'enabled': true, 'price': 50, 'repeatMonths': 6});
    void visit(String name, String cli, num amt, String pay,
        {AnalysisInput? anal}) {
      saveNewRecord(
        repos,
        seedCfg,
        SaveRecordInput(
            name: name,
            date: today,
            amount: amt,
            clinic: cli,
            service: 'حشو',
            payment: pay,
            analysis: anal),
      );
    }

    visit('محمد علي', 'د.عبدالفتاح الدليمي', 500, 'تحويل',
        anal: withAnal
            ? AnalysisInput(
                name: 'التحاليل الثلاثية', price: 50, payment: 'كاش')
            : null);
    visit('أحمد سالم', 'د.عبدالفتاح الدليمي', 200, 'كاش');
    visit('سارة محمود', 'د.ملاذ رجب', 350, 'كاش',
        anal: withAnal
            ? AnalysisInput(
                name: 'التحاليل الثلاثية', price: 50, payment: 'تحويل')
            : null);
  }

  Future<void> boot(
    WidgetTester t, {
    required Size size,
    required bool desktop,
    required Map<String, Object?> finalConfig,
    required bool withAnal,
  }) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: ov());
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    seed(c, withAnal: withAnal);
    // الإعداد النهائي للسيناريو يُكتب بعد البذر (قد يكون متوقفاً).
    c.read(reposProvider).settings.set('app.config', finalConfig);
    c.dispose();
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  Future<void> pumpApp(WidgetTester t) async {
    await t.pumpWidget(
        ProviderScope(overrides: ov(), child: const DentalApp()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Widget phoneHost(Widget child) => ProviderScope(
        overrides: ov(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: child),
          ),
        ),
      );

  group('لقطات م168 — الاختفاء الشامل عند الإيقاف', () {
    testWidgets('إدخال اليوم مكتبي — الميزة مفعّلة (العمود والفلتر ظاهران)',
        (t) async {
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          withAnal: true,
          finalConfig: config(
              tri: {'enabled': true, 'price': 50, 'repeatMonths': 6}));
      await pumpApp(t);
      await t.pumpAndSettle();
      await shot(t, 'm168_desktop_home_on');
    }, skip: !_goldens);

    testWidgets('إدخال اليوم مكتبي — الميزة متوقفة (لا عمود ولا فلتر)',
        (t) async {
      // القيمة 0/الإيقاف بلا تاريخ = اختفاء كلي (الافتراضي الآمن).
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          withAnal: false,
          finalConfig: config(
              tri: {'enabled': false, 'price': 50, 'repeatMonths': 6}));
      await pumpApp(t);
      await t.pumpAndSettle();
      await shot(t, 'm168_desktop_home_off');
    }, skip: !_goldens);

    testWidgets('خزينة الهاتف — شهرٌ تاريخي بعد الإيقاف (البند باقٍ بقيمه)',
        (t) async {
      // أُوقفت اليوم — تحاليل اليوم (≤ تاريخ الإيقاف) تبقى ظاهرة.
      await boot(t,
          size: const Size(420, 900),
          desktop: false,
          withAnal: true,
          finalConfig: config(tri: {
            'enabled': false,
            'price': 50,
            'repeatMonths': 6,
            'disabledOn': getCurrentDate(),
          }));
      await t.pumpWidget(phoneHost(const TreasurySection()));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm168_phone_treasury_history');
    }, skip: !_goldens);

    testWidgets('خزينة الهاتف — شهرٌ بعد تاريخ الإيقاف (البند مختفٍ كلياً)',
        (t) async {
      // أُوقفت قبل الشهر الحالي — لا بند ولا صف في جدول الإجمالي.
      await boot(t,
          size: const Size(420, 900),
          desktop: false,
          withAnal: false,
          finalConfig: config(tri: {
            'enabled': false,
            'price': 50,
            'repeatMonths': 6,
            'disabledOn': '2020-01-01',
          }));
      await t.pumpWidget(phoneHost(const TreasurySection()));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm168_phone_treasury_off');
    }, skip: !_goldens);

    testWidgets('بوابة السجلات هاتف — الميزة متوقفة (لا مدخل سجل التحاليل)',
        (t) async {
      await boot(t,
          size: const Size(420, 900),
          desktop: false,
          withAnal: false,
          finalConfig: config(
              tri: {'enabled': false, 'price': 50, 'repeatMonths': 6}));
      await t.pumpWidget(phoneHost(const PatientsTab()));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm168_phone_records_off');
    }, skip: !_goldens);

    testWidgets('زيارة جديدة هاتف — الميزة متوقفة (لا خيار تحاليل)',
        (t) async {
      await boot(t,
          size: const Size(420, 1200),
          desktop: false,
          withAnal: false,
          finalConfig: config(
              tri: {'enabled': false, 'price': 50, 'repeatMonths': 6}));
      await pumpApp(t);
      await t.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await t.pumpAndSettle();
      await shot(t, 'm168_phone_add_record_off');
    }, skip: !_goldens);
  });
}
