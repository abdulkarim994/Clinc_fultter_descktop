/// اختبارات م26 — أيقونة المعلقات ونافذة «صور بانتظار الرفع»
/// (توأم زر AppShell + PendingUploadsPopup):
///   • الأيقونة بجانب زر المزامنة تظهر فقط عند وجود معلقات وبشارة العدد،
///     ونقرها يفتح النافذة.
///   • النافذة: العدّاد والعناصر (اسم المريض/الملف) والحذف الفردي
///     و«حذف الكل» بتأكيد وحالة «لا توجد صور معلقة».
///   • «رفع الكل» يرفع عنصراً-عنصراً عبر reconcileOne (خط أنابيب حي
///     مزيف) ويصفّر القائمة.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/features/xrays/pending_uploads_dialog.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

/// بعيد ناجح دوماً (الرفع يعيد المفتاح نفسه؛ لا تحقق checksum).
class OkRemote implements XrayRemote {
  int uploads = 0;

  @override
  Future<String> upload(
    Uint8List bytes,
    String key, {
    String patientName = '',
    String fileName = '',
    String contentType = 'image/jpeg',
  }) async {
    uploads++;
    return key;
  }

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async => null;

  @override
  Future<R2HeadResult> headObject(String key) async =>
      const R2HeadResult(ok: true);

  @override
  Future<void> delete(String key) async {}
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('m26_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> seedApp(
    WidgetTester tester, {
    int pending = 2,
    XrayRemote? remote,
  }) async {
    final seed = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    // حساب مُعَدّ (اسم مركز + عيادة) كي تعبر بوابة الإعداد إلى الرئيسية.
    seed.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
    });
    final store = seed.read(xrayStoreProvider);
    for (var i = 0; i < pending; i++) {
      final id = 'xr/pending_$i.jpg';
      store.repos.xrays.upsertLocal({
        'id': id,
        'patient_name': 'مريض $i',
        'file_key': id,
        'upload_status': 'pending',
        'created_at': '2026-07-27T10:0$i:00.000Z',
      });
      store.writeFileBytes(id, Uint8List.fromList(List.filled(64, i)));
    }
    seed.dispose();

    final overrides = [
      // م133 — م118: الصدفة تُحجب بشاشة دخول الموظفين بلا هذا التجاوز
      // (كان محذوفاً هنا سهواً فتبقى الأيقونة غائبة خلف شاشة الدخول).
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
      if (remote != null)
        xrayPipelineProvider.overrideWith(
          (ref) => XrayPipeline(
            db: ref.watch(localDbProvider),
            repos: ref.watch(reposProvider),
            store: ref.watch(xrayStoreProvider),
            remote: remote,
            verifyChecksum: false,
          ),
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const DentalApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    return ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('الأيقونة بشارة العدد تظهر وتفتح النافذة بعناصرها', (
    tester,
  ) async {
    final chk = await seedApp(tester, pending: 2);
    addTearDown(chk.dispose);

    expect(
      find.byKey(const Key('pending-uploads-icon')),
      findsOneWidget,
      reason: 'أيقونة بجانب زر المزامنة عند وجود معلقات',
    );
    expect(find.text('2'), findsWidgets); // شارة العدد

    await tester.tap(find.byKey(const Key('pending-uploads-icon')));
    await settle(tester);

    expect(find.text('صور بانتظار الرفع'), findsOneWidget);
    expect(find.byKey(const Key('pu-count')), findsOneWidget);
    expect(find.textContaining('مريض 0'), findsOneWidget);
    expect(find.textContaining('مريض 1'), findsOneWidget);
    expect(find.byKey(const Key('pu-sync-all')), findsOneWidget);
    expect(find.byKey(const Key('pu-delete-all')), findsOneWidget);
  });

  testWidgets('حذف فردي ثم حذف الكل بتأكيد ⇒ حالة فارغة وأيقونة تختفي', (
    tester,
  ) async {
    final chk = await seedApp(tester, pending: 2);
    addTearDown(chk.dispose);
    await tester.tap(find.byKey(const Key('pending-uploads-icon')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('pu-item-del-0')));
    await settle(tester);
    expect(chk.read(reposProvider).xrays.getPendingUploads(), hasLength(1));

    await tester.tap(find.byKey(const Key('pu-delete-all')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('pu-delete-all-confirm')));
    await settle(tester);

    expect(find.text('لا توجد صور معلقة'), findsOneWidget);
    expect(chk.read(reposProvider).xrays.getPendingUploads(), isEmpty);

    // إغلاق النافذة — الأيقونة زالت من الهيدر (لا معلقات).
    await tester.tap(find.byKey(const Key('pu-close')));
    await settle(tester);
    expect(find.byKey(const Key('pending-uploads-icon')), findsNothing);
  });

  testWidgets('«رفع الكل» يرفع الجميع عبر خط أنابيب حي ويصفّر القائمة', (
    tester,
  ) async {
    final remote = OkRemote();
    final chk = await seedApp(tester, pending: 2, remote: remote);
    addTearDown(chk.dispose);

    await tester.tap(find.byKey(const Key('pending-uploads-icon')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('pu-sync-all')));
    await settle(tester);
    await settle(tester);

    expect(remote.uploads, 2);
    expect(chk.read(reposProvider).xrays.getPendingUploads(), isEmpty);
    expect(find.text('لا توجد صور معلقة'), findsOneWidget);
  });

  testWidgets('نافذة مفتوحة مباشرة بلا معلقات تعرض الحالة الفارغة', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const MaterialApp(home: Scaffold(body: PendingUploadsDialog())),
      ),
    );
    await settle(tester);
    expect(find.text('لا توجد صور معلقة'), findsOneWidget);
    expect(find.byKey(const Key('pu-sync-all')), findsNothing);
  });
}
