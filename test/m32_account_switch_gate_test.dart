/// اختبارات م32 — علة «أهلاً بك مجدداً + الاسم القديم» عند تبديل الحساب:
/// ذاكرة الإعدادات المؤقتة (appConfigProvider) كانت تبقى على إعدادات
/// الحساب القديم بعد مسح التبديل (لا نبضة configRev بعد المسح) فترحّب
/// البوابة بالاسم القديم وتختم علم الإكمال للحساب الجديد خطأً.
/// الإصلاح: البوابة تقفز كل عدّادات النسخ عند أول إطار قبل أي حكم.
///
/// السيناريو الحرفي (داخل تطبيق حي واحد — الحاوية تعيش عبر خروج/دخول):
///   1) دخول أ (مُعَدّ محلياً «مركز أ») ⇒ الرئيسية.
///   2) تسجيل خروج ⇒ شاشة الدخول.
///   3) دخول ب:
///      • الخادم يحمل إعدادات ب («مركز ب») ⇒ ترحيب **باسم ب** — واسم أ
///        لا يظهر أبداً في أي إطار.
///      • خادم فارغ (ب جديد) ⇒ شاشة الإعداد الإجبارية — لا ترحيب باسم أ
///        ولا دخول للرئيسية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'staff_test_session.dart' show staffAdminSession;

/// جهاز بذر «تطبيق الأصل» لحساب ب — يدفع إعداداته للخادم (توأم م17).
class SeederDevice {
  SeederDevice(FakeSyncServer server)
    : tmp = Directory.systemTemp.createTempSync('m32_seed_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine = SyncEngine(SyncContext(db: db, repos: repos, transport: server));
  }

  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncEngine engine;

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  late Directory tmp;
  late FakeSyncServer server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m32_dev_');
    server = FakeSyncServer();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// تجهيز جهاز التطبيق: حسابا أ وب مسجلان، وأ داخل ومُعَدّ محلياً.
  Future<void> seedDeviceWithAccountA() async {
    final c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = c.read(authServiceProvider);
    await auth.register('a@clinic.ly', 'secret12');
    await auth.register('b@clinic.ly', 'secret12');
    // الدخول عبر المتحكم نفسه (يسجل آخر uid = أ كما في التطبيق الحي).
    await c.read(authProvider.notifier).login('a@clinic.ly', 'secret12', true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز أ',
      'clinics': ['عيادة أ'],
    });
    c.dispose();
  }

  /// ضخ حتى نهاية الترحيب (300 + 2800 + 500 وهامش).
  Future<void> pumpThroughWelcome(
    WidgetTester tester, {
    bool forbidText = true,
  }) async {
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      if (forbidText) {
        // الاسم القديم لا يظهر في **أي إطار** — جوهر العلة.
        expect(
          find.text('مركز أ'),
          findsNothing,
          reason: 'اسم الحساب القديم ظهر بعد تبديل الحساب',
        );
      }
    }
  }

  testWidgets('تبديل الحساب: الخادم يحمل إعدادات ب ⇒ ترحيب باسم ب لا باسم أ', (
    tester,
  ) async {
    // «أصل» حساب ب يدفع إعداداته للخادم.
    final seeder = SeederDevice(server);
    addTearDown(seeder.dispose);
    seeder.repos.settings.set('app.config', {
      'centerName': 'مركز ب',
      'clinics': ['عيادة ب'],
    });
    await seeder.engine.syncNow();

    await seedDeviceWithAccountA();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          transportProvider.overrideWithValue(server),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // استعادة جلسة أ المكتملة ⇒ الرئيسية مباشرة (بلا ترحيب متكرر).
    expect(find.byType(AppShellScreen), findsOneWidget);

    // خروج ثم دخول ب — داخل الحاوية الحية نفسها (جوهر الاستنساخ).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShellScreen)),
    );
    await container.read(authProvider.notifier).logout();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await container
        .read(authProvider.notifier)
        .login('b@clinic.ly', 'secret12', true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // البوابة تسحب إعدادات ب ثم ترحب — اسم أ ممنوع في كل الإطارات.
    expect(
      find.text('مركز أ'),
      findsNothing,
      reason: 'العلة الأصلية: ترحيب باسم الحساب القديم',
    );
    await pumpThroughWelcome(tester);

    // الترحيب/الرئيسية باسم ب.
    expect(find.text('مركز ب'), findsWidgets);
    expect(find.byType(AppShellScreen), findsOneWidget);
  });

  testWidgets(
    'تبديل الحساب: ب جديد (خادم فارغ) ⇒ شاشة الإعداد الإجبارية لا ترحيب',
    (tester) async {
      await seedDeviceWithAccountA();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
            transportProvider.overrideWithValue(server),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AppShellScreen), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShellScreen)),
      );
      await container.read(authProvider.notifier).logout();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await container
          .read(authProvider.notifier)
          .login('b@clinic.ly', 'secret12', true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // لا اسم قديم، ولا رئيسية — بل شاشة الإعداد الإجبارية لحساب جديد.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('مركز أ'), findsNothing);
      }
      expect(
        find.text('مرحباً بك'),
        findsOneWidget,
        reason: 'حساب جديد ⇒ الإعداد الإجباري (كان يتخطاه بعلم مختوم خطأً)',
      );
      expect(find.byKey(const Key('gate-submit')), findsOneWidget);
      expect(find.byType(AppShellScreen), findsNothing);
    },
  );
}
