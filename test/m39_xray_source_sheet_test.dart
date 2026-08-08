/// اختبارات م39 — مصدر صور الأشعة: ورقة سفلية بخيارين (المعرض/الملفات)
/// توأم خيارات النظام في الأصل (input type=file) — ومسار «المعرض»
/// بمزود قابل للحقن يوصل الصورة للمعرض المحلي.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_section.dart'
    show xrayGalleryPickProvider, xrayFilePickProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

/// صورة PNG صالحة للفك (نفس مولّد م15).
Uint8List _png({int w = 60, int h = 40}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(30, 100, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m39_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('ورقة الخيارين تظهر ومسار المعرض يوصل الصورة للمعرض', (
    tester,
  ) async {
    var galleryCalls = 0;
    final seed = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = seed.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'ع1',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
    });
    seed.dispose();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          xrayGalleryPickProvider.overrideWithValue(() async {
            galleryCalls++;
            return [('gallery.png', _png())];
          }),
          xrayFilePickProvider.overrideWithValue(() async => const []),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // إلى ملف المريض ← قسم الأشعة.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.byKey(const Key('psec-xrays')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('psec-xrays')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.byKey(const Key('xray-upload')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // نقرة الرفع ⇒ ورقة الخيارين.
    await tester.tap(find.byKey(const Key('xray-upload')), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('xr-src-gallery')), findsOneWidget);
    expect(find.byKey(const Key('xr-src-files')), findsOneWidget);
    expect(find.text('من المعرض'), findsOneWidget);
    expect(find.text('من الملفات'), findsOneWidget);

    // اختيار المعرض ⇒ المزود المحقون يُستدعى والصورة تدخل المعرض.
    await tester.tap(find.byKey(const Key('xr-src-gallery')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(galleryCalls, 1);
    final chk = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    addTearDown(chk.dispose);
    expect(
      chk.read(reposProvider).xrays.getByPatient('سالم'),
      isNotEmpty,
      reason: 'صورة المعرض دخلت معرض المريض',
    );
  });
}
