/// م177 — لقطات للمراجعة (GOLDENS=1 محلياً فقط): شاشة الدور الكاملة
/// بالهاتف (الترويسة الجديدة + التبويبات المنزلقة + البطل والقائمة)،
/// ورقة الإضافة المنبثقة، ولوحة الكمبيوتر العريضة. عدة الخطوط من م154.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/queue/queue_screen.dart'
    show queueViewProvider;
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m177g_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> seed() async {
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'عيادة الصفوة',
      'clinics': ['د.عبدالكريم الإبراهيم'],
      'services': ['حشو'],
      'payments': ['كاش'],
      'bookingSystem': 'queue',
      'queueMorningStart': '10:00',
      'queueSlotMin': 20,
    });
    final today = getCurrentDate();
    final repos = s.read(reposProvider);
    Map<String, Object?> row(int seq, String name,
            {String status = 'new', String notes = ''}) =>
        {
          'id': 'q$seq',
          'clinic': 'د.عبدالكريم الإبراهيم',
          'clinic_id': 'د.عبدالكريم الإبراهيم',
          'date': today,
          'period': 'morning',
          'seq': seq,
          'patient_name': name,
          'phone': '091111111$seq',
          'status': status,
          'notes': notes,
          'est_time': seq == 1 ? '10:00' : (seq == 2 ? '10:20' : '10:40'),
          'est_manual': 0,
          'state': 'waiting',
          'created_at': jsIsoNow(),
        };
    repos.queue.upsertLocal(row(1, 'محمد حسين المحمد', notes: 'حشو ضرس'));
    repos.queue.upsertLocal(row(2, 'هدى سالم', status: 'review'));
    repos.queue.upsertLocal(row(3, 'وليد أحمد'));
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

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));

  testWidgets('لقطة م177 — لوحة الدور الكاملة (هاتف)', (t) async {
    await seed();
    await pumpApp(t, desktop: false);
    await t.tap(find.text('الحجوزات'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('clinic-د.عبدالكريم الإبراهيم')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await shot(t, 'm177_queue_board_phone');
  }, skip: !_goldens);

  testWidgets('لقطة م177 — ورقة الإضافة المنبثقة', (t) async {
    await seed();
    await pumpApp(t, desktop: false);
    await t.tap(find.text('الحجوزات'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('clinic-د.عبدالكريم الإبراهيم')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('queue-fab-add')),
        warnIfMissed: false);
    await t.pumpAndSettle();
    await shot(t, 'm177_queue_add_sheet');
  }, skip: !_goldens);

  testWidgets('لقطة م177 — لوحة الكمبيوتر العريضة', (t) async {
    await seed();
    await pumpApp(t, desktop: true);
    // فتح تبويب الحجوزات ثم العيادة.
    await t.tap(find.byKey(const Key('desk-tab-calendar')),
        warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    final c = ProviderScope.containerOf(
      t.element(find.byType(DentalApp)),
      listen: false,
    );
    c.read(queueViewProvider.notifier).openClinic('د.عبدالكريم الإبراهيم');
    await t.pumpAndSettle();
    await shot(t, 'm177_queue_board_desktop');
  }, skip: !_goldens);
}
