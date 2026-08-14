/// اختبارات م17 — إسقاط المزامنة على الواجهة (علة «الإعدادات ما طلعت»):
/// أول سحب سحابي كان يدمج إعدادات الحساب وبياناته في القاعدة ثم لا يخطر
/// أحداً — projectionListeners بلا مشترك — فتبقى الواجهة على لقطة الإقلاع
/// الفارغة حتى إعادة التشغيل. الإصلاح: مصنع المحرك يوصل مستمعاً يقفز
/// عدّادات النسخ كلها (إعدادات/سجلات/مالية/حجوزات/دور/أشعة) عند كل دمج.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/features/finance/finance_screen.dart'
    show financeRevProvider;
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show patientsRevProvider;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'staff_test_session.dart' show staffAdminSession;

/// جهاز بذر: يمثل «تطبيق الأصل» الذي كتب إعدادات الحساب وبياناته للخادم.
class SeederDevice {
  SeederDevice(FakeSyncServer server)
    : tmp = Directory.systemTemp.createTempSync('m17_seed_') {
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

const seededConfig = <String, Object?>{
  'centerName': 'عيادة السحابة',
  'doctorPct': 45,
  'clinics': ['الصفوة السحابية', 'فرع الظهرة'],
  'services': ['حشو سحابي', 'تنظيف'],
  'payments': ['كاش', 'بطاقة'],
};

void main() {
  late FakeSyncServer server;
  late SeederDevice seeder;
  late Directory tmp;

  setUp(() async {
    server = FakeSyncServer();
    seeder = SeederDevice(server);
    tmp = Directory.systemTemp.createTempSync('m17_dev_');
    // «الأصل» يكتب إعدادات الحساب + مريضاً وسجلاً ثم يدفعها للخادم.
    seeder.repos.settings.set('app.config', seededConfig);
    seeder.repos.patients.upsertLocal({
      'id': 'p1',
      'name': 'أحمد السحابي',
      'clinic': 'الصفوة السحابية',
    });
    seeder.repos.records.upsertLocal({
      'id': 'r1',
      'name': 'أحمد السحابي',
      'patient_name': 'أحمد السحابي',
      'date': '2026-07-20',
      'amount': 250,
      'clinic': 'الصفوة السحابية',
      'service': 'حشو سحابي',
      'payment': 'كاش',
      '_t': 'r',
    });
    final r = await seeder.engine.runCycle('seed');
    expect(r.status, 'ok');
    expect(r.pushed, greaterThanOrEqualTo(3));
  });

  tearDown(() {
    seeder.dispose();
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer freshDevice() => ProviderContainer(
    overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
      transportProvider.overrideWithValue(server),
    ],
  );

  group('الوحدات — دمج السحب يقفز عدّادات النسخ', () {
    test('أول مزامنة تسحب إعدادات الحساب وتحدّث الإسقاطات فوراً', () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      // قبل: لا إعدادات — الافتراضات الفارغة (شكوى المستخدم حرفياً).
      expect(c.read(appConfigProvider), isEmpty);
      // م180/٦ — الاسم البديل صار DENTSHINE.
      expect(c.read(centerNameProvider), 'DENTSHINE');
      final cfg0 = c.read(configRevProvider);
      final pat0 = c.read(patientsRevProvider);
      final fin0 = c.read(financeRevProvider);

      final engine = c.read(syncEngineProvider);
      final r = await engine.syncNow();
      expect(r.ok, isTrue);
      expect(r.merged, greaterThanOrEqualTo(3));

      // بعد: العدّادات قفزت والإسقاطات تعكس إعدادات الحساب بلا إعادة تشغيل.
      expect(c.read(configRevProvider), greaterThan(cfg0));
      expect(c.read(patientsRevProvider), greaterThan(pat0));
      expect(c.read(financeRevProvider), greaterThan(fin0));
      final cfg = c.read(appConfigProvider);
      expect(cfg['centerName'], 'عيادة السحابة');
      expect(cfg['clinics'], ['الصفوة السحابية', 'فرع الظهرة']);
      expect(c.read(centerNameProvider), 'عيادة السحابة');
      // البيانات وصلت أيضاً.
      expect(c.read(reposProvider).records.getAll(), hasLength(1));
    });

    test('دورة بلا دمج جديد لا تقفز العدّادات (لا وميض عبثي)', () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      final engine = c.read(syncEngineProvider);
      await engine.syncNow();
      final cfgAfterFirst = c.read(configRevProvider);
      final r2 = await engine.syncNow();
      expect(r2.merged, 0);
      expect(c.read(configRevProvider), cfgAfterFirst);
    });
  });

  group('الواجهة — سيناريو المستخدم: دخول على جهاز جديد ⇒ البوابة تُنزل '
      'إعدادات الحساب تلقائياً', () {
    testWidgets(
      'بوابة ما بعد الدخول تسحب إعدادات الحساب ثم ترحيب ثم الرئيسية بالاسم',
      (tester) async {
        // تحضير جلسة محفوظة على جهاز جديد فارغ.
        final c = freshDevice();
        final auth = c.read(authServiceProvider);
        await auth.register('doc@clinic.ly', 'secret12');
        await auth.login('doc@clinic.ly', 'secret12', remember: true);
        c.dispose();

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
        await tester.pump(const Duration(milliseconds: 150));

        // م31 — الجهاز الفارغ غير مُعَدّ محلياً: البوابة (لا الرئيسية) تظهر
        // وتسحب إعدادات الحساب من الخادم قبل الحكم — الهيدر الافتراضي «ما
        // يطلع» لأن الرئيسية محجوبة خلف البوابة (هذا جوهر الإصلاح).
        expect(find.text('DENTSHINE'), findsNothing);

        // البوابة: loading → سحب → (مُعَدّ عبر الخادم) → ترحيب → الرئيسية.
        // ننتظر السحب + الترحيب (300ms ظهور + 2800ms قراءة + 500ms تلاشٍ).
        for (var i = 0; i < 14; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }

        // بعد اكتمال البوابة: الرئيسية بالاسم السحابي والإعدادات في القاعدة.
        expect(find.text('عيادة السحابة'), findsWidgets);
        final chk = ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );
        addTearDown(chk.dispose);
        final cfg = chk.read(reposProvider).settings.get('app.config');
        expect((cfg as Map)['clinics'], ['الصفوة السحابية', 'فرع الظهرة']);
      },
    );
  });
}
