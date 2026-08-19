/// اختبارات م90 — تمييز مريضَين بنفس الاسم داخل العيادة الواحدة (بالهاتف).
///
///  قرار المالك (يحدّث م35 جزئياً): الهوية العرضية كانت (اسم|عيادة)، فمريضان
///  متشابهان في نفس العيادة يندمجان بطاقةً وملفاً. التمييز الآن برقم الهاتف —
///  وهو أصلاً جزء هوية الخلفية (p:هاتف:اسم) — **في طبقة العرض والتنقل فقط**:
///  لا مساس بالمزامنة ولا الحمولات ولا أي هجرة.
///
///  قاعدة التقسيم الحتمية (دالة مشتركة واحدة):
///  • هاتفٌ مميز واحد أو لا شيء في المجموعة ⇒ هوية واحدة — سلوك م35 حرفياً.
///  • هاتفان مختلفان فأكثر ⇒ صفوف كل هاتف هوية، والصفوف بلا هاتف هوية
///    «بلا رقم» مستقلة (لا تخمين في إلحاقها).
///
/// 🔄 **م189:** شكل الهاتف في فضاء الهوية صار **قانونياً** (`normPhone`) —
/// فالهويات هنا بلا صفر البدء (`p:911111111`)، والعزل نفسه محفوظ. السبب:
/// تعايش الشكل الخام مع المسكوك في `patient_id` كان يلد ملفاً شبحاً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/db/bootstrap.dart';
import 'package:dental_clinic_flutter/data/db/schema_sql.dart';
import 'package:dental_clinic_flutter/data/db/migrations.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    show PatientProfileScreen;
import 'package:dental_clinic_flutter/features/patients/treatment_plan_store.dart'
    show TreatmentPlanStore;
import 'package:dental_clinic_flutter/features/patients/clinic_scope.dart'
    show medicalScopedRead;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

JMap _rec(
  String id,
  String name,
  String clinic, {
  String phone = '',
  num amount = 100,
}) => {
  'id': id,
  'name': name,
  'clinic': clinic,
  'phone': phone,
  'service': 'حشو',
  'date': '2026-07-2$id'.substring(0, 10),
  'amount': amount,
  'payment': 'كاش',
};

