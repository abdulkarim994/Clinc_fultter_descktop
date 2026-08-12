/// م171 — لقطةٌ للمراجعة (GOLDENS=1 محلياً فقط): تبويب «المواعيد» في
/// بطاقة المريض (بعد الديون وقبل الأشعة) بموعدٍ محجوزٍ قادم وزر حجزٍ
/// سريع. عدة الخطوط من م154.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    hide JMap;
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m171g_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  testWidgets('بطاقة المريض — تبويب المواعيد بموعدٍ قادم', (t) async {
    debugForceDesktopUi = false;
    t.view.physicalSize = const Size(440, 1000);
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
      'clinics': ['د.عبدالفتاح الدليمي'],
      'services': ['حشو'],
      'payments': ['كاش', 'تحويل'],
    });
    final repos = s.read(reposProvider);
    final now = DateTime.now();
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'محمد علي',
      'date': ymd(now),
      'amount': 300,
      'paid': 300,
      'payment': 'كاش',
      'clinic': 'د.عبدالفتاح الدليمي',
      '_t': 'r',
    });
    for (var i = 0; i < 2; i++) {
      repos.appointments.upsertLocal({
        'id': 'ap$i',
        'name': 'محمد علي',
        'date': ymd(now.add(Duration(days: 3 + i * 4))),
        'time': i == 0 ? '10:30' : '16:00',
        'clinic': 'د.عبدالفتاح الدليمي',
        'status': 'pending',
        '_t': 'a',
      });
    }
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
            child: PatientProfileScreen(
              patientName: 'محمد علي',
              clinic: 'د.عبدالفتاح الدليمي',
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('psec-appts')));
    await t.pump(const Duration(milliseconds: 400));

    if (_goldens) {
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/m171_profile_appts.png'));
    }
  }, skip: !_goldens);
}
