/// اختبارات شاشات سطح المكتب: التركيبات (المختبر) + الإضافي + المصروفات.
///
///  يتبع نمط [desktop_shell_smoke_test.dart]: تقليع بجلسة إدارة + قاعدة بيانات
///  مؤقتة + فرض واجهة سطح المكتب + حجم شاشة 1600×1000.
///
///  تبويب المختبر أُعيد تصميمه كنمط شاشة الديون (Master/Detail): يمين قائمة
///  المختبرات المجمّعة بعدّادات، يسار جدول [DesktopDataTable] لحالات المختبر
///  المحدَّد بذيل المجاميع الستة. الاختبارات تغطّي:
///  1. تبويب «إضافي»: بطاقة المختبر ظاهرة، نقرها يعرض الشاشة المنقسمة (حالة
///     فارغة «اختر مختبراً»).
///  2. تبويب «المصروفات»: يفتح بلا أخطاء.
///  3. قائمة المختبرات بعدّاداتها (نشطة/غير مدفوعة/مستحق) + النقر يفتح جدول
///     حالات المختبر + المجاميع صحيحة + النقر المزدوج يفتح تفاصيل الحالة +
///     زر الطباعة موجود.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_shell.dart';
import 'package:dental_clinic_flutter/features/desktop/screens/labs_desktop.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_labs_'));

  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  // ── دالة الإقلاع المشتركة ──────────────────────────────────────────────────

  Future<void> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    // ضبط الإعدادات: مختبر واحد للاختبار.
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
      'labs': ['مختبر الاختبار'],
    });
    c.dispose();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// إقلاع بحالات مزروعة مسبقاً (تركيبات + دين) عبر [seed] قبل بناء الواجهة.
  Future<void> bootSeeded(
    WidgetTester tester,
    void Function(dynamic repos) seed, {
    List<String> labs = const ['مختبر الاختبار'],
  }) async {
    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
      'labs': labs,
    });
    seed(repos);
    c.dispose();

    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// الانتقال لتبويب «إضافي» ثم فتح شاشة التركيبات المنقسمة.
  Future<void> openLabs(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('desk-tab-extra')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('extra-labs')));
    await tester.pump(const Duration(milliseconds: 200));
  }

  // ── الاختبار 1: تبويب «إضافي» — بطاقة المختبر ظاهرة ────────────────────

  testWidgets('تبويب إضافي: بطاقة المختبر ظاهرة وتفتح شاشة التركيبات',
      (tester) async {
    await boot(tester);

    // التحقق من DesktopShell أولاً.
    expect(find.byType(DesktopShell), findsOneWidget,
        reason: 'يجب أن تظهر صدفة سطح المكتب');

    // الانتقال لتبويب «إضافي».
    await tester.tap(find.byKey(const Key('desk-tab-extra')));
    await tester.pump(const Duration(milliseconds: 300));

    // بطاقة المختبر ظاهرة.
    expect(find.byKey(const Key('extra-labs')), findsOneWidget,
        reason: 'بطاقة المختبر يجب أن تظهر في تبويب إضافي');

    // بطاقة المصروفات ظاهرة (مع وسم الانتقال).
    expect(find.byKey(const Key('extra-expenses')), findsOneWidget,
        reason: 'بطاقة المصروفات يجب أن تظهر في تبويب إضافي');

    // نقر بطاقة المختبر يعرض شاشة التركيبات داخل التبويب.
    await tester.tap(find.byKey(const Key('extra-labs')));
    await tester.pump(const Duration(milliseconds: 200));

    // يجب أن تظهر شاشة التركيبات المنقسمة.
    expect(find.byType(DesktopLabsScreen), findsOneWidget,
        reason: 'شاشة التركيبات المنقسمة يجب أن تظهر بعد نقر بطاقة المختبر');

    // حالة الاختيار الفارغة ظاهرة («اختر مختبراً لعرض حالاته»).
    expect(find.text('اختر مختبراً لعرض حالاته'), findsOneWidget,
        reason: 'رسالة الاختيار الفارغة يجب أن تظهر في القسم الأيسر');

    // قائمة المختبرات ظاهرة برأسها وحقل بحثها.
    expect(find.byKey(const Key('labs-desk-search')), findsOneWidget,
        reason: 'حقل بحث المختبرات يجب أن يظهر');
    // م161 — العنوان صار يتضمن الشهر المختار.
    expect(find.textContaining('المختبرات'), findsWidgets,
        reason: 'رأس قائمة المختبرات يجب أن يظهر');

    // زر الرجوع لقائمة الأدوات ظاهر.
    expect(find.byKey(const Key('extra-labs-back')), findsOneWidget,
        reason: 'زر الرجوع يجب أن يظهر أعلى شاشة التركيبات');

    // نقر الرجوع يعيد لقائمة الأدوات.
    await tester.tap(find.byKey(const Key('extra-labs-back')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('extra-labs')), findsOneWidget,
        reason: 'يجب العودة لقائمة الأدوات بعد الرجوع');
  });

  // ── الاختبار 2: تبويب «المصروفات» يفتح بلا أخطاء ────────────────────────

  testWidgets('تبويب المصروفات يفتح ويعرض الإجمالي بلا أخطاء',
      (tester) async {
    await boot(tester);

    // الانتقال لتبويب «المصروفات».
    await tester.tap(find.byKey(const Key('desk-tab-expenses')));
    await tester.pump(const Duration(milliseconds: 300));

    // الصدفة لا تزال ظاهرة (لا صفحات مستقلة).
    expect(find.byType(DesktopShell), findsOneWidget,
        reason: 'الصدفة يجب أن تبقى بعد فتح تبويب المصروفات');

    // مفتاح إجمالي المصروفات ظاهر.
    expect(find.byKey(const Key('expenses-total')), findsOneWidget,
        reason: 'مفتاح إجمالي المصروفات يجب أن يظهر');

    // التحقق من ظهور تبويبات الأقسام.
    expect(find.text('الرواتب'), findsWidgets,
        reason: 'تبويب الرواتب يجب أن يظهر في شاشة المصروفات');

    // أزرار الطباعة ظاهرة.
    expect(find.byKey(const Key('expenses-print-month')), findsOneWidget,
        reason: 'زر طباعة مصروفات الشهر يجب أن يظهر');
    expect(find.byKey(const Key('expenses-print-today')), findsOneWidget,
        reason: 'زر طباعة استهلاك اليوم يجب أن يظهر');
  });

  // ── الاختبار 3: قائمة المختبرات بعدّاداتها + جدول الحالات + المجاميع ─────
  //
  //  زرع مختبرين: «مخبر النور» بحالتين (محصّلة 200 + دين 300) و«مخبر آخر»
  //  بلا حالات. نتحقق: صف المختبر بعدّاداته، النقر يفتح جدول الحالات، ذيل
  //  المجاميع (المحصّل/الديون/الصافي)، والنقر المزدوج يفتح تفاصيل الحالة.

  testWidgets('قائمة المختبرات بعدّاداتها وجدول الحالات ومجاميعها',
      (tester) async {
    await bootSeeded(
      tester,
      (repos) {
        // حالة محصّلة (كاش): قيمة 200.
        repos.prosthetics.upsertLocal({
          'id': 'p-cash',
          'name': 'أحمد المحصّل',
          'clinic': 'ع1',
          'date': '2026-08-01',
          'labName': 'مخبر النور',
          'prosType': 'تاج',
          'prosUnits': 1,
          'labValue': 200,
        });
        // حالة دين: قيمة 300، مرتبطة بدين نشط.
        repos.prosthetics.upsertLocal({
          'id': 'p-debt',
          'name': 'سالم المدين',
          'clinic': 'ع1',
          'date': '2026-08-05',
          'labName': 'مخبر النور',
          'prosType': 'زيركون',
          'prosUnits': 2,
          'labValue': 300,
          'isDebt': true,
        });
        repos.debts.upsertLocal({
          'id': 'd-debt',
          'prostheticId': 'p-debt',
          'name': 'سالم المدين',
          'clinic': 'ع1',
          'date': '2026-08-05',
          'status': 'active',
          'total': 300,
          'remaining': 300,
          'labPaid': 0,
        });
      },
      labs: ['مخبر النور', 'مخبر آخر'],
    );

    await openLabs(tester);
    expect(find.byType(DesktopLabsScreen), findsOneWidget);

    // ① عدّاد القائمة يعرض مختبرين.
    expect(find.byKey(const Key('labs-desk-count')), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'عدّاد المختبرات = 2');

    // ② صفّا المختبرين ظاهران.
    expect(find.byKey(const Key('labs-desk-tile-مخبر النور')),
        findsOneWidget);
    expect(find.byKey(const Key('labs-desk-tile-مخبر آخر')), findsOneWidget);

    // ③ عدّادات «مخبر النور»: حالة دين واحدة ⇒ «1 نشطة» + «1 غير مدفوعة».
    expect(find.text('1 نشطة'), findsOneWidget,
        reason: 'شارة الحالات النشطة الذهبية');
    expect(find.text('1 غير مدفوعة'), findsOneWidget,
        reason: 'شارة غير المدفوعة الحمراء (المستحق > 0)');

    // ④ النقر يفتح جدول حالات المختبر في القسم الأيسر.
    await tester.tap(find.byKey(const Key('labs-desk-tile-مخبر النور')));
    await tester.pump(const Duration(milliseconds: 250));

    // جدول الحالات ظاهر يساراً (زر إدارة أعمدة الجدول + حقل بحثه دليلان).
    expect(find.byKey(const Key('desk-cols-labs-cases')), findsOneWidget,
        reason: 'جدول حالات المختبر يجب أن يظهر يساراً');
    expect(find.byKey(const Key('desk-search-labs-cases')), findsOneWidget);
    // ترويسة المختبر: الاسم + عدد الحالات.
    expect(find.byKey(const Key('labs-desk-detail-name')), findsOneWidget);
    // م161 — الترويسة صارت «N حالة · الشهر».
    // م161/ب — يظهر في الترويسة وفي صف إجمالي الجدول معاً.
    expect(find.textContaining('2 حالة'), findsWidgets,
        reason: 'عدد حالات المختبر في الترويسة وصف الإجمالي');

    // اسما المريضين ظاهران في الجدول.
    expect(find.text('أحمد المحصّل'), findsWidgets);
    expect(find.text('سالم المدين'), findsWidgets);
    // شارتا الحالة المالية في الجدول.
    expect(find.text('محصّل'), findsWidgets);
    expect(find.text('دين'), findsWidgets);

    // ⑤ ذيل المجاميع الستة — نتحقق من صحّتها.
    expect(find.byKey(const Key('labs-desk-totals')), findsOneWidget);
    // المحصّل 200.00 · الديون 300.00 · الصافي -100.00.
    expect(find.text('200.00 د.ل'), findsWidgets, reason: 'المحصّل');
    expect(find.byKey(const Key('labs-desk-total-debt')), findsOneWidget);
    expect(find.text('300.00 د.ل'), findsWidgets, reason: 'الديون');
    expect(find.text('-100.00 د.ل'), findsWidgets, reason: 'الصافي');
    // إجمالي الوحدات 2 + 1 = 3.
    expect(find.text('3'), findsWidgets, reason: 'إجمالي الوحدات');

    // ⑥ زر الطباعة موجود.
    expect(find.byKey(const Key('labs-desk-print')), findsOneWidget,
        reason: 'زر طباعة تقرير المختبر يجب أن يظهر في الترويسة');

    // ⑦ النقر المزدوج على صف يفتح لوحة تفاصيل الحالة الكاملة (مفتاح القيمة).
    //    نقرتان متتاليتان بنفس الموضع ضمن نافذة الـ double-tap.
    final rowCenter = tester.getCenter(find.text('أحمد المحصّل').first);
    await tester.tapAt(rowCenter);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(rowCenter);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('labs-desk-value')), findsOneWidget,
        reason: 'مفتاح قيمة التركيبة في لوحة تفاصيل الحالة يجب أن يظهر');
  });

  // ── الاختبار 4: زرع تركيبة تظهر في جدول حالات المختبر ─────────────────────

  testWidgets('زرع تركيبة تظهر في جدول حالات المختبر داخل تبويب إضافي',
      (tester) async {
    await bootSeeded(tester, (repos) {
      repos.prosthetics.upsertLocal({
        'id': 'test-pros-1',
        'name': 'محمد اختبار',
        'clinic': 'ع1',
        'date': '2026-08-06',
        'labName': 'مختبر الاختبار',
        'prosType': 'تاج معدني',
        'prosUnits': 1,
        'labValue': 500,
      });
    });

    await openLabs(tester);
    expect(find.byType(DesktopLabsScreen), findsOneWidget);

    // صف المختبر ظاهر — نقره يفتح جدول حالاته.
    expect(
        find.byKey(const Key('labs-desk-tile-مختبر الاختبار')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('labs-desk-tile-مختبر الاختبار')));
    await tester.pump(const Duration(milliseconds: 250));

    // اسم المريض المزروع ظاهر في الجدول.
    expect(find.text('محمد اختبار'), findsWidgets,
        reason: 'التركيبة المزروعة يجب أن تظهر في جدول الحالات');
    // جدول الحالات + ذيل المجاميع ظاهران.
    expect(find.byKey(const Key('desk-cols-labs-cases')), findsOneWidget);
    expect(find.byKey(const Key('labs-desk-totals')), findsOneWidget);
  });
}