void main() {
  group('م90/أ — قاعدة التقسيم في التجميعة', () {
    test('هاتفان مختلفان بنفس الاسم والعيادة ⇒ هويتان منفصلتان بأموالهما', () {
      final map = buildPatientMap(
        [
          _rec('1', 'محمد علي', 'ع1', phone: '0911111111', amount: 100),
          _rec('2', 'محمد علي', 'ع1', phone: '0922222222', amount: 250),
        ],
        const [],
        const [],
      );
      expect(map.length, 2, reason: 'م90: التشابه داخل العيادة ينقسم بالهاتف');
      final totals = map.values.map((a) => a.total).toSet();
      expect(totals, {
        100,
        250,
      }, reason: 'م90: أموال كل هوية لها وحدها — لا خلط');
      final phones = map.values.map((a) => a.phone).toSet();
      // م189 — هاتف **العرض** خامٌ كما كتبه المستخدم (والهوية قانونية).
      expect(phones, {'0911111111', '0922222222'});
      for (final a in map.values) {
        expect(
          a.identity,
          isNotEmpty,
          reason: 'م90: التجميعة المنقسمة تحمل هويتها',
        );
      }
    });

    test('الصفوف بلا هاتف عند الانقسام ⇒ هوية «بلا رقم» ثالثة مستقلة', () {
      final map = buildPatientMap(
        [
          _rec('1', 'محمد علي', 'ع1', phone: '0911111111'),
          _rec('2', 'محمد علي', 'ع1', phone: '0922222222'),
          _rec('3', 'محمد علي', 'ع1'), // بلا هاتف — لا تخمين في إلحاقه
        ],
        const [],
        const [],
      );
      expect(map.length, 3);
      expect(map.values.where((a) => a.identity == 'none').length, 1);
    });

    test('هاتف واحد (مع صفوف بلا هاتف) ⇒ هوية واحدة — سلوك م35 حرفياً', () {
      final map = buildPatientMap(
        [
          _rec('1', 'سالم', 'ع1', phone: '0911111111', amount: 100),
          _rec('2', 'سالم', 'ع1', amount: 50), // قديم بلا هاتف — يبقى معه
        ],
        const [],
        const [],
      );
      expect(map.length, 1, reason: 'م90: لا انقسام بلا هاتفين مختلفين');
      expect(map.values.single.total, 150);
      expect(map.values.single.identity, isEmpty);
    });

    test('نفس الاسم في عيادتين يبقى مفصولاً بالعيادة (م35 كما هو)', () {
      final map = buildPatientMap(
        [
          _rec('1', 'محمد علي', 'ع1', phone: '0911111111'),
          _rec('2', 'محمد علي', 'ع2', phone: '0911111111'),
        ],
        const [],
        const [],
      );
      expect(map.length, 2);
    });

    test('ديون المجموعة المنقسمة تُنسب لهوية هاتفها', () {
      final map = buildPatientMap(
        [
          _rec('1', 'محمد علي', 'ع1', phone: '0911111111'),
          _rec('2', 'محمد علي', 'ع1', phone: '0922222222'),
        ],
        const [],
        [
          {
            'id': 'd1',
            'name': 'محمد علي',
            'clinic': 'ع1',
            'phone': '0922222222',
            'totalAmount': 900,
            'paidAmount': 200,
            'remaining': 700,
            'status': 'partial',
            'date': '2026-07-25',
          },
        ],
      );
      final withDebt = map.values.where((a) => a.debtRemaining > 0).toList();
      expect(withDebt.length, 1);
      expect(
        withDebt.single.phone,
        '0922222222',
        reason: 'م90: الدين على صاحب الهاتف لا على سميِّه',
      );
    });

    test('rowMatchesIdentity: العقد الحرفي للهوية الفرعية', () {
      expect(
        rowMatchesIdentity({'phone': '0911'}, ''),
        isTrue,
        reason: 'بلا هوية = الكل (السلوك القائم)',
      );
      expect(rowMatchesIdentity({'phone': '0911'}, 'p:911'), isTrue);
      expect(rowMatchesIdentity({'phone': '0922'}, 'p:911'), isFalse);
      expect(rowMatchesIdentity({'phone': ''}, 'none'), isTrue);
      expect(rowMatchesIdentity({'phone': '0911'}, 'none'), isFalse);
    });
  });

  group('م90/ب — الواجهة: بطاقتان وملفان منفصلان', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m90_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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
        'name': 'محمد علي',
        'patient_name': 'محمد علي',
        'clinic': 'ع1',
        'phone': '0911111111',
        'service': 'حشو',
        'date': '2026-07-20',
        'amount': 100,
        'payment': 'كاش',
      });
      repos.records.upsertLocal({
        'id': 'r2',
        'name': 'محمد علي',
        'patient_name': 'محمد علي',
        'clinic': 'ع1',
        'phone': '0922222222',
        'service': 'حشو',
        'date': '2026-07-21',
        'amount': 250,
        'payment': 'كاش',
      });
      // دينٌ لصاحب الهاتف الثاني وحده.
      repos.debts.upsertLocal({
        'id': 'd2',
        'name': 'محمد علي',
        'patient_name': 'محمد علي',
        'clinic': 'ع1',
        'phone': '0922222222',
        'service': 'حشو',
        'date': '2026-07-22',
        'totalAmount': 900,
        'paidAmount': 200,
        'remaining': 700,
        'status': 'partial',
      });
      seed.dispose();

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
      // تبويب السجلات ← عيادة ع1.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('ع1').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('حارس الإدخال: اسم مكرر بهاتف مختلف ⇒ حوار قبل إنشاء سميّ', (
      tester,
    ) async {
      await boot(tester);
      // م133 — نموذج الإدخال rec-* لم يبق على تبويب «الرئيسية» (صار
      // DailyIncomeScreen)؛ انتقل إلى ورقة سفلية تُفتح بالزر العائم
      // Key('fab-add') (app_shell.dart). كل مفاتيح rec-* باقية بلا تغيير.
      // م172 — «+» صار في الرئيسية فقط: نعود إليها أولاً (استقرارٌ
      // لحركة تكبير الزر العائم قبل نقره).
      await tester.tap(find.text('الرئيسية'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('rec-name')), 'محمد علي');
      await tester.enterText(find.byKey(const Key('rec-phone')), '0933333333');
      await tester.enterText(find.byKey(const Key('rec-amount')), '75');
      await tester.ensureVisible(find.byKey(const Key('rec-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rec-save')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // الحوار حاضر — «رجوع» لا يحفظ.
      expect(
        find.text('اسم مكرر في العيادة'),
        findsOneWidget,
        reason: 'م90: هاتف ثالث مختلف = سميّ جديد — يحتاج تأكيداً',
      );
      await tester.tap(find.byKey(const Key('twin-cancel')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('تم حفظ السجل'),
        findsNothing,
        reason: 'م90: الرجوع من الحوار لا يكتب شيئاً',
      );

      // الحفظ مجدداً مع «إنشاء مريض جديد» ⇒ يُحفظ.
      await tester.tap(find.byKey(const Key('rec-save')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('twin-proceed')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('تم حفظ السجل'),
        findsOneWidget,
        reason: 'م90: المتابعة الواعية تحفظ سميّاً مستقلاً',
      );
    });

    testWidgets('حارس الإدخال: نفس الهاتف القائم ⇒ حفظ صامت بلا حوار', (
      tester,
    ) async {
      await boot(tester);
      // م133 — نفس انتقال rec-* إلى ورقة fab-add أعلاه.
      // م172 — «+» في الرئيسية فقط: نعود إليها أولاً (استقرار الحركة).
      await tester.tap(find.text('الرئيسية'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('rec-name')), 'محمد علي');
      await tester.enterText(find.byKey(const Key('rec-phone')), '0911111111');
      await tester.enterText(find.byKey(const Key('rec-amount')), '60');
      await tester.ensureVisible(find.byKey(const Key('rec-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rec-save')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('اسم مكرر في العيادة'),
        findsNothing,
        reason: 'م90: هوية قائمة مطابقة — زيارة عادية بلا إزعاج',
      );
      expect(find.text('تم حفظ السجل'), findsOneWidget);
    });

    testWidgets('قائمة العيادة تعرض بطاقتين للمتشابهين بهاتف كل منهما', (
      tester,
    ) async {
      await boot(tester);
      expect(
        find.byKey(const Key('patient-card-محمد علي|p:911111111')),
        findsOneWidget,
        reason: 'م90: بطاقة الهوية الأولى',
      );
      expect(
        find.byKey(const Key('patient-card-محمد علي|p:922222222')),
        findsOneWidget,
        reason: 'م90: بطاقة الهوية الثانية',
      );
      // سطرا الهاتف الصغيران للتفريق البصري.
      expect(find.textContaining('0911111111'), findsWidgets);
      expect(find.textContaining('0922222222'), findsWidgets);
    });

    testWidgets('القفز من تبويب الديون يفتح هوية صاحب الدين لا سميّه', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      // م133 — بطاقة القسم تفتح MaterialPageRoute حقيقياً (م108)؛ نبضة
      // ثابتة واحدة لا تكفي لإنهاء حركة الانتقال فتبقى شاشة الديون خارج
      // الشجرة (نفس ما وُجد في m89_debt_jump_clinic_test.dart).
      await tester.tap(
        find.byKey(const Key('fin-seg-debts')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // نقر اسم دين صاحب الهاتف الثاني (نمط م89: المعالج مباشرة).
      final ink = tester.widget<InkWell>(find.byKey(const Key('debt-name-d2')));
      ink.onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PatientProfileScreen), findsOneWidget);
      final p = tester.widget<PatientProfileScreen>(
        find.byType(PatientProfileScreen),
      );
      expect(p.clinic, 'ع1');
      expect(
        p.identity,
        'p:922222222',
        reason: 'م90: هوية صفّ الدين المنقور تمرّ حتى شاشة الملف',
      );
    });

    Future<void> openCard(WidgetTester tester, String key) async {
      final f = find.byKey(Key(key));
      await tester.ensureVisible(f);
      await tester.pump();
      // نقر مركز البطاقة (InkWell يملأها) — ثم مهلة دفع الملاحة والملف.
      await tester.tap(f, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('فتح كل بطاقة يعرض ملف هويتها وحدها (زياراتها ودينها)', (
      tester,
    ) async {
      await boot(tester);

      // الهوية الأولى: زيارة 100، بلا دين.
      await openCard(tester, 'patient-card-محمد علي|p:911111111');
      expect(find.byType(PatientProfileScreen), findsOneWidget);
      final p1 = tester.widget<PatientProfileScreen>(
        find.byType(PatientProfileScreen),
      );
      expect(p1.identity, 'p:911111111');
      expect(
        find.textContaining('250'),
        findsNothing,
        reason: 'م90: مبلغ زيارة السميّ لا يظهر في ملف غيره',
      );
      Navigator.of(tester.element(find.byType(PatientProfileScreen))).pop();
      await tester.pump(const Duration(milliseconds: 600));

      // الهوية الثانية: زيارة 250 ودين 900/700.
      await openCard(tester, 'patient-card-محمد علي|p:922222222');
      expect(find.byType(PatientProfileScreen), findsOneWidget);
      final p2 = tester.widget<PatientProfileScreen>(
        find.byType(PatientProfileScreen),
      );
      expect(p2.identity, 'p:922222222');
    });

    testWidgets('ترويسة الملف تطابق صفوف الهوية (لا 0/0/0) — لقطة المالك', (
      tester,
    ) async {
      await boot(tester);
      // هوية الهاتف الثاني: 250 زيارة + دين 900 (متبقٍّ 700، مدفوع 200).
      await openCard(tester, 'patient-card-محمد علي|p:922222222');
      expect(find.byType(PatientProfileScreen), findsOneWidget);
      // فتح الملخص المالي (البطاقة مطوية افتراضياً).
      await tester.tap(find.byKey(const Key('pp-summary-toggle')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));

      // الترويسة تطابق تجميعة الهوية — لا 0/0/0 (قبل الإصلاح كانت التجميعة
      // null فتُقرأ فارغةً بينما الصفوف المرشحة تعرض قيمها).
      expect(
        find.descendant(
            of: find.byKey(const Key('pp-total')),
            matching: find.text('1,150')),
        findsOneWidget,
        reason: 'الإجمالي = 250 + 900 (لا صفر)',
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('pp-paid')), matching: find.text('450')),
        findsOneWidget,
        reason: 'المدفوع = 250 + 200',
      );
      expect(
        find.descendant(
            of: find.byKey(const Key('pp-debt')), matching: find.text('700')),
        findsOneWidget,
        reason: 'الديون = 700',
      );
    });
  });

  // ── م-عزل الهوية/ج — عزل التجميعة (سبب لقطة 0/0/0) ────────────────────────
  group('م-عزل الهوية/ج — patientForClinic/treatmentCards بالهوية', () {
    // نفس بذرة لقطتَي المالك: سميّان بهاتفين، لأحدهما دين.
    final recs = [
      _rec('1', 'حسن', 'الصفوة', phone: '0911111111', amount: 100),
      _rec('2', 'حسن', 'الصفوة', phone: '0922222222', amount: 250),
    ];
    final dbts = [
      {
        'id': 'd2',
        'name': 'حسن',
        'clinic': 'الصفوة',
        'phone': '0922222222',
        'service': 'تقويم',
        'date': '2026-07-25',
        'totalAmount': 900,
        'paidAmount': 200,
        'remaining': 700,
        'status': 'partial',
      },
    ];

    test('ترويسة الملف تطابق مجموع صفوف الهوية (تعيد إنتاج 0/0/0 وتثبت الإصلاح)',
        () {
      // الهوية الأولى: زيارة 100 فقط، بلا دين — لا يتسرّب 250 ولا الدين.
      final a1 = patientForClinic('حسن', 'الصفوة',
          records: recs, prosthetics: const [], debts: dbts,
          identity: 'p:911111111')!;
      expect(a1.grossTotal, 100);
      expect(a1.total, 100);
      expect(a1.debtRemaining, 0);
      expect(a1.visitCount, 1);

      // الهوية الثانية: 250 + دين 900 (متبقٍّ 700، مدفوع 200).
      final a2 = patientForClinic('حسن', 'الصفوة',
          records: recs, prosthetics: const [], debts: dbts,
          identity: 'p:922222222')!;
      expect(a2.grossTotal, 1150, reason: '250 زيارة + 900 دين');
      expect(a2.total, 450, reason: '250 + 200 مدفوع الدين');
      expect(a2.debtRemaining, 700);
      expect(a2.visitCount, 2);

      // **جذر لقطة 0/0/0 حرفياً**: بلا تمرير هوية، كان buildPatientMap
      // يقسم مجموعة الاسم بمفاتيح مركّبة («حسن||p:هاتف») فلا يجد
      // patientForClinic مفتاح الاسم المجرّد ⇒ null ⇒ ترويسة 0/0/0.
      // م181 — الإصلاح الجذري الثاني: البناء صار بلا انقسام داخلي
      // (splitSameName:false) فيعيد الفتحُ بلا هوية تجميعةً **موحّدة**
      // تطابق كل الصفوف الظاهرة — لا null ولا 0/0/0 بأي مسار.
      final merged = patientForClinic('حسن', 'الصفوة',
          records: recs, prosthetics: const [], debts: dbts);
      expect(merged, isNotNull,
          reason: 'م181: مفتاح الاسم يجد التجميعة دائماً — زال 0/0/0');
      expect(merged!.grossTotal, 1250, reason: '100 + 250 + 900 موحّدة');
      expect(merged.total, 550, reason: '100 + 250 + 200 مدفوع الدين');
      expect(merged.debtRemaining, 700);
      // وتمرير الهوية يبقى العزل الصحيح لكل سميّ.
      expect(a1.grossTotal, 100);
      expect(a2.grossTotal, 1150);
    });

    test('treatmentCards بالهوية: بطاقات معالجات هوية لا سميّها', () {
      // تركيبة لصاحب الهاتف الثاني فقط.
      final pros = [
        {
          'id': 'p2',
          'name': 'حسن',
          'clinic': 'الصفوة',
          'phone': '0922222222',
          'service': 'تركيبات',
          'date': '2026-07-26',
          'total': 500,
          '_t': 'p',
        },
      ];
      final aggA = patientForClinic('حسن', 'الصفوة',
          records: recs, prosthetics: pros, debts: dbts,
          identity: 'p:911111111')!;
      final cardsA = treatmentCards(
        patient: aggA,
        patientName: 'حسن',
        clinic: 'الصفوة',
        prosthetics: pros,
        debts: dbts,
        identity: 'p:911111111',
      );
      // الهوية الأولى بلا تركيبات (تركيبة السميّ لا تظهر لها).
      expect(cardsA.any((c) => c.service == 'تركيبات'), isFalse);

      final aggB = patientForClinic('حسن', 'الصفوة',
          records: recs, prosthetics: pros, debts: dbts,
          identity: 'p:922222222')!;
      final cardsB = treatmentCards(
        patient: aggB,
        patientName: 'حسن',
        clinic: 'الصفوة',
        prosthetics: pros,
        debts: dbts,
        identity: 'p:922222222',
      );
      expect(cardsB.any((c) => c.service == 'تركيبات'), isTrue,
          reason: 'تركيبة صاحب الهاتف الثاني تظهر لهويته');
    });
  });

  // ── م-عزل الهوية/د — الردم الحتمي (هجرة phaseA2) ──────────────────────────
  group('م-عزل الهوية/د — هجرة الردم الحتمية', () {
    void ins(Database db, String t, String id, String name, String? phone,
        {int dirty = 0}) {
      final data = phone == null
          ? '{"name":"$name"}'
          : '{"name":"$name","phone":"$phone"}';
      db.execute(
        'INSERT INTO $t (id, patient_name, data, _dirty, _deleted) '
        'VALUES (?,?,?,?,0)',
        [id, name, data, dirty],
      );
    }

    test('تفك صفوف الهاتف لهويتين، وتحصر الملتبس (بلا COUNT(DISTINCT)=1)', () {
      final db = sqlite3.open(':memory:');
      addTearDown(db.close);
      db.execute(schemaSql);
      // تشغيلٌ أول ينشئ الأعمدة والأعلام، ثم نزيل علم phaseA2 كي يُعاد
      // على الصفوف المبذورة بعده.
      runMigrations(SqliteMigrationShim(db));
      db.execute("DELETE FROM metadata WHERE key='phaseA2_identity_backfill'");

      ins(db, 'records', 'r1', 'محمد علي', '0911111111');
      ins(db, 'records', 'r2', 'محمد علي', '0922222222');
      ins(db, 'records', 'r3', 'محمد علي', null); // ملتبس (اسم بين هويتين)
      ins(db, 'records', 'r4', 'خالد', '0933333333', dirty: 1); // dirty يُترك
      ins(db, 'records', 'r5', 'سعاد', null); // اسم فريد — ليس ملتبساً

      runMigrations(SqliteMigrationShim(db));

      String? pidOf(String id) => db.select(
          'SELECT patient_id FROM records WHERE id=?',
          [id]).first['patient_id'] as String?;

      // السميّان انفصلا بمعرّفين هاتفيين مختلفين — جوهر الإصلاح.
      expect(pidOf('r1'), 'p:911111111:محمد علي');
      expect(pidOf('r2'), 'p:922222222:محمد علي');
      expect(pidOf('r1') != pidOf('r2'), isTrue,
          reason: 'شرط COUNT(DISTINCT)=1 كان يمنع الفصل — أُزيل');
      // الملتبس (بلا هاتف واسم مكرر) لم يُلمس.
      expect(pidOf('r3'), isNull);
      // dirty=1 تُركت لجولة لاحقة (لا تُدفع هجرةٌ كتعديل).
      expect(pidOf('r4'), isNull);
      expect(db.select('SELECT _dirty FROM records WHERE id=?', ['r4'])
          .first['_dirty'], 1);

      // عدّاد الملتبس في سجل الهجرة = 1 (r3 وحده).
      final amb = db.select(
          "SELECT value FROM metadata WHERE key='phaseA2_ambiguous_count'");
      expect(amb.single['value'], '1');

      // صفوف patients أُعيد بناؤها هوياتياً: صفٌّ لكل هوية هاتفية.
      final pats = db
          .select("SELECT id FROM patients WHERE patient_id LIKE 'p:%'")
          .map((r) => r['id'] as String)
          .toSet();
      expect(pats.contains('p:911111111:محمد علي'), isTrue);
      expect(pats.contains('p:922222222:محمد علي'), isTrue);
    });

    test('إعادة التشغيل بلا أثر (idempotent) — العلم يمنع التكرار', () {
      final db = sqlite3.open(':memory:');
      addTearDown(db.close);
      db.execute(schemaSql);
      runMigrations(SqliteMigrationShim(db));
      db.execute("DELETE FROM metadata WHERE key='phaseA2_identity_backfill'");
      ins(db, 'records', 'r1', 'نور', '0911111111');
      runMigrations(SqliteMigrationShim(db));
      final pid1 = db.select('SELECT patient_id FROM records WHERE id=?',
          ['r1']).first['patient_id'];
      final patCount1 =
          db.select('SELECT COUNT(*) c FROM patients').first['c'];
      // تشغيلٌ ثانٍ: العلم مثبت ⇒ لا صف مرضى مكرر ولا تغيير.
      runMigrations(SqliteMigrationShim(db));
      expect(db.select('SELECT patient_id FROM records WHERE id=?',
          ['r1']).first['patient_id'], pid1);
      expect(db.select('SELECT COUNT(*) c FROM patients').first['c'],
          patCount1);
    });
  });

  // ── م-عزل الهوية/هـ — الكتابة والاكتساح والطبية/الخطة ─────────────────────
  group('م-عزل الهوية/هـ — عزل الكتابة والاكتساح', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m90e_');
      c = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('editPatientCascade بهوية لا يمسّ صفوف السميّ', () {
      final repos = c.read(reposProvider);
      // سميّان بهاتفين مختلفين، لكلٍّ سجلٌّ في العيادة نفسها.
      repos.records.upsertLocal({
        'id': 'a', 'name': 'محمد علي', 'patient_name': 'محمد علي',
        'clinic': 'الصفوة', 'phone': '0911111111', 'service': 'حشو',
        'date': '2026-07-20', 'amount': 100, 'payment': 'كاش',
      });
      repos.records.upsertLocal({
        'id': 'b', 'name': 'محمد علي', 'patient_name': 'محمد علي',
        'clinic': 'الصفوة', 'phone': '0922222222', 'service': 'حشو',
        'date': '2026-07-21', 'amount': 250, 'payment': 'كاش',
      });

      // تعديل اسم هوية الهاتف الأول فقط.
      final touched = editPatientCascade(
        repos,
        origName: 'محمد علي',
        newName: 'محمد علي الأب',
        phone: '0911111111',
        clinic: 'الصفوة',
        identity: 'p:911111111',
      );
      expect(touched, greaterThanOrEqualTo(1));

      final a = repos.records.getById('a')!;
      final b = repos.records.getById('b')!;
      expect(a['name'], 'محمد علي الأب', reason: 'هوية الهاتف الأول تُعاد تسميتها');
      expect(b['name'], 'محمد علي',
          reason: 'السميّ (الهاتف الثاني) لم يُمس — عزل الاكتساح');
    });

    test('المعلومات الطبية تتبع الهوية المفتوحة (هاتفها)', () {
      // كتابةٌ لهوية الهاتف الأول، وقراءةٌ بهاتف الثاني ⇒ لا تسرّب.
      final medA = medicalScopedRead(
        <String, Object?>{}, 'محمد علي', 'الصفوة', '0911111111');
      expect(medA, anyOf(isNull, isEmpty));
      final written = {
        'patientMedical': _medWrite(
          'محمد علي', 'الصفوة', '0911111111', {'allergy': 'بنسلين'}),
      };
      // القراءة بهاتف الهوية الأولى تجد الحساسية.
      final r1 = medicalScopedRead(
        written['patientMedical'], 'محمد علي', 'الصفوة', '0911111111');
      expect((r1 as Map)['allergy'], 'بنسلين');
      // القراءة بهاتف السميّ (الثاني) لا تجدها — عزل طبي.
      final r2 = medicalScopedRead(
        written['patientMedical'], 'محمد علي', 'الصفوة', '0922222222');
      expect(r2, anyOf(isNull, isEmpty),
          reason: 'طبية السميّ لا تُقرأ بهاتف سميّه');
    });

    test('خطة العلاج تتبع الهوية المفتوحة (هاتفها)', () {
      final repos = c.read(reposProvider);
      final tp = TreatmentPlanStore(repos.settings);
      tp.add('محمد علي', 'الصفوة', 'حشو العصب', phone: '0911111111');
      // هوية الهاتف الأول ترى مرحلتها.
      final s1 = tp.read('محمد علي', 'الصفوة', phone: '0911111111');
      expect(s1.map((s) => s.desc), contains('حشو العصب'));
      // السميّ (الهاتف الثاني) لا يرى خطة سميّه.
      final s2 = tp.read('محمد علي', 'الصفوة', phone: '0922222222');
      expect(s2.any((s) => s.desc == 'حشو العصب'), isFalse,
          reason: 'خطة السميّ معزولة بهاتفه');
    });

    test('رفع أشعة لهوية لا يظهر لسميّها (عزل المعرض + صف xrays)', () {
      final repos = c.read(reposProvider);
      // صفّ أشعة لكلّ سميّ (عبر المستودع، بهاتف كلٍّ منهما).
      repos.xrays.addXray('محمد علي', 'k_a',
          clinic: 'الصفوة', phone: '0911111111');
      repos.xrays.addXray('محمد علي', 'k_b',
          clinic: 'الصفوة', phone: '0922222222');

      // استعلام صفوف الهوية الأولى: k_a فقط.
      final rowsA = repos.xrays
          .getByClinicPatient('الصفوة', 'محمد علي', phone: '0911111111')
          .map((r) => r['id'])
          .toSet();
      expect(rowsA, contains('k_a'));
      expect(rowsA.contains('k_b'), isFalse,
          reason: 'صف أشعة السميّ لا يظهر لهوية غيره');

      final rowsB = repos.xrays
          .getByClinicPatient('الصفوة', 'محمد علي', phone: '0922222222')
          .map((r) => r['id'])
          .toSet();
      expect(rowsB, contains('k_b'));
      expect(rowsB.contains('k_a'), isFalse);
    });
  });
}

/// كتابة طبية موضعية (يُبقي الاختبار مستقلاً عن دالة الواجهة).
Map<String, Object?> _medWrite(
    String name, String clinic, String phone, Object? value) {
  // مفتاح الهوية «اسم|عيادة|هاتف» — توأم medicalScopedWrite.
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final key = digits.isEmpty ? '$name|$clinic' : '$name|$clinic|$digits';
  return {key: value};
}
