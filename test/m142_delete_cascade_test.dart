/// اختبارات م142 — الحذف الحقيقي لصور الأشعة (تراجع 3ث + تصريف R2 فوري)،
/// تعطّف حذف المريض على R2/الحصة/حارس المحذوف، وعدّاد صور الأشعة في تأكيد
/// الحذف. تعتمد مزيّفات خفيفة (طرف R2 بعيد + قاعدة بالذاكرة + مقياس حصة
/// حقيقي فوقها) — لا شبكة ولا تشغيل السويت كاملاً.
///
/// التغطية:
///   (أ) نافذة التراجع الافتراضية 3، و0 تُعطّلها (حذفٌ فوري بلا شريط).
///   (ب) عند انقضاء المؤقت: المفتاح مصفوفٌ للحذف + حارس المحذوف مضبوط +
///       الحصة تنقص.
///   (ج) التراجع يُلغي — لا حذف ولا صف.
///   (د) الحذف الجماعي يحترم بوابة الموظفين.
///   (هـ) drainDeletes يستدعي remote.delete لكل مفتاح، ويفرّغ الناجح فقط،
///       وreportUp يُطلَق حين deleted>0.
///   (و) تعطّف حذف المريض: صفٌّ + بوابة + نقص حصة لكل مفتاح أشعة، وعدّاد
///       التأكيد = طول xrayKeysFor.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart'
    show XrayRemote, R2HeadResult;
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/db_sync.dart'
    show getMetaValue, setMetaValue;
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show StorageTransport;
import 'package:dental_clinic_flutter/features/patients/profile_actions.dart'
    show deletePatientData;
import 'package:dental_clinic_flutter/features/staff/staff_session.dart'
    show kCurrentStaff;
import 'package:dental_clinic_flutter/features/xrays/storage_meter.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart'
    show XrayPipeline, enqueuePendingDelete, isXrayDeleted, pendingDeletes;
import 'package:dental_clinic_flutter/features/xrays/xray_section.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// طرف R2 بعيد مزيّف — يسجّل الحذف ويسمح ببرمجة الفشل.
class _FakeRemote implements XrayRemote {
  final deleted = <String>[];
  final Map<String, Uint8List> objects = {};
  bool failDelete = false;

  @override
  Future<String> upload(
    Uint8List bytes,
    String key, {
    String patientName = '',
    String fileName = '',
    String contentType = 'image/jpeg',
  }) async {
    objects[key] = bytes;
    return key;
  }

  @override
  Future<R2HeadResult> headObject(String key) async =>
      R2HeadResult(ok: objects.containsKey(key), size: objects[key]?.length);

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async =>
      objects[key];

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw Exception('offline');
    deleted.add(key);
    objects.remove(key);
  }
}

/// خادم تخزين مزيّف — يسجّل نداءات التبليغ (reportUp).
class _FakeStorageCloud implements StorageTransport {
  final reports = <(int, int)>[];

  @override
  Future<Map<String, Object?>> getMyStorage() async => const {
    'used_bytes': 0,
    'file_count': 0,
    'quota_bytes': 200 * 1024 * 1024,
  };

  @override
  Future<Map<String, Object?>> reportMyStorage(int used, int files) async {
    reports.add((used, files));
    return {'used_bytes': used, 'file_count': files, 'quota_bytes': 1 << 30};
  }
}

