/// م164 — لقطاتٌ للمراجعة (GOLDENS=1): شاشة الحجوزات الجديدة للهاتف
/// (رقائق العيادات + شريط الأيام + Timeline بخط «الآن» والاستراحة
/// والأرشيف)، معالجُ الإضافة، ورقة الإجراءات السريعة، وتبويبات العيادات
/// على سطح المكتب.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m164g_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'عيادة الصفوة',
        'clinics': ['الصفوة', 'كاريزما'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'workdayStart': '09:00',
        'workdayEnd': '17:00',
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  void seed(ProviderContainer c) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate();
    final tomorrow = () {
      final d = DateTime.parse('${today}T00:00:00')
          .add(const Duration(days: 1));
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }();
    void appt(String id, String name, String time, String service,
        String status, String clinic,
        {int? dur, int isBreak = 0, String? archivedOn, String? date}) {
      repos.appointments.upsertLocal({
        'id': id,
        'name': name,
        'phone': '0912345678',
        'date': date ?? today,
        'time': time,
        'service': service,
        'status': status,
        'clinic': clinic,
        'clinic_id': 'c-$clinic',
        'durationMin': ?dur,
        if (isBreak == 1) 'isBreak': 1,
        'archivedOn': ?archivedOn,
        '_t': 'a',
      });
    }

    appt('a1', 'أحمد محمد', '09:00', 'تنظيف لثة', 'confirmed', 'الصفوة');
    appt('a2', 'سارة علي', '09:30', 'حشوة', 'waiting', 'الصفوة');
    appt('b1', 'استراحة', '10:00', '', 'pending', 'الصفوة',
        dur: 30, isBreak: 1);
    appt('a3', 'محمد أحمد', '10:30', 'علاج عصب', 'pending', 'الصفوة',
        dur: 60);
    appt('a4', 'ليلى حسن', '13:00', 'تركيبات', 'in_treatment', 'الصفوة');
    appt('done1', 'خالد يوسف', '08:30', 'كشف', 'completed', 'الصفوة',
        archivedOn: getCurrentDate());
    appt('ns1', 'مها سعيد', '08:00', 'كشف', 'no_show', 'الصفوة',
        archivedOn: getCurrentDate());
    appt('k1', 'عمر فتحي', '11:00', 'كشف', 'pending', 'كاريزما');
    appt('f1', 'هدى سالم', '09:00', 'متابعة', 'pending', 'الصفوة',
        date: tomorrow);
  }

  Future<ProviderContainer> boot(WidgetTester t,
      {Size size = const Size(420, 1050)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c0 = ProviderContainer(overrides: ov());
    final auth = c0.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c0.read(reposProvider).settings.set('app.config', config());
    seed(c0);
    c0.dispose();
    return ProviderContainer(overrides: ov());
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  Future<void> pumpPhone(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AppointmentsTab()),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('م164 — الهاتف: Timeline العيادة مع الاستراحة والأرشيف',
      (t) async {
    final c = await boot(t);
    await pumpPhone(t, c);
    // اختر عيادة الصفوة.
    await t.tap(find.byKey(const Key('appt-clinic-الصفوة')));
    await t.pumpAndSettle();
    await shot(t, 'm164_phone_timeline');
  }, skip: !_goldens);

  testWidgets('م164 — الهاتف: معالج الإضافة (عيادة/تاريخ/أوقات/مريض)',
      (t) async {
    final c = await boot(t, size: const Size(420, 1150));
    await pumpPhone(t, c);
    await t.tap(find.byKey(const Key('appt-clinic-الصفوة')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appt-add-toggle')));
    await t.pumpAndSettle();
    await shot(t, 'm164_phone_wizard');
  }, skip: !_goldens);

  testWidgets('م164 — الهاتف: ورقة الإجراءات السريعة', (t) async {
    final c = await boot(t, size: const Size(420, 1150));
    await pumpPhone(t, c);
    await t.tap(find.byKey(const Key('appt-clinic-الصفوة')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appt-row-a2')));
    await t.pumpAndSettle();
    await shot(t, 'm164_phone_actions');
  }, skip: !_goldens);

  testWidgets('م165 — خمس عيادات: الرأس المضغوط بالزر المنسدل', (t) async {
    final c = await boot(t);
    // خمس عيادات (واقع المالك) — تُكتب فوق الإعدادات قبل الضخ.
    final c0 = ProviderContainer(overrides: ov());
    c0.read(reposProvider).settings.set('app.config', {
      ...config(),
      'clinics': ['الصفوة', 'كاريزما', 'د.عبدالفتاح الدليمي', 'د.عبدالكريم', 'د.ملاذ رجب'],
    });
    c0.dispose();
    await pumpPhone(t, c);
    await t.tap(find.byKey(const Key('appt-clinic-pill')));
    await t.pumpAndSettle();
    await shot(t, 'm165_phone_clinic_sheet');
    await t.tap(find.byKey(const Key('appt-clinic-الصفوة')));
    await t.pumpAndSettle();
    await shot(t, 'm165_phone_compact');
  }, skip: !_goldens);

  testWidgets('م164 — الكمبيوتر: تبويبات العيادات فوق الجدولة', (t) async {
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
    await t.pumpWidget(
        ProviderScope(overrides: ov(), child: const DentalApp()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    // إغلاق إشعار «مواعيد اليوم» المنبثق عند الفتح (يحجب النقر).
    if (find.byKey(const Key('appt-notif-ok')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('appt-notif-ok')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const Key('desk-tab-calendar')),
        warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('appt-week-view')), findsOneWidget,
        reason: 'شاشة الحجوزات المكتبية معروضة');
    // تبويب عيادة الصفوة.
    await t.tap(find.byKey(const Key('appt-desk-clinic-الصفوة')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await shot(t, 'm164_desktop_tabs');
  }, skip: !_goldens);
}
