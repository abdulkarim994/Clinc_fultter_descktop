/// اختبارات م15 — قسم صور الأشعة طبق الأصل (تصميم + أوفلاين/أونلاين):
///   • وحدات: مسترجِع المصغرات (جلب المصغرة، التراجع للنسخة الكاملة،
///     الفشل الأحمر، فرصة جديدة عند عودة الاتصال)، ترشيح عزل العيادة
///     (خلف العلم؛ القديمة غير الموسومة تظهر دائماً).
///   • واجهة: الرفع أوفلاين برسالة الطابور وشارة «بانتظار الرفع» والتاريخ
///     العربي، الرفع أونلاين بمزيّف R2 برسالة النجاح وشارة «مرفوعة»،
///     التحديد المتعدد بالضغط المطوّل وحذفه الجماعي حتى الإعدادات
///     والطوابير، مبدّل النمط يذكر التفضيل، وEnter يحفظ التسمية.
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
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart'
    show XrayThumbRestorer, pendingDeletes, isXrayDeleted;
import 'package:dental_clinic_flutter/features/xrays/xray_section.dart'
    show XrayPick, xrayFilePickProvider;
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'staff_test_session.dart' show staffAdminSession;

/// مزيّف R2 — يخزّن المرفوع ويعيده عند الجلب (تحقق المطابقة يمر).
class FakeRemote implements XrayRemote {
  final store = <String, Uint8List>{};
  final thumbs = <String, Uint8List>{};
  bool failFetch = false;
  int fetchCalls = 0;

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
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async {
    fetchCalls++;
    if (failFetch) throw Exception('offline');
    return thumb ? thumbs[key] : store[key];
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
    thumbs.remove(key);
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
    tmp = Directory.systemTemp.createTempSync('m15_');
    syncFlags.resetForTest();
  });
  tearDown(() {
    syncFlags.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinics': ['ع1', 'ع2'],
    'services': ['حشو'],
    'payments': ['كاش'],
  };

  ProviderContainer container({XrayRemote? remote}) => ProviderContainer(
    overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
      if (remote != null) r2ClientProvider.overrideWithValue(remote),
    ],
  );

  group('الوحدات — مسترجِع المصغرات', () {
    test('مصغرة غائبة تُجلب من R2 وتُخزَّن محلياً', () async {
      final c = container();
      addTearDown(c.dispose);
      final store = c.read(xrayStoreProvider);
      final remote = FakeRemote();
      remote.thumbs['k1'] = _png(w: 30, h: 20);
      var changes = 0;
      final r = XrayThumbRestorer(
        store: store,
        remote: remote,
        onChange: () => changes++,
      );

      expect(store.thumbnailBytes('k1'), isNull);
      r.request('k1', online: true);
      expect(r.isLoading('k1'), isTrue);
      await pumpEventQueue();
      expect(store.thumbnailBytes('k1'), isNotNull);
      expect(r.isFailed('k1'), isFalse);
      expect(changes, 1);
      // طلب لاحق والمصغرة موجودة: الواجهة لا تستدعيه أصلاً — وإن فعلت
      // فالمفتاح ليس فاشلاً ولا جارياً فيعاد جلبه بلا ضرر.
    });

    test('تعذّر المصغرة يتراجع للنسخة الكاملة ويولّد المصغرة منها', () async {
      final c = container();
      addTearDown(c.dispose);
      final store = c.read(xrayStoreProvider);
      final remote = FakeRemote();
      remote.store['k2'] = _png(); // نسخة كاملة فقط — لا مصغرة
      final r = XrayThumbRestorer(store: store, remote: remote);
      r.request('k2', online: true);
      await pumpEventQueue();
      expect(store.thumbnailBytes('k2'), isNotNull);
      expect(store.fileBytes('k2'), isNotNull); // حُفظت الكاملة أيضاً
    });

    test('الفشل يعلّم أحمر ولا يعاود؛ وعودة الاتصال تمنح فرصة جديدة', () async {
      final c = container();
      addTearDown(c.dispose);
      final store = c.read(xrayStoreProvider);
      final remote = FakeRemote()..failFetch = true;
      final r = XrayThumbRestorer(store: store, remote: remote);

      r.request('k3', online: true);
      await pumpEventQueue();
      expect(r.isFailed('k3'), isTrue);
      final calls = remote.fetchCalls;

      // أوفلاين: الفاشل يبقى فاشلاً — لا محاولة جديدة (حرفية الأصل).
      r.request('k3', online: false);
      await pumpEventQueue();
      expect(remote.fetchCalls, calls);
      expect(r.isFailed('k3'), isTrue);

      // عاد الاتصال: يُمحى من الفاشل ويعاد الجلب — وينجح هذه المرة.
      remote.failFetch = false;
      remote.thumbs['k3'] = _png(w: 20, h: 20);
      r.request('k3', online: true);
      await pumpEventQueue();
      expect(r.isFailed('k3'), isFalse);
      expect(store.thumbnailBytes('k3'), isNotNull);
    });
  });

  group('الوحدات — عزل العيادة (المرحلة H)', () {
    test('العلم مطفأ: الكل يظهر؛ مفعّل: الموسومة لعيادتها والقديمة للجميع', () {
      final cfg = <String, Object?>{
        'xrayMeta': {
          'a': {'clinic': 'ع1'},
          'b': {'clinic': 'ع2'},
          'c': {'name': 'قديمة'}, // غير موسومة
        },
      };
      final keys = ['a', 'b', 'c'];
      // م35 — قرار مالك v12: العزل مفعّل افتراضياً.
      expect(isolationFilteredKeys(cfg, keys, 'ع1'), ['a', 'c']);
      // إطفاء العلم يعيد سلوك الأصل الحرفي (الكل يظهر).
      syncFlags.clinicXrayIsolation = false;
      expect(isolationFilteredKeys(cfg, keys, 'ع1'), ['a', 'b', 'c']);
      syncFlags.clinicXrayIsolation = true;
      expect(isolationFilteredKeys(cfg, keys, 'ع1'), ['a', 'c']);
      expect(isolationFilteredKeys(cfg, keys, 'ع2'), ['b', 'c']);
      // بلا عيادة (فتح خارج سياقها): لا ترشيح.
      expect(isolationFilteredKeys(cfg, keys, ''), ['a', 'b', 'c']);
    });
  });

  group('الواجهة — قسم الأشعة التوأم', () {
    Future<void> boot(
      WidgetTester tester, {
      required XrayPick pick,
      XrayRemote? remote,
    }) async {
      final c = container();
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
            xrayFilePickProvider.overrideWithValue(pick),
            if (remote != null) r2ClientProvider.overrideWithValue(remote),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
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
      // م39 — ورقة المصدر: نختار «من الملفات» (المنتقي المحقون).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('xr-src-files')),
        findsOneWidget,
        reason: 'ورقة مصدر الصور لم تظهر',
      );
      await tester.tap(find.byKey(const Key('xr-src-files')));
      await settle(tester);
      await settle(tester);
      await settle(tester);
    }

    testWidgets(
      'أوفلاين: رسالة الطابور وشارة «بانتظار الرفع» والتاريخ العربي',
      (tester) async {
        final png = _png();
        await boot(tester, pick: () async => [('scan.png', png)]);
        await openXrays(tester);
        await uploadTap(tester);

        expect(
          find.text('تم حفظ الصور — سيتم رفعها تلقائياً عند الاتصال'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('xray-thumb-0')), findsOneWidget);
        // ترويسة العدد + زر الرفع المتقطع.
        expect(find.text('صور الأشعة (1)'), findsOneWidget);
        expect(find.text('إرفاق صور أشعة'), findsOneWidget);

        // العرض التفصيلي: الشارة والتاريخ العربي واسم الملف.
        await tester.tap(
          find.byKey(const Key('xray-seg-details')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.text('بانتظار الرفع'), findsOneWidget);
        expect(find.text('scan'), findsOneWidget);
        expect(
          find.textContaining(RegExp('[٠-٩]+ [^ ]+ [٠-٩]{4}')),
          findsOneWidget,
        );
        // التفضيل ذُكر في الإعدادات.
        final chk = container();
        addTearDown(chk.dispose);
        final cfg = Map<String, Object?>.from(
          chk.read(reposProvider).settings.get('app.config') as Map,
        );
        expect(cfg['xrayViewMode'], 'details');
        // الوسم بالعيادة دائم التفعيل (المرحلة H).
        final key = xrayKeysFor(cfg, 'هدى').single;
        expect(xrayMetaFor(cfg, key)['clinic'], 'ع1');
      },
    );

    testWidgets('أونلاين: تصريف فوري برسالة النجاح وشارة «مرفوعة»', (
      tester,
    ) async {
      final png = _png();
      final remote = FakeRemote();
      await boot(tester, pick: () async => [('scan.png', png)], remote: remote);
      await openXrays(tester);
      await uploadTap(tester);

      expect(find.text('تم رفع صور الأشعة بنجاح'), findsOneWidget);
      final chk = container();
      final row = chk.read(reposProvider).xrays.getByPatient('هدى').single;
      expect(row['upload_status'], 'uploaded');
      chk.dispose();
      expect(remote.store, isNotEmpty);

      await tester.tap(
        find.byKey(const Key('xray-seg-details')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('مرفوعة'), findsOneWidget);
      expect(find.text('بانتظار الرفع'), findsNothing);
    });

    testWidgets('التحديد المتعدد بالضغط المطوّل: شريط العدد وحذف جماعي واحد', (
      tester,
    ) async {
      final png = _png();
      await boot(tester, pick: () async => [('a.png', png), ('b.png', png)]);
      await openXrays(tester);
      await uploadTap(tester);
      expect(find.byKey(const Key('xray-thumb-1')), findsOneWidget);
      // تصريف سناك الرفع — كي لا يصطف سناك الحذف خلفه.
      await tester.pump(const Duration(seconds: 5));

      // ضغط مطوّل يدخل الوضع بصورة واحدة محددة.
      await tester.longPress(
        find.byKey(const Key('xray-thumb-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('1 محددة'), findsOneWidget);
      expect(find.byKey(const Key('xray-check-0')), findsOneWidget);

      // نقر الثانية يضيفها.
      await tester.tap(
        find.byKey(const Key('xray-thumb-1')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('2 محددة'), findsOneWidget);

      // مفاتيح قبل الحذف — للتحقق من الشواهد والطوابير.
      var chk = container();
      var cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      final keys = xrayKeysFor(cfg, 'هدى');
      expect(keys, hasLength(2));
      chk.dispose();

      await tester.tap(
        find.byKey(const Key('xray-ms-del')),
        warnIfMissed: false,
      );
      // م142 — الحذف مؤجَّل خلف نافذة تراجع 3ث: يظهر الشريط أولاً، ولم يُحذف
      // شيء بعد؛ ننتظر انقضاء المؤقت ثم نتحقق من الحذف الفعلي.
      await settle(tester);
      expect(find.text('سيُحذف بعد 3 ثوانٍ'), findsOneWidget);
      var probe = container();
      expect(
        xrayKeysFor(
          Map<String, Object?>.from(
            probe.read(reposProvider).settings.get('app.config') as Map,
          ),
          'هدى',
        ),
        hasLength(2),
        reason: 'لم يُحذف شيء قبل انقضاء المؤقت',
      );
      probe.dispose();
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.text('تم حذف 2 صورة'), findsOneWidget);
      expect(find.text('لا توجد صور أشعة'), findsOneWidget);

      chk = container();
      addTearDown(chk.dispose);
      cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      expect(xrayKeysFor(cfg, 'هدى'), isEmpty);
      final db = chk.read(localDbProvider);
      for (final k in keys) {
        expect(isXrayDeleted(db, k), isTrue); // حارس المحذوف
        expect(pendingDeletes(db), contains(k)); // طابور حذف R2
      }
    });

    testWidgets('إلغاء التحديد يخرج من الوضع وEnter يحفظ التسمية', (
      tester,
    ) async {
      final png = _png();
      await boot(tester, pick: () async => [('a.png', png)]);
      await openXrays(tester);
      await uploadTap(tester);
      // تصريف سناك الرفع — كي لا يصطف سناك التسمية خلفه.
      await tester.pump(const Duration(seconds: 5));

      await tester.longPress(
        find.byKey(const Key('xray-thumb-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('1 محددة'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('xray-ms-cancel')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('1 محددة'), findsNothing);
      expect(find.byKey(const Key('xray-check-0')), findsNothing);

      // التفصيلي: إعادة التسمية بـ Enter (onSubmitted).
      await tester.tap(
        find.byKey(const Key('xray-seg-details')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('xray-rename-btn-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('xray-rename')),
        'بانوراما سفلية',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('تم حفظ الاسم'), findsOneWidget);
      expect(find.text('بانوراما سفلية'), findsOneWidget);

      final chk = container();
      addTearDown(chk.dispose);
      final cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      final key = xrayKeysFor(cfg, 'هدى').single;
      expect(xrayMetaFor(cfg, key)['name'], 'بانوراما سفلية');
    });
  });
}