Uint8List _png({int w = 60, int h = 40}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 100, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m142_');
    kCurrentStaff = null; // بلا جلسة ⇒ البوابة تسمح (سلوك الاختبارات).
  });
  tearDown(() {
    kCurrentStaff = null;
    tmp.deleteSync(recursive: true);
  });

  // ── وحدات نقية ─────────────────────────────────────────────────────────

  group('م142/أ — قراءة مدة التراجع من البيانات الوصفية', () {
    test('غياب المفتاح ⇒ الافتراضي 3؛ التخزين يدور ذهاباً وإياباً', () {
      final db = LocalDb.open(':memory:');
      addTearDown(db.close);
      // العقد: null ⇒ الافتراضي 3.
      expect(getMetaValue(db, 'xray.delete_undo_secs'), isNull);
      // ضبط 0 (تعطيل) ثم 5 — نقرأ القيمة الخام كما يقرؤها الودجت.
      setMetaValue(db, 'xray.delete_undo_secs', '0');
      expect('${getMetaValue(db, 'xray.delete_undo_secs')}', '0');
      setMetaValue(db, 'xray.delete_undo_secs', '5');
      expect(int.parse('${getMetaValue(db, 'xray.delete_undo_secs')}'), 5);
    });
  });

  group('م142/هـ — drainDeletes: حذف R2 لكل مفتاح + reportUp عند النجاح', () {
    test('النجاح يفرّغ الطابور ويستدعي delete لكل مفتاح ويبلّغ الخادم', () async {
      final db = LocalDb.open(':memory:');
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      );
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      final remote = _FakeRemote();
      final cloud = _FakeStorageCloud();
      final meter = StorageMeter(db, cloud: cloud);
      final pipe = XrayPipeline(
        db: db,
        repos: repos,
        store: XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1'),
        remote: remote,
        meter: meter,
      );

      enqueuePendingDelete(db, 'srv/a.jpg');
      enqueuePendingDelete(db, 'srv/b.jpg');
      expect(pendingDeletes(db), ['srv/a.jpg', 'srv/b.jpg']);

      final res = await pipe.drainDeletes();
      await pumpEventQueue(); // reportUp غير مُنتظَر (unawaited)

      expect(res.deleted, 2);
      expect(res.kept, 0);
      expect(remote.deleted, ['srv/a.jpg', 'srv/b.jpg']);
      expect(pendingDeletes(db), isEmpty);
      expect(cloud.reports, isNotEmpty, reason: 'reportUp حين deleted>0');
    });

    test('الفشل يُبقي المفتاح ولا يبلّغ (deleted==0)', () async {
      final db = LocalDb.open(':memory:');
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      );
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      final remote = _FakeRemote()..failDelete = true;
      final cloud = _FakeStorageCloud();
      final pipe = XrayPipeline(
        db: db,
        repos: repos,
        store: XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1'),
        remote: remote,
        meter: StorageMeter(db, cloud: cloud),
      );
      enqueuePendingDelete(db, 'srv/a.jpg');

      final res = await pipe.drainDeletes();
      await pumpEventQueue();

      expect(res.deleted, 0);
      expect(res.kept, 1);
      expect(pendingDeletes(db), ['srv/a.jpg'], reason: 'يُحتفَظ للإعادة');
      expect(cloud.reports, isEmpty, reason: 'لا تبليغ بلا حذفٍ ناجح');
    });
  });

  group('م142/و — تعطّف حذف المريض على R2/الحصة/حارس المحذوف', () {
    test('كل مفتاح أشعة: صفٌّ + حارسٌ + نقص حصة، وعدّاد التأكيد=xrayKeysFor', () {
      final db = LocalDb.open(':memory:');
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      );
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      final cloud = _FakeStorageCloud();
      final meter = StorageMeter(db, cloud: cloud);

      // بذر صورتين للمريض عبر المخزن ثم المعرض في config.
      final store = XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1');
      final r1 = store.ingest('سالم', 'a.png', _png());
      final r2 = store.ingest('سالم', 'b.png', _png());
      var cfg = addXrayKeyToConfig(<String, Object?>{}, 'سالم', r1.key, 'a.png');
      cfg = addXrayKeyToConfig(cfg, 'سالم', r2.key, 'b.png');
      repos.settings.set('app.config', cfg);

      // الحصة تعرف حجم كلا المفتاحين (كأنهما رُفعا).
      meter.addUpload(r1.key, 1000);
      meter.addUpload(r2.key, 2000);
      expect(meter.usedBytes, 3000);

      // عدّاد التأكيد يُحسب من xrayKeysFor قبل التجريد.
      final imgCount = xrayKeysFor(cfg, 'سالم').length;
      expect(imgCount, 2);

      final keys = [r1.key, r2.key];
      deletePatientData(
        repos,
        cfg,
        name: 'سالم',
        db: db,
        meter: meter,
      );

      for (final k in keys) {
        expect(isXrayDeleted(db, k), isTrue, reason: 'حارس المحذوف لكل مفتاح');
        expect(pendingDeletes(db), contains(k), reason: 'طابور حذف R2');
      }
      expect(meter.usedBytes, 0, reason: 'الحصة نقصت بكل مفتاح');
      // المعرض جُرّد من config.
      final after = Map<String, Object?>.from(
        repos.settings.get('app.config') as Map,
      );
      expect(xrayKeysFor(after, 'سالم'), isEmpty);
    });
  });

  // ── ودجت: نافذة التراجع + البوابة (تُشغّل XraySection مباشرةً) ─────────────

  group('م142 — سلوك التراجع والبوابة في XraySection', () {
    /// يبذر مريضاً بصورٍ ثم يبني XraySection داخل حاوية حقيقية (المزوّدات
    /// تُشتقّ من dbDir). يعيد الحاوية للفحص بعد التفاعل.
    Future<ProviderContainer> mount(
      WidgetTester tester, {
      required int imageCount,
    }) async {
      final seed = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      );
      final repos = seed.read(reposProvider);
      final store = seed.read(xrayStoreProvider);
      var cfg = <String, Object?>{'centerName': 'م'};
      for (var i = 0; i < imageCount; i++) {
        final r = store.ingest('هدى', 'x$i.png', _png());
        cfg = addXrayKeyToConfig(cfg, 'هدى', r.key, 'x$i.png');
      }
      repos.settings.set('app.config', cfg);
      seed.dispose();

      // سطحٌ أطول كي يبقى شريط SnackBar (وزر «تراجع») داخل الحدود القابلة
      // للنقر. نتجنّب SingleChildScrollView حتى لا يزيح الشريطَ العائمَ
      // خارج الشاشة (القسم صغير بصورةٍ أو اثنتين فلا يحتاج تمريراً).
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: XraySection(patientName: 'هدى', clinic: ''),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return c;
    }

    // كتابة الإعدادات في XraySection تُبلَّغ عبر نبضة post-frame على
    // configRevProvider، فيلزم إطارٌ للنبضة وآخر لإعادة بناء المستهلِك.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    List<String> keysOf(ProviderContainer c) {
      final cfg = Map<String, Object?>.from(
        c.read(reposProvider).settings.get('app.config') as Map,
      );
      return xrayKeysFor(cfg, 'هدى');
    }

    testWidgets('(أ) الافتراضي 3: شريط «سيُحذف بعد 3 ثوانٍ» يظهر ولا يُحذف بعد', (
      tester,
    ) async {
      final c = await mount(tester, imageCount: 1);
      expect(keysOf(c), hasLength(1));
      // العرض التفصيلي كي يظهر زر حذف السطر.
      await tester.tap(find.byKey(const Key('xray-seg-details')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('xray-del-btn-0')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('سيُحذف بعد 3 ثوانٍ'), findsOneWidget);
      expect(keysOf(c), hasLength(1), reason: 'مؤجَّل — لم يُحذف بعد');
      expect(pendingDeletes(c.read(localDbProvider)), isEmpty);

      // بعد انقضاء المؤقت: يُحذف فعلاً.
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(keysOf(c), isEmpty);
      expect(find.text('تم حذف الصورة'), findsOneWidget);
    });

    testWidgets('(أ) الصفر يُعطّل: حذفٌ فوري بلا شريط تراجع', (tester) async {
      final c = await mount(tester, imageCount: 1);
      // 0 = تعطيل نافذة التراجع.
      setMetaValue(c.read(localDbProvider), 'xray.delete_undo_secs', '0');
      final key = keysOf(c).single;

      await tester.tap(find.byKey(const Key('xray-seg-details')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('xray-del-btn-0')));
      await settle(tester);

      expect(find.textContaining('سيُحذف بعد'), findsNothing);
      expect(find.text('تم حذف الصورة'), findsOneWidget);
      expect(keysOf(c), isEmpty, reason: 'حُذف فوراً');
      expect(isXrayDeleted(c.read(localDbProvider), key), isTrue);
      expect(pendingDeletes(c.read(localDbProvider)), contains(key));
    });

    testWidgets('(ب) الانقضاء: المفتاح مصفوفٌ + حارسٌ + الحصة تنقص', (
      tester,
    ) async {
      final c = await mount(tester, imageCount: 1);
      final db = c.read(localDbProvider);
      final key = keysOf(c).single;
      // الحصة تعرف حجم المفتاح كي نلمس نقصها بعد الحذف.
      c.read(storageMeterProvider).addUpload(key, 4096);
      expect(c.read(storageMeterProvider).usedBytes, 4096);

      await tester.tap(find.byKey(const Key('xray-seg-details')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('xray-del-btn-0')));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(pendingDeletes(db), contains(key));
      expect(isXrayDeleted(db, key), isTrue);
      expect(c.read(storageMeterProvider).usedBytes, 0, reason: 'الحصة نقصت');
      expect(keysOf(c), isEmpty);
    });

    testWidgets('(ج) التراجع يُلغي — لا حذف ولا صف', (tester) async {
      final c = await mount(tester, imageCount: 1);
      final db = c.read(localDbProvider);
      final key = keysOf(c).single;
      c.read(storageMeterProvider).addUpload(key, 4096);

      await tester.tap(find.byKey(const Key('xray-seg-details')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('xray-del-btn-0')));
      await tester.pump(const Duration(milliseconds: 300));

      // «تراجع» قبل انقضاء المؤقت. نستدعي رَدّ الفعل مباشرةً بدل نقرٍ حساسٍ
      // لموضع الشريط العائم في اختبار الودجت (نختبر ربط التراجع والإلغاء لا
      // بكسل الموضع): زر SnackBarAction الوحيد المعروض.
      final action = tester.widget<SnackBarAction>(
        find.byType(SnackBarAction),
      );
      action.onPressed();
      await tester.pump(const Duration(milliseconds: 200));
      // اترك ما يفوق المؤقت للتأكد أن الحذف أُلغي فعلاً.
      await tester.pump(const Duration(seconds: 4));
      await settle(tester);

      expect(keysOf(c), hasLength(1), reason: 'لم يُحذف — التراجع ألغى');
      expect(pendingDeletes(db), isEmpty);
      expect(isXrayDeleted(db, key), isFalse);
      expect(c.read(storageMeterProvider).usedBytes, 4096);
    });

    testWidgets('(د) الحذف الجماعي يحترم بوابة الموظفين', (tester) async {
      // موظفٌ بلا صلاحية records.delete ⇒ البوابة تمنع.
      kCurrentStaff = <String, Object?>{
        'id': 'u',
        'username': 'staff',
        'name': 'موظف',
        'role': 'staff',
        'perms': <String, Object?>{},
      };
      final c = await mount(tester, imageCount: 2);
      final db = c.read(localDbProvider);
      final before = keysOf(c);
      expect(before, hasLength(2));

      // دخول التحديد المتعدد بالضغط المطوّل ثم تحديد الثانية.
      await tester.longPress(find.byKey(const Key('xray-thumb-0')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('xray-thumb-1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2 محددة'), findsOneWidget);

      await tester.tap(find.byKey(const Key('xray-ms-del')));
      await tester.pump(const Duration(milliseconds: 200));
      // لا شريط تراجع، ولا حذف — بل رسالة المنع.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));

      expect(keysOf(c), hasLength(2), reason: 'البوابة منعت الحذف الجماعي');
      expect(pendingDeletes(db), isEmpty);
      for (final k in before) {
        expect(isXrayDeleted(db, k), isFalse);
      }
      expect(find.textContaining('تتطلب صلاحية'), findsOneWidget);
    });
  });
}
