/// م190 — لقطات للمراجعة (GOLDENS=1 محلياً فقط): جدول الأرباح والخسائر
/// السنوي بعد إعادة التصميم — الكمبيوتر بأعمدته التسعة المنتهية بعمود
/// «صافي العيادة» المظلَّل، والهاتف بجدوله المختصر (إيرادٌ بعد المختبرات،
/// بلا عمود مصروفات، وصافٍ شامل) وأيقونةِ التكبير. البذرة تحوي تركيبات
/// بقيمة معمل + تحاليل + مصروفات فتظهر كل الأعمدة معاً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/desktop/screens/profits_desktop.dart'
    show desktopProfitsViewProvider;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show ByteData, EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m190g_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'عيادة الصفوة',
        'clinics': ['د.عبدالكريم الإبراهيم', 'عيادة الفرع'],
        'services': ['حشو', 'تنظيف', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'doctorPct': 50,
      };

  final year = '${DateTime.now().year}';
  final month = '${DateTime.now().month}'.padLeft(2, '0');

  Future<void> seed() async {
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = s.read(reposProvider);
    repos.settings.set('app.config', config());
    void save(String name, String date, num amount, String clinic,
        String payment,
        {String service = 'حشو'}) {
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: name,
          date: date,
          amount: amount,
          clinic: clinic,
          service: service,
          payment: payment,
        ),
      );
    }

    // اليوم (يُظهر صفوف كشف الحساب بمداه الافتراضي «اليوم»).
    final today = getCurrentDate();
    save('نادر الشريف', today, 450, 'د.عبدالكريم الإبراهيم', 'كاش');
    save('آمنة الصادق', today, 300, 'عيادة الفرع', 'تحويل',
        service: 'تنظيف');
    // الشهر الحالي (يظهر في الشهرية) + أشهر متفرقة (تُغني السنوية).
    save('محمد حسين المحمد', '$year-$month-03', 1200,
        'د.عبدالكريم الإبراهيم', 'كاش');
    save('هدى سالم', '$year-$month-06', 800, 'د.عبدالكريم الإبراهيم',
        'تحويل', service: 'تنظيف');
    save('وليد أحمد', '$year-$month-10', 650, 'عيادة الفرع', 'كاش');
    save('سارة الطاهر', '$year-01-15', 2400, 'د.عبدالكريم الإبراهيم',
        'كاش');
    save('عمر بشير', '$year-02-20', 1500, 'عيادة الفرع', 'تحويل');
    save('ليلى مراد', '$year-03-08', 3100, 'د.عبدالكريم الإبراهيم',
        'كاش');
    // مصروفات: للشهر الحالي وليناير (يظهر أثرها في الصافي).
    repos.expenses.upsert({
      'id': 'exp-g1',
      'date': '$year-$month-08',
      'amount': 350,
      'category': 'كهرباء',
      'payment': 'كاش',
    });
    repos.expenses.upsert({
      'id': 'exp-g2',
      'date': '$year-01-20',
      'amount': 500,
      'category': 'إيجار',
      'payment': 'كاش',
    });
    // م188 — تحاليل ثلاثية للشهر الحالي: إيرادٌ خاصٌّ بالعيادة (لا يدخل
    // الإيراد ولا حصة الطبيب) — بها يظهر الصفّ الجديد في اللقطة.
    void anal(String id, String day, num amount, String clinic) {
      repos.records.upsertLocal({
        'id': id,
        'date': '$year-$month-$day',
        'name': 'مريض تحليل $id',
        'patient_name': 'مريض تحليل $id',
        'amount': amount,
        'clinic': clinic,
        'clinic_id': clinic,
        'service': 'تحاليل',
        'payment': 'كاش',
        'isAnalysis': 1,
        'isDebt': 0,
        'isPros': 0,
        'isDebtPayment': 0,
        'analysisName': 'التحاليل الثلاثية',
        'analysisOf': 'x',
        '_t': 'r',
      });
    }

    // م190 — تركيبتان بقيمة معمل: بهما يظهر عمودا «المختبرات» و«بعد
    // المختبرات» في الجدول الكامل.
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'فاطمة الزهراء',
        date: '$year-$month-09',
        amount: 2000,
        clinic: 'د.عبدالكريم الإبراهيم',
        service: 'تركيبات',
        payment: 'كاش',
        labValue: 700,
      ),
    );
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'يوسف الهادي',
        date: '$year-03-12',
        amount: 1600,
        clinic: 'عيادة الفرع',
        service: 'تركيبات',
        payment: 'تحويل',
        labValue: 500,
      ),
    );

    anal('g-an1', '04', 120, 'د.عبدالكريم الإبراهيم');
    anal('g-an2', '07', 120, 'عيادة الفرع');
    anal('g-an3', '11', 80, 'د.عبدالكريم الإبراهيم');
    s.dispose();
  }

  Future<void> pumpApp(WidgetTester t, {required bool desktop}) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize =
        desktop ? const Size(1500, 950) : const Size(440, 1050);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          builder: (ctx, child) => Directionality(
              textDirection: TextDirection.rtl, child: child!),
          home: const DentalApp(),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await t.tap(ok);
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openProfitsPhone(WidgetTester t) async {
    await t.tap(find.text('المالية'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('fin-seg-profits')),
        warnIfMissed: false);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));

  testWidgets('لقطة م190 — السنوية المختصرة (هاتف)', (t) async {
    await seed();
    await pumpApp(t, desktop: false);
    await openProfitsPhone(t);
    await t.tap(find.byKey(const Key('prof-view-yearly')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await shot(t, 'm190_year_phone_compact');
  }, skip: !_goldens);

  testWidgets('لقطة م190 — الجدول الكامل بالتكبير (هاتف)', (t) async {
    await seed();
    await pumpApp(t, desktop: false);
    await openProfitsPhone(t);
    await t.tap(find.byKey(const Key('prof-view-yearly')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('prof-pnl-expand')));
    await t.pumpAndSettle();
    await shot(t, 'm190_year_phone_full');
  }, skip: !_goldens);

  testWidgets('لقطة م190 — السنوية بأعمدتها التسعة (كمبيوتر)', (t) async {
    await seed();
    await pumpApp(t, desktop: true);
    await t.tap(find.byKey(const Key('desk-tab-finance')),
        warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
    final c = ProviderScope.containerOf(
      t.element(find.byType(DentalApp)),
      listen: false,
    );
    c.read(desktopProfitsViewProvider.notifier).state = 'yearly';
    await t.pumpAndSettle();
    await shot(t, 'm190_year_desktop_full');
  }, skip: !_goldens);
}
