/// م173 — لقطاتٌ للمراجعة (GOLDENS=1 محلياً فقط): واجهة الحجز الجديدة —
/// رأس «الحجز» بالمحدد الكبير مع تبويب الجدول، تبويب «أرشيف اليوم»
/// بفلاتره، تبويب «المواعيد القادمة» المجمع بالأيام، وشاشة مراجعة
/// لقطات الكاميرا. عدة الخطوط من م154.
library;

import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_review_screen.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show EventChannel, FontLoader, MethodChannel;
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

/// PNG شفاف 1×1 — عيّنات لقطات شاشة المراجعة (نفس ثابت اختبار المراجعة).
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOoaOr5'
  'DwAFggKGrvU4EwAAAABJRU5ErkJggg==',
);

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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m173g_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(440, 1050);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'عيادة الصفوة',
      'clinics': ['الصفوة', 'كاريزما'],
      'services': ['حشو', 'كشف'],
      'payments': ['كاش', 'تحويل'],
      'workdayStart': '09:00',
      'workdayEnd': '13:00',
    });
    final repos = s.read(reposProvider);
    final today = getCurrentDate();
    final base = DateTime.parse('${today}T00:00:00');
    Map<String, Object?> a(String id, String date, String time, String name,
            {String status = 'pending', String? archivedOn}) =>
        {
          'id': id,
          'name': name,
          'date': date,
          'time': time,
          'service': 'كشف',
          'status': status,
          'archivedOn': ?archivedOn,
          'clinic': 'الصفوة',
          '_t': 'a',
        };
    repos.appointments.upsertLocal(a('t1', today, '09:00', 'محمد علي'));
    repos.appointments.upsertLocal(a('t2', today, '10:30', 'هدى سالم'));
    repos.appointments.upsertLocal(a('c1', today, '11:00', 'وليد منجز',
        status: 'completed', archivedOn: today));
    repos.appointments.upsertLocal(a('c2', today, '12:00', 'سعاد ملغاة',
        status: 'cancelled', archivedOn: today));
    repos.appointments.upsertLocal(a(
        'u1',
        ymd(base.add(const Duration(days: 2))),
        '09:30',
        'قادم أول'));
    repos.appointments.upsertLocal(a(
        'u2',
        ymd(base.add(const Duration(days: 2))),
        '11:00',
        'قادم ثانٍ'));
    repos.appointments.upsertLocal(a(
        'u3',
        ymd(base.add(const Duration(days: 6))),
        '10:00',
        'قادم بعيد'));
    s.dispose();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: AppointmentsTab()),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    // اختيار «الصفوة» من محدد الرأس.
    await t.tap(find.byKey(const Key('appt-clinic-pill')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('appt-clinic-الصفوة')));
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  group('لقطات م173 — واجهة الحجز الجديدة', () {
    testWidgets('تبويب الجدول: الرأس الكبير + المؤشر المنزلق', (t) async {
      await boot(t);
      await shot(t, 'm173_booking_schedule');
    }, skip: !_goldens);

    testWidgets('تبويب أرشيف اليوم بفلاتره', (t) async {
      await boot(t);
      await t.tap(find.byKey(const Key('appt-tab-archive')));
      await t.pumpAndSettle();
      await shot(t, 'm173_booking_archive');
    }, skip: !_goldens);

    testWidgets('تبويب القادمة مجمعاً بالأيام', (t) async {
      await boot(t);
      await t.tap(find.byKey(const Key('appt-tab-upcoming')));
      await t.pumpAndSettle();
      await shot(t, 'm173_booking_upcoming');
    }, skip: !_goldens);

    testWidgets('شاشة مراجعة لقطات الكاميرا', (t) async {
      t.view.physicalSize = const Size(440, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: XrayReviewScreen(
              patientName: 'محمد علي',
              shots: [for (var i = 0; i < 5; i++) ('s$i.jpg', _png)],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      // إلغاء تحديد الثالثة — لإظهار حالتَي التحديد معاً.
      await t.tap(find.byKey(const Key('xray-rev-item-2')));
      await t.pumpAndSettle();
      await shot(t, 'm173_camera_review');
    }, skip: !_goldens);
  });
}
