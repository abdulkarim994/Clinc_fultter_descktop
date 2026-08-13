/// م176 — لقطة للمراجعة (GOLDENS=1 محلياً فقط): بطاقة صور الأشعة
/// بالعرض التفصيلي بعد التحسينات — نقطة نجاح الرفع الحمراء، الحجم بجانب
/// التاريخ، خط المساحة برأس البطاقة، وزر قائمة الثلاث نقاط (مفتوحةً).
/// عدة الخطوط من م154.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart'
    show XrayRemote, R2HeadResult;
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/features/xrays/xray_section.dart'
    show xrayFilePickProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show ByteData, EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

class FakeRemote implements XrayRemote {
  final store = <String, Uint8List>{};

  @override
  Future<String> upload(
    Uint8List bytes,
    String key, {
    String patientName = '',
    String fileName = '',
    String contentType = 'image/jpeg',
  }) async {
    store[key] = bytes;
    return key;
  }

  @override
  Future<R2HeadResult> headObject(String key) async =>
      R2HeadResult(ok: store.containsKey(key), size: store[key]?.length);

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async =>
      store[key];

  @override
  Future<void> delete(String key) async => store.remove(key);
}

Uint8List _png() {
  final im = img.Image(width: 60, height: 40);
  img.fill(im, color: img.ColorRgb8(120, 130, 140));
  return Uint8List.fromList(img.encodePng(im));
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
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m176g_');
    syncFlags.resetForTest();
  });
  tearDown(() {
    syncFlags.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('لقطة م176 — بطاقة الأشعة التفصيلية بالقائمة المفتوحة',
      (t) async {
    t.view.physicalSize = const Size(440, 1050);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'عيادة الصفوة',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    saveNewRecord(
      c.read(reposProvider),
      {'clinics': ['ع1'], 'services': ['حشو'], 'payments': ['كاش']},
      SaveRecordInput(
        name: 'محمد علي',
        date: getCurrentDate(),
        amount: 100,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    c.dispose();
    final remote = FakeRemote();
    final png = _png();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          xrayFilePickProvider
              .overrideWithValue(() async => [('scan.png', png)]),
          r2ClientProvider.overrideWithValue(remote),
        ],
        child: const DentalApp(),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await t.tap(ok);
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.tap(find.text('السجلات'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byKey(const Key('patient-search')), 'محمد');
    await settle(t);
    await t.tap(find.byKey(const Key('patient-card-محمد علي')),
        warnIfMissed: false);
    await settle(t);
    await t.tap(find.byKey(const Key('psec-xrays')), warnIfMissed: false);
    await settle(t);
    // رفع صورة (أونلاين — تُرفع فوراً فتظهر النقطة الحمراء).
    await t.scrollUntilVisible(
      find.byKey(const Key('xray-upload')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('xray-upload')), warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.byKey(const Key('xr-src-files')));
    await settle(t);
    await settle(t);
    await settle(t);
    // العرض التفصيلي + فتح قائمة الثلاث نقاط للقطة.
    await t.tap(find.byKey(const Key('xray-seg-details')),
        warnIfMissed: false);
    await settle(t);
    await t.tap(find.byKey(const Key('xray-more-0')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5)); // تصريف سنackbar الرفع.
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/m176_xray_card.png'));
  }, skip: !_goldens);
}
