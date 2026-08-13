/// م176 — تحسينات بطاقة صور الأشعة (قرار المالك):
///   • نقطة نجاح الرفع الحمراء بجانب الاسم بدل شارة «مرفوعة» — تظهر
///     مرةً واحدة: فتحٌ جديد للتطبيق بعد مشاهدتها لا يظهرها ثانيةً.
///   • حجم الملف بجانب التاريخ (صياغة humanBytesAr).
///   • خط المساحة المصغر برأس البطاقة (المستخدم من الكلي) — يتحدث
///     تلقائياً بعد حذف صورة.
///   • التعديل والحذف مجموعان بقائمة ثلاث نقاطٍ واحدة (تغطيها أيضاً
///     اختبارات م142/م15/م4c المحدثة).
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
    show XrayPick, xrayFilePickProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'staff_test_session.dart' show staffAdminSession;

/// مزيّف R2 — توأم مزيّف م15 (يخزن ويعيد).
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

Uint8List _png({int w = 60, int h = 40}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 100, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m176_');
    syncFlags.resetForTest();
  });
  tearDown(() {
    syncFlags.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinics': ['ع1'],
    'services': ['حشو'],
    'payments': ['كاش'],
  };

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> boot(
    WidgetTester tester, {
    required XrayPick pick,
    required XrayRemote remote,
    bool seed = true,
  }) async {
    if (seed) {
      final c = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config());
      saveNewRecord(
        c.read(reposProvider),
        config(),
        SaveRecordInput(
          name: 'هدى',
          date: getCurrentDate(),
          amount: 100,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
        ),
      );
      c.dispose();
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          xrayFilePickProvider.overrideWithValue(pick),
          r2ClientProvider.overrideWithValue(remote),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openXrays(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('patient-search')), 'هدى');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('patient-card-هدى')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('psec-xrays')),
      warnIfMissed: false,
    );
    await settle(tester);
  }

  Future<void> uploadTap(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('xray-upload')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('xray-upload')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('xr-src-files')));
    await settle(tester);
    await settle(tester);
    await settle(tester);
  }

  testWidgets(
    'النقطة الحمراء مرة واحدة + الحجم بجانب التاريخ + خط المساحة يتحدث',
    (tester) async {
      final png = _png();
      final remote = FakeRemote();
      await boot(tester, pick: () async => [('scan.png', png)], remote: remote);
      await openXrays(tester);
      await uploadTap(tester);
      expect(find.text('تم رفع صور الأشعة بنجاح'), findsOneWidget);

      // العرض التفصيلي.
      await tester.tap(
        find.byKey(const Key('xray-seg-details')),
        warnIfMissed: false,
      );
      await settle(tester);

      // (1) النقطة الحمراء ظاهرة ولا شارة «مرفوعة».
      expect(find.byKey(const Key('xray-dot-0')), findsOneWidget);
      expect(find.text('مرفوعة'), findsNothing);

      // (2) الحجم بجانب التاريخ (التاريخ · الحجم بالبايت/كيلوبايت).
      final ds = tester
          .widget<Text>(find.byKey(const Key('xray-datesize-0')))
          .data!;
      expect(ds.contains('·'), isTrue, reason: 'التاريخ والحجم معاً: $ds');
      expect(
        RegExp(r'^[\d.,]+ ').hasMatch(ds.split('·').last.trim()),
        isTrue,
        reason: 'الحجم رقمٌ بوحدته (صياغة humanBytesAr): $ds',
      );

      // (3) خط المساحة المصغر برأس البطاقة.
      final mini0 = tester
          .widget<Text>(find.byKey(const Key('xray-storage-mini')))
          .data!;
      expect(mini0.contains('من'), isTrue);

      // (4) حذف الصورة من قائمة الثلاث نقاط ⇒ الخط يتحدث تلقائياً.
      await tester.tap(find.byKey(const Key('xray-more-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('xray-del-btn-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      // انقضاء مهلة التراجع (3 ثوان) ⇒ الحذف الفعلي وتحرر المساحة.
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);
      final mini1 = tester
          .widget<Text>(find.byKey(const Key('xray-storage-mini')))
          .data!;
      expect(mini1, isNot(equals(mini0)),
          reason: 'المساحة المستخدمة نقصت بعد الحذف');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('النقطة لا تعود بعد المشاهدة (فتح جديد للتطبيق)',
      (tester) async {
    final png = _png();
    final remote = FakeRemote();
    await boot(tester, pick: () async => [('scan.png', png)], remote: remote);
    await openXrays(tester);
    await uploadTap(tester);
    await tester.tap(
      find.byKey(const Key('xray-seg-details')),
      warnIfMissed: false,
    );
    await settle(tester);
    // المشاهدة الأولى: النقطة ظاهرة (وتُختم محلياً).
    expect(find.byKey(const Key('xray-dot-0')), findsOneWidget);

    // فتحٌ جديد للتطبيق (نفس قاعدة البيانات) ⇒ لا نقطة.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await boot(tester,
        pick: () async => [], remote: remote, seed: false);
    await openXrays(tester);
    await settle(tester);
    expect(find.byKey(const Key('xray-dot-0')), findsNothing,
        reason: 'شوهدت مرةً — لا تظهر ثانيةً (قرار المالك)');
    // الصف نفسه موجود (الصورة باقية).
    expect(find.byKey(const Key('xray-datesize-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
