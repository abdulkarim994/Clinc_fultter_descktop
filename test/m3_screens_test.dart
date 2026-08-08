/// اختبارات م3 — الشاشات الأساسية فوق الطبقات المنقولة:
/// تدفق الدخول الكامل، تبويب المرضى (بحث FTS حي + إضافة)، ولوحة الدور
/// (إضافة سريعة، ترقيم، أرشفة بتم الدخول، تخطٍّ) مع تحقق أن كل كتابة
/// واجهة تدخل طابور المزامنة (dirty) فعلاً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/login/login_screen.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

Widget appWith(String dir) => ProviderScope(
  overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(dir)],
  child: const DentalApp(),
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 350)); // دخول السناك بار
}

Future<void> tapSeen(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, warnIfMissed: false);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('m3_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('تدفق الدخول', () {
    testWidgets('جلسة غائبة ⇒ شاشة الدخول؛ تسجيل ثم دخول ⇒ الصدفة', (
      tester,
    ) async {
      await tester.pumpWidget(appWith(tmp.path));
      await settle(tester);

      // شاشة الدخول ظاهرة
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsWidgets);

      // دخول بلا حساب ⇒ رسالة الخطأ العربية
      await tester.enterText(find.byType(TextField).at(0), 'doc@clinic.ly');
      await tester.enterText(find.byType(TextField).at(1), 'secret12');
      await tester.tap(find.text('تسجيل الدخول').last);
      await settle(tester);
      expect(find.textContaining('لا يوجد حساب'), findsOneWidget);

      // إنشاء حساب
      await tapSeen(tester, find.text('إنشاء حساب جديد').first);
      await settle(tester);
      final fields = find.byType(TextField);
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), 'doc@clinic.ly');
      await tester.enterText(fields.at(3), 'secret12');
      await tapSeen(tester, find.text('إنشاء الحساب'));
      await settle(tester);
      expect(find.textContaining('تم إنشاء الحساب'), findsOneWidget);

      // دخول ناجح لحساب جديد ⇒ بوابة الإعداد الإجبارية (م31) لا الصدفة.
      await tapSeen(tester, find.text('تسجيل الدخول').last);
      await settle(tester);
      expect(find.text('مرحباً بك'), findsOneWidget);
      expect(find.byKey(const Key('gate-submit')), findsOneWidget);

      // إكمال الإعداد الإلزامي: اسم المركز + عيادة واحدة ثم بدء التجهيز.
      await tester.enterText(
        find.byKey(const Key('gate-center-name')),
        'مركز النور',
      );
      await tester.enterText(
        find.byKey(const Key('gate-clinic-0')),
        'العيادة 1',
      );
      await tapSeen(tester, find.byKey(const Key('gate-submit')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }

      // بعد التجهيز ⇒ الصدفة بتبويباتها الخمسة.
      expect(find.byType(AppShellScreen), findsOneWidget);
      for (final label in [
        'الرئيسية',
        'السجلات',
        'المالية',
        'إضافي',
        'الحجوزات',
      ]) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('التحقق: بريد سيّئ وكلمة قصيرة يعرضان الرسائل نفسها', (
      tester,
    ) async {
      await tester.pumpWidget(appWith(tmp.path));
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'ليس بريداً');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.tap(find.text('تسجيل الدخول').last);
      await settle(tester);
      expect(find.text('يرجى إدخال بريد إلكتروني صحيح'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'doc@clinic.ly');
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.tap(find.text('تسجيل الدخول').last);
      await settle(tester);
      // م68 — رُفع الحد الأدنى من ستة إلى ثمانية محارف.
      expect(
        find.text('كلمة المرور يجب أن تكون 8 أحرف على الأقل'),
        findsOneWidget,
      );
    });
  });

  group('الصدفة والمرضى (جلسة مسبقة)', () {
    late ProviderContainer seedContainer;

    Future<void> seedSessionAndData(String dir) async {
      // نبذر الحساب والجلسة والبيانات عبر نفس الطبقات (بلا واجهة).
      seedContainer = ProviderContainer(
        overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(dir)],
      );
      final auth = seedContainer.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      final repos = seedContainer.read(reposProvider);
      repos.settings.set('app.config', {
        'centerName': 'مركز الزهراء',
        'clinics': ['عيادة 1', 'عيادة 2'],
      });
      // خريطة المرضى تُشتق من السجلات (patientMap) — نبذر قيوداً فعلية.
      repos.records.bulkUpsert([
        {
          'id': 'r1',
          'name': 'أحمد الطيّب',
          'patient_name': 'أحمد الطيّب',
          'phone': '0911111111',
          'clinic': 'عيادة 1',
          'date': '2026-07-20',
          'amount': 100,
          'service': 'حشو',
          'payment': 'كاش',
        },
        {
          'id': 'r2',
          'name': 'خالد المهدي',
          'patient_name': 'خالد المهدي',
          'phone': '0922222222',
          'clinic': 'عيادة 1',
          'date': '2026-07-22',
          'amount': 50,
          'service': 'كشف',
          'payment': 'كاش',
        },
        {
          'id': 'r3',
          'name': 'احمد سالم',
          'patient_name': 'احمد سالم',
          'phone': '0933333333',
          'clinic': 'عيادة 2',
          'date': '2026-07-25',
          'amount': 80,
          'service': 'حشو',
          'payment': 'كاش',
        },
      ]);
      seedContainer.dispose(); // يغلق القاعدة ليعيد التطبيق فتحها
    }

    testWidgets('الهيدر باسم المركز + تبويب السجلات يعرض ويبحث بالعربية', (
      tester,
    ) async {
      await seedSessionAndData(tmp.path);
      await tester.pumpWidget(appWith(tmp.path));
      await settle(tester);

      expect(find.byType(AppShellScreen), findsOneWidget);
      expect(find.text('مركز الزهراء'), findsOneWidget);

      // م36 — الافتراضي صار «الرئيسية»: نفتح السجلات ثم بوابة العيادات.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('clinic-card-عيادة 1')), findsOneWidget);
      expect(find.byKey(const Key('clinic-card-عيادة 2')), findsOneWidget);

      // بحث مطبّع: «أَحْمَد» بالتشكيل يجد الاثنين بهمزة وبدونها
      await tester.enterText(
        find.byKey(const Key('patient-search')),
        'أَحْمَد',
      );
      await settle(tester);
      expect(find.text('أحمد الطيّب'), findsOneWidget);
      expect(find.text('احمد سالم'), findsOneWidget);
      expect(find.text('خالد المهدي'), findsNothing);
    });

    testWidgets('زر المزامنة يدفع البيانات للناقل المحلي ويصفّر المعلّق', (
      tester,
    ) async {
      await seedSessionAndData(tmp.path);
      await tester.pumpWidget(appWith(tmp.path));
      await settle(tester);

      await tester.tap(find.byTooltip('مزامنة'));
      await settle(tester);
      await settle(tester);

      // كل ما بُذر بـ set/bulkUpsert من الواجهة الخلفية دُفع وأُقرّ
      final container = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(container.dispose);
      // ملاحظة: bulkUpsert البذر ليس dirty (server-origin)؛ الإعداد dirty.
      // بعد المزامنة اليدوية يجب ألا يبقى شيء معلقاً على الإطلاق.
      final engine = container.read(syncEngineProvider);
      expect(engine.getEngineStatus().pending, 0);
    });
  });

  group('نظام الدور', () {
    Future<void> openQueue(WidgetTester tester, String dir) async {
      final c = ProviderContainer(
        overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(dir)],
      );
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الزهراء',
        'clinics': ['عيادة 1'],
        'bookingSystem': 'queue', // نظام الدور (الافتراضي التقليدي)
      });
      c.dispose();

      await tester.pumpWidget(appWith(dir));
      await settle(tester);
      await tapSeen(tester, find.text('الحجوزات'));
      await settle(tester);
    }

    testWidgets(
      'إضافة سريعة لمريضين ⇒ ترقيم 1،2؛ تم الدخول يؤرشف؛ التخطي يبدّل',
      (tester) async {
        await openQueue(tester, tmp.path);

        // اختيار العيادة
        await tapSeen(tester, find.byKey(const Key('clinic-عيادة 1')));
        await settle(tester);
        expect(find.text('قائمة الانتظار فارغة.'), findsOneWidget);

        // إضافة سريعة تبقى مفتوحة
        await tapSeen(tester, find.byKey(const Key('queue-add-toggle')));
        await settle(tester);
        await tester.enterText(find.byKey(const Key('queue-add-name')), 'سالم');
        await tapSeen(tester, find.byKey(const Key('queue-add-go')));
        await settle(tester);
        await tester.enterText(find.byKey(const Key('queue-add-name')), 'مريم');
        await tapSeen(tester, find.byKey(const Key('queue-add-go')));
        await settle(tester);
        // م56 — أغلق لوحة الإضافة لتحرير مساحة القائمة (نافذة ٦٠٠ بكسل):
        // القائمة كسولة فتبني البطاقتين معاً بعد الإغلاق.
        await tapSeen(tester, find.byKey(const Key('queue-add-toggle')));
        await settle(tester);

        // v62 — «سالم» الأول يظهر مرتين: لوحة «التالي» البطلة + صفه.
        expect(find.text('سالم'), findsNWidgets(2));
        expect(find.byKey(const Key('hero-name')), findsOneWidget);
        expect(find.byKey(const Key('hero-admit')), findsOneWidget);
        expect(find.text('مريم'), findsOneWidget);
        expect(find.text('صباح (2)'), findsOneWidget);

        // كتابات الواجهة دخلت طابور المزامنة فعلاً
        final c = ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );
        addTearDown(c.dispose);
        final dirty = c
            .read(localDbProvider)
            .query('SELECT COUNT(*) AS n FROM queue_patients WHERE _dirty = 1');
        expect(dirty.first['n'], 2);

        // «تم الدخول» للأول ⇒ الأرشيف (1) والمتبقي 1
        final rows = c
            .read(reposProvider)
            .queue
            .getByClinicDate(
              'عيادة 1',
              c.read(reposProvider).queue.getAll().first['date'] as String,
            );
        final salem = rows.firstWhere((r) => r['patient_name'] == 'سالم');
        await tapSeen(tester, find.byKey(Key('admit-${salem['id']}')));
        await settle(tester);
        expect(find.text('صباح (1)'), findsOneWidget);
        expect(find.text('الأرشيف (1)'), findsOneWidget);

        // الأرشيف يعرض سالم برقم أرشيف 1
        await tapSeen(tester, find.byKey(const Key('period-archive')));
        await settle(tester);
        expect(find.text('سالم'), findsOneWidget);

        // عودة للانتظار ثم رجوع لاختيار العيادة
        await tapSeen(tester, find.byKey(const Key('period-morning')));
        await settle(tester);
        await tapSeen(tester, find.byKey(const Key('queue-back')));
        await settle(tester);
        expect(find.text('اختر العيادة'), findsOneWidget);
        expect(find.textContaining('في الانتظار اليوم'), findsOneWidget);
      },
    );
  });
}
