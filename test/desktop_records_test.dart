/// اختبارات شاشة السجلات المكتبية (Master/Detail):
///   • فتح تبويب السجلات يعرض رسالة «اختر مريضاً لعرض التفاصيل».
///   • النقر على مريض يعرض PatientProfileScreen داخل الشاشة دون صفحة جديدة.
///   • البحث باسم مريض يصفي القائمة.
///   • DesktopShell يبقى ظاهراً طوال التفاعلات (لا نقل صفحات فوق الصدفة).
///
///  م(تكافؤ الهاتف) — اختبارات إضافية تنسج على منوال harness أعلاه:
///   • بطاقة عيادة تعرض العدادات (مرضى/زيارات الشهر).
///   • مبدّل الفرز يبدّل ترتيب القائمة (الاسم مقابل النشاط).
///   • فلتر «عليه دين فقط» يقلص القائمة على أصحاب الدين.
///   • المؤرشف يظهر/يخفى بمفتاح «إظهار المؤرشفين».
///   • بند «طباعة ملف المريض» موجود بقائمة السياق (نقرة يمنى).
///   • البحث الضبابي يجد بالخطأ الإملائي البسيط (fuzzyMatch).
///
///  نمط الإقلاع: staffAdminSession + dbDirProvider + debugForceDesktopUi=true
///  بحجم 1600×1000 — حرفياً كـ desktop_shell_smoke_test.dart.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/desktop/desktop_shell.dart';
import 'package:dental_clinic_flutter/features/patients/archive_store.dart'
    show PatientArchiveStore;
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    show PatientProfileScreen;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_rec_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  // ── الإقلاع المشترك ──────────────────────────────────────────────────────

  /// يُقلع التطبيق بوضع سطح المكتب، ويزرع مريضَين، وينتقل لتبويب السجلات.
  /// [seed] — خطّاف زرع إضافي على حاوية البذر قبل نقل الشاشة (لاختبارات
  /// الدين والأرشفة): تُمرَّر repos حيّة فيكتب الاختبار بياناته بلا تكرار.
  Future<void> boot(
    WidgetTester tester, {
    void Function(ProviderContainer c, String month)? seed,
  }) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // الحاوية المؤقتة لزرع البيانات قبل نقل الشاشة.
    final c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);

    // إعداد العيادة والخدمات كما في اختبارات الصدفة.
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
    });

    // زرع مريضَين بسجلاتهما عبر المستودع مباشرةً.
    final month = getCurrentDate().substring(0, 7);
    c.read(reposProvider).records.bulkUpsert([
      {
        'id': 'rec-ahmed',
        'name': 'أحمد الزبير',
        'patient_name': 'أحمد الزبير',
        'clinic': 'ع1',
        'amount': 150,
        'date': '$month-05',
        'service': 'حشو',
        'payment': 'كاش',
        'phone': '0911234567',
      },
      {
        'id': 'rec-fatima',
        'name': 'فاطمة السالم',
        'patient_name': 'فاطمة السالم',
        'clinic': 'ع1',
        'amount': 200,
        'date': '$month-06',
        'service': 'قلع',
        'payment': 'تحويل',
        'phone': '0927654321',
      },
    ]);

    // زرع إضافي اختياري (دين/أرشفة) على نفس الحاوية قبل الإغلاق.
    seed?.call(c, month);
    c.dispose();

    // تشغيل التطبيق الفعلي بنفس المسار.
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

    // الانتقال لتبويب السجلات (desk-tab-clinics كما في DesktopShell).
    await tester.tap(find.byKey(const Key('desk-tab-clinics')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  // ── الاختبارات الأصلية ──────────────────────────────────────────────────

  testWidgets(
      'فتح تبويب السجلات يعرض رسالة «اختر مريضاً لعرض التفاصيل»',
      (tester) async {
    await boot(tester);

    // الرسالة الترحيبية في القسم الأيسر الفارغ.
    expect(
      find.text('اختر مريضاً لعرض التفاصيل'),
      findsOneWidget,
      reason: 'يجب أن تظهر رسالة الحالة الفارغة عند الفتح',
    );
    // الصدفة لا تزال ظاهرة (لم تُفتح صفحة جديدة).
    expect(find.byType(DesktopShell), findsOneWidget);
  });

  testWidgets(
      'النقر على مريض يعرض PatientProfileScreen داخل القسم الأيسر',
      (tester) async {
    await boot(tester);

    // التحقق من ظهور المريض الأول في قائمة اليمين.
    expect(
      find.text('أحمد الزبير'),
      findsOneWidget,
      reason: 'يجب أن يظهر المريض في القائمة',
    );

    // النقر على المريض — ينبغي أن يعرض ملفه في القسم الأيسر.
    await tester.tap(find.text('أحمد الزبير'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // PatientProfileScreen يظهر داخل الشاشة.
    expect(
      find.byType(PatientProfileScreen),
      findsOneWidget,
      reason: 'PatientProfileScreen يجب أن يُعرض في القسم الأيسر',
    );
    // DesktopShell لا تزال ظاهرة — لم تُفتح صفحة جديدة فوقها.
    expect(
      find.byType(DesktopShell),
      findsOneWidget,
      reason: 'DesktopShell يجب أن تبقى ظاهرة (لا صفحة جديدة)',
    );
    // رسالة الحالة الفارغة اختفت.
    expect(
      find.text('اختر مريضاً لعرض التفاصيل'),
      findsNothing,
      reason: 'رسالة الحالة الفارغة تختفي بعد الاختيار',
    );
  });

  testWidgets(
      'اختيار مريض ثان يبدّل القسم الأيسر دون فتح صفحات',
      (tester) async {
    await boot(tester);

    // اختيار المريض الأول.
    await tester.tap(find.text('أحمد الزبير'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PatientProfileScreen), findsOneWidget);

    // اختيار المريض الثاني — القسم الأيسر يتبدل فقط.
    await tester.tap(find.text('فاطمة السالم'));
    await tester.pump(const Duration(milliseconds: 300));

    // الصدفة لا تزال واحدة (لا صفحات فوقها).
    expect(find.byType(DesktopShell), findsOneWidget);
    // ملف المريض لا يزال ظاهراً (للمريض الثاني الآن).
    expect(find.byType(PatientProfileScreen), findsOneWidget);
  });

  testWidgets('البحث باسم مريض يصفي القائمة', (tester) async {
    await boot(tester);

    // حقل البحث بـ hintText معروف — نُدخل اسم المريض الأول.
    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'بحث بالاسم أو الهاتف…',
    );
    expect(searchField, findsOneWidget,
        reason: 'حقل البحث يجب أن يكون موجوداً');

    await tester.enterText(searchField, 'أحمد');
    await tester.pump(const Duration(milliseconds: 200));

    // المريض الأول يظهر، الثاني يختفي.
    expect(
      find.text('أحمد الزبير'),
      findsOneWidget,
      reason: 'أحمد يجب أن يظهر في نتائج البحث',
    );
    expect(
      find.text('فاطمة السالم'),
      findsNothing,
      reason: 'فاطمة يجب أن تختفي عند البحث بـ «أحمد»',
    );

    // مسح البحث يعيد كلا المريضين.
    await tester.enterText(searchField, '');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('أحمد الزبير'), findsOneWidget);
    expect(find.text('فاطمة السالم'), findsOneWidget);
  });

  // ── م(تكافؤ الهاتف) — الاختبارات الإضافية ─────────────────────────────────

  testWidgets(
      'شريط العيادات: رقائق مطويّة بعدّاد المرضى ثم بطاقات موسّعة بالزيارات',
      (tester) async {
    await boot(tester);

    // ── الوضع المطويّ الافتراضي: رقائق أفقية بدل البطاقات العمودية ──
    // رقاقة العيادة «ع1» ورقاقة «كل العيادات» حاضرتان.
    expect(find.byKey(const Key('dr-clinic-chip-ع1')), findsOneWidget,
        reason: 'رقاقة العيادة يجب أن تظهر في الشريط المطويّ');
    expect(find.byKey(const Key('dr-clinic-chip-all')), findsOneWidget,
        reason: 'رقاقة كل العيادات يجب أن تبقى خياراً');
    // العدّاد المدمج «· 2» (عدد مرضى العيادة) على الرقاقة.
    expect(
      find.descendant(
          of: find.byKey(const Key('dr-clinic-chip-ع1')),
          matching: find.textContaining('2')),
      findsWidgets,
      reason: 'عدد المرضى (2) يجب أن يظهر على الرقاقة',
    );
    // البطاقات الموسّعة غير مبنية في الوضع المطويّ.
    expect(find.byKey(const Key('dr-clinic-card-ع1')), findsNothing,
        reason: 'بطاقة الوضع الموسّع مخفية افتراضياً (الشريط مطويّ)');

    // ── التوسيع: البطاقات الكاملة بالزيارات تظهر ──
    await tester.tap(find.byKey(const Key('dr-clinic-strip-toggle')));
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('dr-clinic-card-ع1'));
    expect(card, findsOneWidget,
        reason: 'بطاقة العيادة تظهر في الوضع الموسّع');
    expect(find.byKey(const Key('dr-clinic-card-all')), findsOneWidget,
        reason: 'بطاقة كل العيادات تظهر في الوضع الموسّع');
    // العدّادات: مريضان و«زيارة هذا الشهر» على البطاقة (سجلان في الشهر).
    expect(
      find.descendant(of: card, matching: find.text('2')),
      findsWidgets,
      reason: 'عدد المرضى (2) يجب أن يظهر على البطاقة',
    );
    expect(
      find.descendant(
          of: card, matching: find.textContaining('زيارة هذا الشهر')),
      findsOneWidget,
      reason: 'سطر «X زيارة هذا الشهر» يجب أن يظهر على البطاقة الموسّعة',
    );
  });

  testWidgets('مبدّل الفرز يبدّل ترتيب القائمة (الاسم مقابل النشاط)',
      (tester) async {
    await boot(tester);

    // الترتيب الافتراضي «الأحدث نشاطاً»: فاطمة (05-06) قبل أحمد (05-05).
    Offset yOf(String name) => tester.getTopLeft(find.text(name));
    expect(yOf('فاطمة السالم').dy < yOf('أحمد الزبير').dy, isTrue,
        reason: 'الافتراضي: الأحدث نشاطاً — فاطمة أولاً');

    // فتح قمع الأدوات واختيار الفرز بالاسم.
    await tester.tap(find.byKey(const Key('dr-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dr-sort-name')));
    await tester.pumpAndSettle();

    // بالاسم: «أحمد» (أ) قبل «فاطمة» (ف) — انقلب الترتيب.
    expect(yOf('أحمد الزبير').dy < yOf('فاطمة السالم').dy, isTrue,
        reason: 'الفرز بالاسم يقدّم أحمد على فاطمة');
  });

  testWidgets('فلتر «عليه دين فقط» يقلص القائمة على أصحاب الدين',
      (tester) async {
    await boot(tester, seed: (c, month) {
      // دين مفتوح لأحمد فقط (status != paid) → hasDebt=true له وحده.
      c.read(reposProvider).debts.bulkUpsert([
        {
          'id': 'debt-ahmed',
          'name': 'أحمد الزبير',
          'clinic': 'ع1',
          'recordId': 'rec-ahmed',
          'totalAmount': 150,
          'paidAmount': 50,
          'remaining': 100,
          'status': 'partial',
          'date': '$month-05',
        },
      ]);
    });

    // قبل الفلتر: كلاهما ظاهر.
    expect(find.text('أحمد الزبير'), findsOneWidget);
    expect(find.text('فاطمة السالم'), findsOneWidget);

    // تفعيل «عليه دين/متبقٍ فقط» من قمع الأدوات.
    await tester.tap(find.byKey(const Key('dr-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dr-filter-debt')));
    await tester.pumpAndSettle();

    // بعد الفلتر: أحمد (له دين) يبقى، فاطمة (بلا دين) تختفي.
    expect(find.text('أحمد الزبير'), findsOneWidget,
        reason: 'صاحب الدين يبقى بعد فلتر الدين');
    expect(find.text('فاطمة السالم'), findsNothing,
        reason: 'من لا دين عليه يختفي عند فلتر الدين');
  });

  testWidgets('المؤرشف يظهر/يخفى بمفتاح «إظهار المؤرشفين»',
      (tester) async {
    await boot(tester, seed: (c, month) {
      // أرشفة فاطمة عبر المخزن نفسه (يكتب في settings الملفية فيبقى بعد
      // إعادة إنشاء الحاوية على نفس dbDir).
      PatientArchiveStore(c.read(reposProvider).settings)
          .archive('فاطمة السالم', 'ع1');
    });

    // افتراضاً المؤرشفون مخفيون: أحمد يظهر، فاطمة مخفية.
    expect(find.text('أحمد الزبير'), findsOneWidget);
    expect(find.text('فاطمة السالم'), findsNothing,
        reason: 'المؤرشف مخفي افتراضياً');

    // تفعيل «إظهار المؤرشفين».
    await tester.tap(find.byKey(const Key('dr-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dr-filter-archived')));
    await tester.pumpAndSettle();

    // الآن يظهر المؤرشف بشارته الرمادية.
    expect(find.text('فاطمة السالم'), findsOneWidget,
        reason: 'المؤرشف يظهر عند تفعيل المفتاح');
    expect(find.text('مؤرشف'), findsWidgets,
        reason: 'شارة «مؤرشف» تظهر على الصف');
  });

  testWidgets('بند «طباعة ملف المريض» موجود بقائمة السياق (نقرة يمنى)',
      (tester) async {
    await boot(tester);

    // نقرة يمنى على صف المريض تفتح قائمة السياق المكتبية.
    await tester.tap(find.text('أحمد الزبير'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    // بنود الأفعال بمفاتيح ctx-<keyId> (من showDesktopContextMenu).
    expect(find.byKey(const Key('ctx-records-print-profile')),
        findsOneWidget,
        reason: 'بند «طباعة ملف المريض» يجب أن يكون في قائمة السياق');
    // وبقية الأفعال المكافئة للهاتف حاضرة أيضاً.
    expect(find.byKey(const Key('ctx-records-quick-visit')),
        findsOneWidget,
        reason: 'بند «زيارة سريعة جديدة» حاضر');
    expect(find.byKey(const Key('ctx-records-edit-patient')),
        findsOneWidget,
        reason: 'بند «تعديل البيانات» حاضر');
    expect(
        find.byKey(const Key('ctx-records-archive')), findsOneWidget,
        reason: 'بند «أرشفة المريض» حاضر');
  });

  testWidgets('طباعة ملف المريض من قائمة السياق تفتح الملف في اللوح',
      (tester) async {
    await boot(tester);

    await tester.tap(find.text('أحمد الزبير'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    // اختيار «طباعة ملف المريض» يفتح PatientProfileScreen في اللوح
    // (بتمرير autoPrint=true — نتحقق من ظهور الملف دون فتح صفحة كاملة).
    await tester.tap(find.byKey(const Key('ctx-records-print-profile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final profile = tester.widget<PatientProfileScreen>(
        find.byType(PatientProfileScreen));
    expect(profile.autoPrint, isTrue,
        reason: 'فعل الطباعة يمرر autoPrint=true للملف');
    expect(find.byType(DesktopShell), findsOneWidget,
        reason: 'الصدفة تبقى ظاهرة (اللوح لا صفحة جديدة)');
  });

  testWidgets('البحث الضبابي يجد بالخطأ الإملائي البسيط',
      (tester) async {
    await boot(tester);

    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'بحث بالاسم أو الهاتف…',
    );

    // «الزبير» بحرف مقلوب («الزبير» → «الزبيير») — خطأ إملائي بسيط
    // (مسافة levenshtein = 1) يجب أن يطابق أحمد الزبير عبر fuzzyMatch.
    await tester.enterText(searchField, 'احمد الزبيير');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('أحمد الزبير'), findsOneWidget,
        reason: 'البحث الضبابي يجد الاسم رغم الخطأ الإملائي البسيط');
    expect(find.text('فاطمة السالم'), findsNothing,
        reason: 'الاسم غير المطابق لا يظهر');
  });
}
