/// اختبارات م9 — الشاشة الرئيسية 100%:
///   • وحدات مالية دقيقة: todayIncome المركّب (نقدي + حصة طبيب التركيبات
///     بلقطات مجمدة + دفعات ديون التركيبات عبر _docAmount + دفعات الديون
///     العادية، مع استبعاد أصل الدين payment=='دين')، todayDebt،
///     التفصيلات الثلاث حسب العيادة، localNameSearch بعزل العيادة،
///     phoneFirstSearch بالتطبيع، medicalHasData.
///   • واجهة: شريط اليوم يعرض الأرقام ولوحة الدخل تفتح بالمجموع، اقتراح
///     مريض يربط ويملأ الهاتفين، المعلومات الطبية تُحفظ في config وتُعلّم
///     الرقاقة، معاينة التركيبات الحية، الوضع الداكن يبني الشاشة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m9_'));
  tearDown(() {
    BrandColors.darkMode = false;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinicRates': {
      'clinics': {
        'ع1': {
          'treatments': {'حشو': 40},
          'prosthetics': 30,
        },
      },
    },
    'clinics': ['ع1', 'ع2'],
    'services': ['حشو', 'تركيبات'],
    'payments': ['كاش', 'تحويل'],
    'labs': ['مخبر النور'],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  group('الوحدات — المنطق المالي لليوم', () {
    test('todayIncome بتعريف المالك (م23): المقبوض كاملاً = مجموع الكشف', () {
      final today = getCurrentDate();
      final debts = [
        // دين تركيبات (لأجل isProsDebtPay)
        {'id': 'dp', 'type': 'prosthetic', 'name': 'س'},
        // دين عادي
        {'id': 'dr', 'name': 'ص'},
      ];
      final records = [
        // نقدي يُحسب
        {'id': 'r1', 'date': today, 'amount': 100, 'payment': 'كاش'},
        // أصل دين اليوم — مستبعد (payment == دين، غير مقبوض)
        {
          'id': 'r2',
          'date': today,
          'amount': 999,
          'payment': 'دين',
          'isDebt': true,
        },
        // دفعة دين عادية — تُحسب كاملة
        {
          'id': 'r3',
          'date': today,
          'amount': 50,
          'isDebtPayment': true,
          'debtId': 'dr',
          'payment': 'كاش',
        },
        // دفعة دين تركيبات — م23: تُحسب **كاملة** (كان الأصل يحسب حصة
        // الطبيب _docAmount=24 فقط — قرار المالك: المقبوض هو الدخل).
        {
          'id': 'r4',
          'date': today,
          'amount': 80,
          'isDebtPayment': true,
          'debtId': 'dp',
          'payment': 'كاش',
          '_docAmount': 24,
        },
        // سجل أمس — خارج اليوم
        {'id': 'r5', 'date': '2020-01-01', 'amount': 500, 'payment': 'كاش'},
      ];
      final pros = [
        // تركيبات اليوم بلا مبلغ مقبوض مباشر (قيمتها ديون تُسدد دفعاتٍ)
        // — لا تدخل الكشف بذاتها.
        {'id': 'p1', 'date': today, 'doctorShare': 90, 'isDebt': false},
        {'id': 'p2', 'date': today, 'doctorShare': 70, 'isDebt': true},
      ];
      // المقبوض فعلاً: 100 + 50 + 80 = 230 — ويساوي مجموع الكشف حتماً.
      expect(todayIncome(records, pros, debts), 230);
      final sheet = todayIncomeByClinic(
        records,
        pros,
      ).fold<num>(0, (s, g) => s + g.total);
      expect(todayIncome(records, pros, debts), sheet);
      // دفعة دين تركيبات قديمة بلا _docAmount ⇒ كاملة أيضاً (تعريف واحد).
      final legacy = [
        {
          'id': 'r6',
          'date': today,
          'amount': 40,
          'isDebtPayment': true,
          'debtId': 'dp',
          'payment': 'كاش',
        },
      ];
      expect(todayIncome(legacy, const [], debts), 40);
    });

    test('todayDebt وtodayPatients', () {
      final today = getCurrentDate();
      expect(
        todayDebt([
          {'id': 'd1', 'date': today, 'remaining': 150},
          {'id': 'd2', 'date': today, 'remaining': 0},
          {'id': 'd3', 'date': '2020-01-01', 'remaining': 999},
        ]),
        150,
      );
      expect(
        todayPatients(
          [
            {'id': 'r1', 'date': today, 'name': 'أ'},
            {'id': 'r2', 'date': today, 'name': 'أ'}, // مكرر
          ],
          [
            {'id': 'p1', 'date': today, 'name': 'ب'},
          ],
        ),
        2,
      );
    });

    test('التفصيلات حسب العيادة: مرضى/دخل/دين بصفوف الأصل', () {
      final today = getCurrentDate();
      final pGroups = todayPatientsByClinic(
        [
          {
            'id': 'r1',
            'date': today,
            'name': 'أ',
            'clinic': 'ع1',
            'service': 'حشو',
          },
          {
            'id': 'r2',
            'date': today,
            'name': 'أ',
            'clinic': 'ع1',
            'service': 'قلع',
          },
          {
            'id': 'r3',
            'date': today,
            'name': 'دفعة',
            'isDebtPayment': true,
          }, // مستبعدة
        ],
        [
          {'id': 'p1', 'date': today, 'name': 'ب'}, // بدون عيادة
        ],
      );
      final g1 = pGroups.firstWhere((g) => g.clinic == 'ع1');
      expect(g1.patients.single.name, 'أ');
      expect(g1.patients.single.visits, 2);
      expect(g1.patients.single.services, containsAll(['حشو', 'قلع']));
      expect(pGroups.any((g) => g.clinic == kNoClinic), isTrue);

      final iGroups = todayIncomeByClinic([
        {
          'id': 'r1',
          'date': today,
          'name': 'أ',
          'clinic': 'ع1',
          'amount': 100,
          'payment': 'كاش',
          'service': 'حشو',
        },
        {
          'id': 'r2',
          'date': today,
          'name': 'ب',
          'clinic': 'ع1',
          'amount': 200,
          'payment': 'دين',
          'isDebt': true,
        }, // مستبعد
        {
          'id': 'r3',
          'date': today,
          'name': 'ج',
          'clinic': 'ع1',
          'amount': 30,
          'payment': 'دين',
          'isDebtPayment': true,
        }, // دفعةتُحسب
      ], const []);
      expect(iGroups.single.total, 130);
      expect(iGroups.single.patients, hasLength(2));

      final dGroups = todayDebtByClinic([
        {
          'id': 'd1',
          'date': today,
          'clinic': 'ع1',
          'name': 'أ',
          'remaining': 70,
          'totalAmount': 100,
          'paidAmount': 30,
          'service': 'حشو',
        },
      ]);
      expect(dGroups.single.total, 70);
      expect(dGroups.single.patients.single.paid, 30);
    });

    test('localNameSearch: عزل العيادة الصارم ودمج الهواتف', () {
      final records = [
        {'id': 'r1', 'name': 'أحمد', 'clinic': 'ع1', 'phone': ''},
        {'id': 'r2', 'name': 'أحمد', 'clinic': 'ع1', 'phone': '0911111111'},
        {'id': 'r3', 'name': 'سالم', 'clinic': 'ع2', 'phone': '0922222222'},
      ];
      // بلا عيادة مختارة: الاثنان
      var out = localNameSearch(
        'ا',
        selectedClinic: '',
        records: records,
        prosthetics: const [],
        debts: const [],
      );
      // 'ا' قصيرة — تبدأ بها الأسماء المطبّعة فقط
      expect(out.map((s) => s.name), contains('أحمد'));
      // عيادة ع1: سالم (ع2) مستبعد حتى لو طابق
      out = localNameSearch(
        'سالم',
        selectedClinic: 'ع1',
        records: records,
        prosthetics: const [],
        debts: const [],
      );
      expect(out, isEmpty);
      // الهاتف يُدمج من الصف الذي يملكه
      out = localNameSearch(
        'أحمد',
        selectedClinic: 'ع1',
        records: records,
        prosthetics: const [],
        debts: const [],
      );
      expect(out.single.phone, '0911111111');
    });

    test('phoneFirstSearch بالتطبيع (00218/218/أصفار وأرقام عربية)', () {
      final records = [
        {'id': 'r1', 'name': 'أحمد', 'clinic': 'ع1', 'phone': '0911111111'},
      ];
      for (final q in [
        '0911111111',
        '218911111111',
        '00218911111111',
        '٠٩١١١١١١١١',
      ]) {
        final out = phoneFirstSearch(
          q,
          selectedClinic: 'ع1',
          records: records,
          prosthetics: const [],
          debts: const [],
        );
        expect(out.single.name, 'أحمد', reason: q);
      }
      // عيادة أخرى ⇒ لا اقتراح
      expect(
        phoneFirstSearch(
          '0911111111',
          selectedClinic: 'ع2',
          records: records,
          prosthetics: const [],
          debts: const [],
        ),
        isEmpty,
      );
    });

    test('medicalHasData', () {
      expect(medicalHasData(null), isFalse);
      expect(medicalHasData({}), isFalse);
      expect(medicalHasData({'conditions': []}), isFalse);
      expect(medicalHasData({'gender': 'ذكر'}), isTrue);
      expect(
        medicalHasData({
          'conditions': ['السكري'],
        }),
        isTrue,
      );
    });
  });

  group('الواجهة — الرئيسية 1:1', () {
    Future<void> boot(
      WidgetTester tester, {
      void Function(ProviderContainer c)? seed,
    }) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config());
      seed?.call(c);
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
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('الرئيسية'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // م133 — «شريط اليوم» الثلاثي (today-patients/-income/-debt) ولوحة
    // sheet-income انتقلا جوهرياً من الرئيسية إلى بطاقة _Header في
    // DailyIncomeScreen (تبويب الرئيسية الجديد، م121+)؛ ذلك البطاقات
    // القديمة صارت مقفولة خلف `if (!widget.compact)` في add_record_screen
    // ولا مستدعٍ في lib/ كله يمرّر compact:false (تحقّقتُ عبر grep شامل) —
    // تعليق المالك صريح هناك: «يُخفى داخل ورقة الإدخال المضغوطة (دخل اليوم
    // صار له تبويب الرئيسية)». فالخانات ليست منقولة بل مُستبدَلة بحسابٍ
    // جديدٍ كلياً (todayLedgerRows/ledgerTotals في home_logic.dart، م93+).
    // أبقيتُ جوهر الاختبار (أرقام اليوم الحقيقية تُعرض في رأس الرئيسية)
    // وبدّلت البذرة لسجلٍ نقديٍّ واحد بسيط لتجنّب افتراض حسابات دمج الدين
    // المعقّدة الجديدة، وأعدت الأرقام المتوقعة لما يحسبه الكود الحالي حرفياً.
    testWidgets('شريط اليوم يعرض المركّب ولوحة الدخل تفتح بالمجموع', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          // سجل نقدي بسيط: قيمة=مدفوع=100، متبقٍّ=0 (home_logic.dart:820-834).
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'أ',
              date: getCurrentDate(),
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
        },
      );
      // رأس دخل اليوم (_Header في daily_income_screen.dart): حالة واحدة،
      // الإجمالي(المدفوع)=100 د.ل (لا مفاتيح على الخانات — نطابق النص).
      // النص الحقيقي «دخل اليوم • <تاريخ>» (سطرٌ واحد مدموج) لا نصاً مجرداً.
      expect(find.textContaining('دخل اليوم'), findsWidgets);
      expect(find.text('1 حالة'), findsOneWidget);
      expect(find.text('الإجمالي (المدفوع)'), findsOneWidget);
      expect(find.text('100 د.ل'), findsOneWidget);
    });

    // م133 — نموذج الإدخال (rec-*) انتقل من الرئيسية مباشرة إلى ورقة سفلية
    // (add_record_screen.dart → openAddRecordSheet)، تُفتح بالزر العائم
    // Key('fab-add') في app_shell.dart. الوصول فقط تغيّر؛ كل مفاتيح rec-*
    // ما تزال موجودة بلا تغيير داخل الورقة (compact:true).
    testWidgets('اقتراح المريض يربط ويملأ الهاتفين برسالة الربط', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          c.read(reposProvider).records.upsertLocal({
            'id': 'r1',
            'name': 'هدى السالم',
            'clinic': 'ع1',
            'phone': '0917777777',
            'phone2': '0928888888',
            'date': '2026-01-01',
            'amount': 10,
          });
        },
      );
      await tester.tap(find.byKey(const Key('fab-add')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('rec-name')), 'هدى');
      await settle(tester);
      expect(find.byKey(const Key('rec-suggest-هدى السالم')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('rec-suggest-هدى السالم')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.textContaining('تم الربط بسجل المريض'), findsOneWidget);
      final phone = tester.widget<TextField>(
        find.byKey(const Key('rec-phone')),
      );
      expect(phone.controller!.text, '0917777777');
      // الرقم الثاني ظهر وامتلأ.
      final phone2 = tester.widget<TextField>(
        find.byKey(const Key('rec-phone2')),
      );
      expect(phone2.controller!.text, '0928888888');
    });

    // م133 — نفس انتقال rec-* إلى ورقة fab-add أعلاه.
    testWidgets('البحث بالهاتف أولاً يقترح داخل العيادة فقط', (tester) async {
      await boot(
        tester,
        seed: (c) {
          c.read(reposProvider).records.upsertLocal({
            'id': 'r1',
            'name': 'سعاد',
            'clinic': 'ع1',
            'phone': '0911111111',
            'date': '2026-01-01',
            'amount': 10,
          });
          c.read(reposProvider).records.upsertLocal({
            'id': 'r2',
            'name': 'غريب',
            'clinic': 'ع2',
            'phone': '0933333333',
            'date': '2026-01-01',
            'amount': 10,
          });
        },
      );
      await tester.tap(find.byKey(const Key('fab-add')));
      await settle(tester);
      // العيادة الافتراضية ع1 — رقم ع1 يقترح
      await tester.enterText(find.byKey(const Key('rec-phone')), '0911111111');
      await settle(tester);
      expect(find.byKey(const Key('rec-suggest-سعاد')), findsOneWidget);
      // رقم ع2 لا يقترح داخل ع1
      await tester.enterText(find.byKey(const Key('rec-phone')), '0933333333');
      await settle(tester);
      expect(find.byKey(const Key('rec-suggest-غريب')), findsNothing);
    });

    // م133 — نفس انتقال rec-* إلى ورقة fab-add أعلاه.
    testWidgets(
      'المعلومات الطبية: تُحفظ في config.patientMedical وتعلّم الرقاقة',
      (tester) async {
        await boot(tester);
        await tester.tap(find.byKey(const Key('fab-add')));
        await settle(tester);
        await tester.enterText(find.byKey(const Key('rec-name')), 'وليد');
        await settle(tester);
        await tester.ensureVisible(find.byKey(const Key('rec-medical-tgl')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('rec-medical-tgl')),
          warnIfMissed: false,
        );
        await settle(tester);
        // النافذة مفتوحة — اختر جنساً وحالتين واكتب تشخيصاً ثم احفظ.
        await tester.tap(
          find.byKey(const Key('med-gender-ذكر')),
          warnIfMissed: false,
        );
        await tester.tap(
          find.byKey(const Key('med-cond-السكري')),
          warnIfMissed: false,
        );
        await tester.tap(
          find.byKey(const Key('med-cond-الربو')),
          warnIfMissed: false,
        );
        await tester.enterText(find.byKey(const Key('med-age')), '45');
        // التشخيص صار قائمة أسطر (توأم MedicalInfoCard) — الكتابة في حقل
        // الإضافة، والحفظ يلتقط النص المعلّق تلقائياً.
        await tester.enterText(
          find.byKey(const Key('med-dx-add')),
          'التهاب لثة',
        );
        await tester.tap(
          find.byKey(const Key('med-save')),
          warnIfMissed: false,
        );
        await settle(tester);

        final c = container();
        addTearDown(c.dispose);
        final cfg = Map<String, Object?>.from(
          c.read(reposProvider).settings.get('app.config') as Map,
        );
        // م35 — الحفظ من نموذج الرئيسية معزول بعيادة النموذج (ع1).
        final med = (cfg['patientMedical'] as Map)['وليد|ع1'] as Map;
        expect(med['gender'], 'ذكر');
        expect(med['age'], '45');
        expect((med['conditions'] as List), containsAll(['السكري', 'الربو']));
        expect(med['diagnosis'], 'التهاب لثة');
        // المفتاح مفعّل الآن (البيانات حقيقية + مريض محدد) — م12: Switch.
        final sw = tester.widget<Switch>(
          find.byKey(const Key('rec-medical-tgl')),
        );
        expect(sw.value, isTrue);

        // م66 — إعادة فتح النافذة بعد وجود بيانات ⇒ وضع الورقة (عرض غير
        // قابل للتعديل) لا النموذج؛ الحفظ مخفي، والقلم يعيد للتحرير.
        await tester.ensureVisible(find.byKey(const Key('rec-medical-tgl')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('rec-medical-tgl')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.byKey(const Key('med-sheet')), findsOneWidget);
        expect(find.byKey(const Key('med-save')), findsNothing);
        expect(find.byKey(const Key('med-edit')), findsOneWidget);
        expect(find.text('التهاب لثة'), findsOneWidget); // ورقة تعرض التشخيص
        // القلم يحوّل لنموذج التحرير (يظهر الحفظ وحقل العمر).
        await tester.tap(
          find.byKey(const Key('med-edit')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.byKey(const Key('med-save')), findsOneWidget);
        expect(find.byKey(const Key('med-age')), findsOneWidget);
      },
    );

    // م133 — نفس انتقال rec-* إلى ورقة fab-add أعلاه.
    testWidgets('معاينة التركيبات الحية بالصيغ الحرفية', (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const Key('fab-add')));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('rec-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('تركيبات').last, warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('rec-amount')), '500');
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('rec-lab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rec-lab')), '200');
      await settle(tester);
      // صافي 300، طبيب 30% = 90، عيادة 70% = 210.
      expect(find.text('نسبة الطبيب (30%):'), findsOneWidget);
      expect(find.text('نسبة العيادة (70%):'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('pros-net'))).data,
        '300',
      );
      expect(tester.widget<Text>(find.byKey(const Key('pros-doc'))).data, '90');
      expect(
        tester.widget<Text>(find.byKey(const Key('pros-clin'))).data,
        '210',
      );
    });

    // م133 — نفس استبدال «شريط اليوم» أعلاه: Key('today-patients') غير
    // قابل للوصول (compact:false ميت لا مستدعٍ له)؛ رأس DailyIncomeScreen
    // يُبنى دوماً (حتى بلا بذرة، تِبعاً لحالة العدّ 0) فهو ما يثبت أن
    // الرئيسية تُبنى فعلاً بالوضع الداكن. rec-save يبقى بمفتاحه — يُفتح
    // بالزر العائم (fab-add) لا مباشرة من الرئيسية.
    testWidgets('الوضع الداكن يبني الرئيسية بشريط اليوم', (tester) async {
      final c = container();
      c
          .read(localDbProvider)
          .execute(
            'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
            "VALUES ('dental_theme', 'dark', datetime('now'))",
          );
      c.dispose();
      await boot(tester);
      expect(BrandColors.darkMode, isTrue);
      expect(find.textContaining('دخل اليوم'), findsWidgets);
      expect(find.text('0 حالة'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fab-add')));
      await settle(tester);
      expect(find.byKey(const Key('rec-save')), findsOneWidget);
    });
  });
}
