/// اختبارات م10-أ/ب — قسم السجلات (البوابة + مرضى العيادة):
///   • وحدات: recordAmount، buildPatientMap (استبدال الدين المرتبط
///     بالمدفوع، الدين غير المرتبط زيارة بمدفوعه، أرصدة المخابر،
///     النشاط السريري)، clinicCards (استبعاد المرتبط بدين + دفعات
///     الشهر + الديون المعلقة)، البحث الشامل بوضعيه، فرز مرضى العيادة.
///   • واجهة: البوابة تعرض بطاقات العيادات بأرقامها وفتح عيادة يعرض
///     صفوف المرضى بشاراتهم، البحث الشامل يفتح الملف، تعديل بيانات
///     المريض يكتسح الجداول، زيارة جديدة تقفز للرئيسية مربوطة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/features/patients/profile_actions.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m10_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  Future<void> boot2(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seed,
  }) async {
    final c = container();
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'تركيبات'],
      'payments': ['كاش'],
      'clinicRates': {
        'clinics': {
          'ع1': {
            'treatments': {'حشو': 40},
            'prosthetics': 30,
          },
        },
      },
    });
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
    // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('الوحدات — منطق قسم السجلات', () {
    test('recordAmount يوحّد amount/total/totalAmount', () {
      expect(recordAmount({'amount': 100}), 100);
      expect(recordAmount({'total': 250}), 250);
      expect(recordAmount({'totalAmount': 70}), 70);
      expect(recordAmount({'amount': null, 'total': 30}), 30);
      expect(recordAmount({}), 0);
      expect(recordAmount(null), 0);
    });

    test(
      'buildPatientMap: الدين المرتبط يستبدل بالمدفوع وغير المرتبط زيارة',
      () {
        final recs = [
          // نقدي عادي
          {
            'id': 'r1',
            'name': 'أ',
            'amount': 100,
            'date': '2026-07-01',
            'service': 'حشو',
            '_mod': 5,
          },
          // أصل دين مرتبط (يُستبدل مبلغه بمدفوع دينه 40)
          {
            'id': 'r2',
            'name': 'أ',
            'amount': 300,
            'date': '2026-07-02',
            'isDebt': true,
          },
          // دفعة دين — لا تُحسب (محسوبة في paidAmount)
          {
            'id': 'r3',
            'name': 'أ',
            'amount': 40,
            'isDebtPayment': true,
            'date': '2026-07-03',
          },
        ];
        final debts = [
          {
            'id': 'd1',
            'name': 'أ',
            'recordId': 'r2',
            'paidAmount': 40,
            'totalAmount': 300,
            'remaining': 260,
            'status': 'partial',
          },
          // دين غير مرتبط (قديم) — زيارة بمدفوعه 20
          {
            'id': 'd2',
            'name': 'أ',
            'paidAmount': 20,
            'totalAmount': 90,
            'remaining': 70,
            'status': 'partial',
            'date': '2026-07-04',
            'service': 'قلع',
            'type': 'prosthetic',
            'labValue': 30,
            'labPaid': 10,
          },
        ];
        final map = buildPatientMap(recs, const [], debts);
        final a = map['أ']!;
        // زيارات: r1 + r2 + d2 (الدفعة لا) = 3
        expect(a.visitCount, 3);
        // المحصَّل: 100 + 40 (مدفوع المرتبط) + 20 (مدفوع غير المرتبط) = 160
        expect(a.total, 160);
        // الكلي: 100 + 300 + 90 = 490
        expect(a.grossTotal, 490);
        expect(a.debtTotal, 390);
        expect(a.debtRemaining, 330);
        expect(a.labTotal, 30);
        expect(a.labPaid, 10);
        expect(a.lastDate, '2026-07-04');
        expect(a.services, containsAll(['حشو', 'قلع']));
      },
    );

    test('clinicCards: استبعاد المرتبط بدين + دفعات الشهر + المعلقة', () {
      final month = '2026-07';
      final records = [
        {
          'id': 'r1',
          'name': 'أ',
          'clinic': 'ع1',
          'amount': 100,
          'date': '2026-07-01',
        },
        // مرتبط بدين — يُستبعد من الدخل
        {
          'id': 'r2',
          'name': 'ب',
          'clinic': 'ع1',
          'amount': 500,
          'date': '2026-07-02',
          'isDebt': true,
        },
        // دفعة دين هذا الشهر — تُضاف
        {
          'id': 'r3',
          'name': 'ب',
          'clinic': 'ع1',
          'amount': 60,
          'date': '2026-07-03',
          'isDebtPayment': true,
        },
        // شهر آخر
        {
          'id': 'r4',
          'name': 'ج',
          'clinic': 'ع1',
          'amount': 999,
          'date': '2026-06-01',
        },
      ];
      final pros = [
        // تركيبة بلا دين — recordAmount(total) تدخل
        {
          'id': 'p1',
          'name': 'د',
          'clinic': 'ع1',
          'total': 200,
          'date': '2026-07-05',
        },
      ];
      final debts = [
        {
          'id': 'd1',
          'name': 'ب',
          'clinic': 'ع1',
          'recordId': 'r2',
          'status': 'partial',
        },
        {'id': 'd2', 'name': 'هـ', 'clinic': 'ع1', 'status': 'paid'},
      ];
      final cards = clinicCards(
        clinics: ['ع1'],
        month: month,
        records: records,
        prosthetics: pros,
        debts: debts,
      );
      final c = cards.single;
      // مرضى الشهر الفريدون: أ، ب، د (r4 خارج الشهر، r3 دفعة مستبعدة)
      expect(c.patientCount, 3);
      expect(c.visitCount, 3); // r1 + r2 + p1
      // الدخل: 100 + 200 (تركيبة) + 60 (دفعة) — r2 مستبعد
      expect(c.income, 360);
      expect(c.debtCount, 1); // d1 فقط (d2 مسدد)
    });

    test('البحث الشامل: اسم مرتب بالدقة أو هاتف بالأرقام وحد 15', () {
      final map = buildPatientMap(
        [
          {
            'id': 'r1',
            'name': 'سالم أحمد',
            'clinic': 'ع1',
            'phone': '0911111111',
            'date': '2026-07-01',
            'amount': 5,
          },
          {
            'id': 'r2',
            'name': 'أحمد سالم',
            'clinic': 'ع2',
            'phone': '0922222222',
            'date': '2026-07-01',
            'amount': 5,
          },
        ],
        const [],
        const [],
      );
      // «أحمد» بادئة للثاني (score 1) واحتواء للأول (score 2)
      final byName = landingSearchResults(
        'أحمد',
        patientMap: map,
        phoneMode: false,
      );
      expect(byName.first.agg.name, 'أحمد سالم');
      expect(byName, hasLength(2));
      expect(byName.first.clinic, 'ع2');
      // وضع الهاتف
      final byPhone = landingSearchResults(
        '0911',
        patientMap: map,
        phoneMode: true,
      );
      expect(byPhone.single.agg.name, 'سالم أحمد');
    });

    test('فرز مرضى العيادة الخمسة وشاراتهم', () {
      final records = [
        {
          'id': 'r1',
          'name': 'أ',
          'clinic': 'ع1',
          'amount': 50,
          'date': '2026-07-01',
          '_activityAt': 100,
        },
        {
          'id': 'r2',
          'name': 'ب',
          'clinic': 'ع1',
          'amount': 300,
          'date': '2026-07-05',
          '_activityAt': 50,
          'report': {
            'entries': [
              {'tooth': 'UR:1'},
            ],
          },
        },
      ];
      final pros = [
        {
          'id': 'p1',
          'name': 'ب',
          'clinic': 'ع1',
          'total': 100,
          'date': '2026-07-02',
        },
      ];
      final debts = [
        {
          'id': 'd1',
          'name': 'أ',
          'clinic': 'ع1',
          'status': 'partial',
          'remaining': 20,
          'totalAmount': 20,
        },
      ];
      final map = buildPatientMap(records, pros, debts);
      final rows = clinicPatients(
        'ع1',
        patientMap: map,
        records: records,
        prosthetics: pros,
        debts: debts,
      );
      final a = rows.firstWhere((p) => p.agg.name == 'أ');
      final b = rows.firstWhere((p) => p.agg.name == 'ب');
      expect(a.hasDebt, isTrue);
      expect(b.hasDebt, isFalse);
      expect(b.hasPros, isTrue);
      expect(b.hasReport, isTrue);

      // الفرز: بالمبلغ ب أولاً (400) ثم أ
      var out = filterClinicPatients(
        rows,
        query: '',
        phoneMode: false,
        sortBy: 'amount',
      );
      expect(out.first.agg.name, 'ب');
      // بالنشاط: بديل التاريخ لتركيبة ب (07-02) يتغلب على طوابع
      // صغيرة — سلوك حرفي (النشاط الأحدث زمنياً يفوز).
      out = filterClinicPatients(
        rows,
        query: '',
        phoneMode: false,
        sortBy: 'activity',
      );
      expect(out.first.agg.name, 'ب');
      // بآخر زيارة: ب (07-05)
      out = filterClinicPatients(
        rows,
        query: '',
        phoneMode: false,
        sortBy: 'date',
      );
      expect(out.first.agg.name, 'ب');
    });
  });

  group('الواجهة — البوابة ومرضى العيادة', () {
    Future<void> boot(
      WidgetTester tester, {
      void Function(ProviderContainer c)? seed,
    }) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1', 'ع2'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش'],
      });
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
      // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void seedData(ProviderContainer c) {
      final repos = c.read(reposProvider);
      final month = getCurrentDate().substring(0, 7);
      repos.records.bulkUpsert([
        {
          'id': 'r1',
          'name': 'أحمد',
          'patient_name': 'أحمد',
          'clinic': 'ع1',
          'amount': 100,
          'date': '$month-01',
          'service': 'حشو',
          'payment': 'كاش',
          'phone': '0911111111',
        },
        {
          'id': 'r2',
          'name': 'سعاد',
          'patient_name': 'سعاد',
          'clinic': 'ع1',
          'amount': 200,
          'date': '$month-02',
          'service': 'حشو',
          'payment': 'كاش',
        },
      ]);
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'سعاد',
        'clinic': 'ع1',
        'status': 'partial',
        'remaining': 50,
        'totalAmount': 80,
        'paidAmount': 30,
        'date': '$month-02',
      });
    }

    testWidgets('البوابة: بطاقة العيادة بأرقامها وفتحها يعرض الصفوف', (
      tester,
    ) async {
      await boot(tester, seed: seedData);
      // بطاقة ع1: مريضان، الدخل 100+200+... (د1 غير مرتبط بسجل ⇒ لا
      // استبعاد) + لا دفعات = 300.
      // م133 — شارة «دين معلق» على بطاقة العيادة (clinic-debt-*) حُذفت
      // نهائياً بقرار المالك (م125، patients_tab.dart): لا مكافئ لها بعد
      // الآن، فحُذف التوقّع بدل تبديل مفتاح.
      expect(find.byKey(const Key('clinic-card-ع1')), findsOneWidget);
      expect(find.text('300'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clinic-card-ع1')));
      await settle(tester);
      expect(find.byKey(const Key('patient-card-أحمد')), findsOneWidget);
      expect(find.byKey(const Key('patient-card-سعاد')), findsOneWidget);
      // م64/v59 — فلتر الدين صار داخل قائمة قمع الأدوات الموحد:
      // فتح القمع ← «عليه دين/متبقٍ فقط» يقصر القائمة على سعاد.
      expect(find.byKey(const Key('cp-tools')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cp-tools')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('cp-filter-debt')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('patient-card-سعاد')), findsOneWidget);
      expect(find.byKey(const Key('patient-card-أحمد')), findsNothing);
      // إلغاء الفلتر (من القائمة نفسها) يعيد الجميع.
      await tester.tap(find.byKey(const Key('cp-tools')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('cp-filter-debt')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('patient-card-أحمد')), findsOneWidget);
      // العودة للبوابة.
      await tester.tap(find.byKey(const Key('clinic-back')));
      await settle(tester);
      expect(find.byKey(const Key('clinic-card-ع1')), findsOneWidget);
    });

    testWidgets('البحث الشامل من البوابة يفتح ملف المريض', (tester) async {
      await boot(tester, seed: seedData);
      await tester.enterText(find.byKey(const Key('patient-search')), 'أحمد');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-أحمد')),
        warnIfMissed: false,
      );
      await settle(tester);
      // الملف مفتوح (رأس الملف باسم المريض).
      expect(find.text('أحمد'), findsWidgets);
      expect(find.textContaining('السجلات (1)'), findsOneWidget);
    });

    testWidgets('تعديل بيانات المريض يكتسح الجداول ويعيد التسمية', (
      tester,
    ) async {
      await boot(tester, seed: seedData);
      await tester.tap(find.byKey(const Key('clinic-card-ع1')));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-more-سعاد')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('act-edit-سعاد')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('edit-pat-name')),
        'سعاد الهادي',
      );
      await tester.enterText(
        find.byKey(const Key('edit-pat-phone')),
        '0925555555',
      );
      await tester.tap(
        find.byKey(const Key('edit-pat-save')),
        warnIfMissed: false,
      );
      await settle(tester);

      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      expect(repos.records.getById('r2')!['name'], 'سعاد الهادي');
      expect(repos.records.getById('r2')!['phone'], '0925555555');
      expect(repos.debts.getById('d1')!['name'], 'سعاد الهادي');
      // الصف المعروض تحدّث.
      expect(find.byKey(const Key('patient-card-سعاد الهادي')), findsOneWidget);
    });

    testWidgets(
      'م58: زيارة جديدة تفتح ورقة سريعة، والخيارات الكاملة تقفز للرئيسية مربوطة',
      (tester) async {
        await boot(tester, seed: seedData);
        await tester.tap(find.byKey(const Key('clinic-card-ع1')));
        await settle(tester);
        await tester.tap(
          find.byKey(const Key('patient-more-أحمد')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.tap(
          find.byKey(const Key('act-visit-أحمد')),
          warnIfMissed: false,
        );
        await settle(tester);
        // م58 — ورقة الزيارة السريعة بهوية المريض (لا مغادرة للقائمة).
        expect(find.text('زيارة جديدة — أحمد'), findsOneWidget);
        expect(find.byKey(const Key('qv-save')), findsOneWidget);
        // «الخيارات الكاملة» تسلك المسار القديم: الرئيسية باسم وهاتف
        // معبأين (توأم query {patient, clinic}).
        await tester.tap(
          find.byKey(const Key('qv-full-options')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.byKey(const Key('rec-save')), findsOneWidget);
        final nameField = tester.widget<TextField>(
          find.byKey(const Key('rec-name')),
        );
        expect(nameField.controller!.text, 'أحمد');
        final phoneField = tester.widget<TextField>(
          find.byKey(const Key('rec-phone')),
        );
        expect(phoneField.controller!.text, '0911111111');
      },
    );
  });

  group('م10-ج — ملف المريض', () {
    test('patientForClinic يعزل وtreatmentCards تجمع حرفياً', () {
      final records = [
        {
          'id': 'r1',
          'name': 'أ',
          'clinic': 'ع1',
          'amount': 100,
          'date': '2026-07-01',
          'service': 'حشو',
        },
        {
          'id': 'r2',
          'name': 'أ',
          'clinic': 'ع2',
          'amount': 999,
          'date': '2026-07-01',
          'service': 'حشو',
        },
        // أصل دين مرتبط بدين مدفوعه 30
        {
          'id': 'r3',
          'name': 'أ',
          'clinic': 'ع1',
          'amount': 200,
          'date': '2026-07-02',
          'service': 'قلع',
          'isDebt': true,
        },
      ];
      final pros = [
        {
          'id': 'p1',
          'name': 'أ',
          'clinic': 'ع1',
          'total': 500,
          'labValue': 150,
          'doctorShare': 105,
          'clinicShare': 245,
          'date': '2026-07-03',
        },
      ];
      final debts = [
        {
          'id': 'd1',
          'name': 'أ',
          'clinic': 'ع1',
          'recordId': 'r3',
          'paidAmount': 30,
          'totalAmount': 200,
          'remaining': 170,
          'status': 'partial',
        },
      ];
      final agg = patientForClinic(
        'أ',
        'ع1',
        records: records,
        prosthetics: pros,
        debts: debts,
      )!;
      // العزل: r2 (ع2) خارج الحساب.
      expect(agg.grossTotal, 100 + 200 + 500);
      expect(agg.total, 100 + 30 + 500);

      final cards = treatmentCards(
        patient: agg,
        patientName: 'أ',
        clinic: 'ع1',
        prosthetics: pros,
        debts: debts,
      );
      // ثلاث مجموعات: تركيبات (مدفوع 500)، حشو (100)، قلع (30) —
      // مرتبة تنازلياً بالمدفوع.
      expect(cards.map((c) => c.service).toList(), ['تركيبات', 'حشو', 'قلع']);
      expect(cards[0].paidTotal, 500);
      expect(cards[2].paidTotal, 30);
      expect(cards[2].grossTotal, 200);
      // سجل التركيبة يحمل حصصه المجمدة.
      expect(cards[0].records.single.doctorShare, 105);
    });

    test('حذف سجل دفعة يعكسها على الدين (المبالغ والحالة والقسط)', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', {
        'clinics': ['ع1'],
        'clinicRates': {
          'clinics': {
            'ع1': {'treatments': {}, 'prosthetics': 30},
          },
        },
      });
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'أ',
        'clinic': 'ع1',
        'type': 'prosthetic',
        'totalAmount': 500,
        'paidAmount': 200,
        'remaining': 300,
        'status': 'partial',
        'labValue': 150,
        'labPaid': 150,
        'doctorEarned': 15,
        'installments': [
          {'recordId': 'pay1', 'date': '2026-07-01', 'amount': 200},
        ],
      });
      repos.records.upsertLocal({
        'id': 'pay1',
        'name': 'أ',
        'clinic': 'ع1',
        'amount': 200,
        'date': '2026-07-01',
        'isDebtPayment': true,
        'debtId': 'd1',
        'payment': 'كاش',
      });

      deleteEntryCascade(
        repos,
        repos.settings.get('app.config') as Map<String, Object?>,
        id: 'pay1',
        source: 'r',
      );

      expect(repos.records.getById('pay1'), isNull);
      final d = repos.debts.getById('d1')!;
      expect(jsNumOr0(d['paidAmount']), 0);
      expect(jsNumOr0(d['remaining']), 500);
      expect(d['status'], 'unpaid');
      expect(jsNumOr0(d['labPaid']), 0);
      expect(jsNumOr0(d['doctorEarned']), 0);
      expect((d['installments'] as List), isEmpty);
    });

    test('حذف أصل دين يحذف دينه وكل دفعاته', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', {
        'clinics': ['ع1'],
      });
      repos.records.upsertLocal({
        'id': 'r1',
        'name': 'أ',
        'clinic': 'ع1',
        'amount': 300,
        'date': '2026-07-01',
        'isDebt': true,
        'payment': 'دين',
      });
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'أ',
        'recordId': 'r1',
        'totalAmount': 300,
        'paidAmount': 50,
        'remaining': 250,
        'status': 'partial',
      });
      repos.records.upsertLocal({
        'id': 'pay1',
        'name': 'أ',
        'amount': 50,
        'isDebtPayment': true,
        'debtId': 'd1',
        'date': '2026-07-02',
      });
      deleteEntryCascade(repos, const {}, id: 'r1', source: 'r');
      expect(repos.records.getById('r1'), isNull);
      expect(repos.records.getById('pay1'), isNull);
      expect(repos.debts.getById('d1'), isNull);
    });

    testWidgets('الملف: الثلاثي وبطاقات المعالجات والتبويبات والحذف', (
      tester,
    ) async {
      await boot2(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          repos.records.bulkUpsert([
            {
              'id': 'r1',
              'name': 'أحمد',
              'patient_name': 'أحمد',
              'clinic': 'ع1',
              'amount': 100,
              'date': '2026-07-01',
              'service': 'حشو',
              'payment': 'كاش',
            },
          ]);
          repos.debts.upsertLocal({
            'id': 'd1',
            'name': 'أحمد',
            'patient_name': 'أحمد',
            'clinic': 'ع1',
            'totalAmount': 80,
            'paidAmount': 20,
            'remaining': 60,
            'status': 'partial',
            'date': '2026-07-02',
            'service': 'قلع',
          });
        },
      );
      await tester.enterText(find.byKey(const Key('patient-search')), 'أحمد');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('patient-card-أحمد')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // م65 — بطاقة الملخص مطوية افتراضياً: الخلاصة المضغوطة تعرض
      // الأرقام، والتوسيع يظهر الثلاثي الكامل وبطاقات المعالجات.
      expect(find.byKey(const Key('pp-summary-toggle')), findsOneWidget);
      expect(find.text('180'), findsOneWidget); // في الخلاصة المضغوطة
      await tester.tap(
        find.byKey(const Key('pp-summary-toggle')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // الثلاثي: الإجمالي 180 (100 + دين غير مرتبط 80)، المدفوع 120،
      // الديون 60.
      expect(find.byKey(const Key('pp-total')), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);

      // بطاقة معالجة واحدة: حشو (100) — الدين غير المرتبط بسجل لا
      // يولّد بطاقة (حرفية الأصل: البطاقات من القيود لا الديون).
      expect(find.byKey(const Key('tc-card-حشو')), findsOneWidget);
      expect(find.byKey(const Key('tc-card-قلع')), findsNothing);
      // نافذة التفصيل.
      await tester.tap(
        find.byKey(const Key('tc-card-حشو')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('tc-detail-حشو')), findsOneWidget);
      await tester.tap(find.text('إغلاق'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // التبويبات: الديون تعرض الدين.
      await tester.tap(
        find.byKey(const Key('psec-debts')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // م43 — بطاقة الدين الجديدة: خلية «المتبقي» + قيمتها المنسقة.
      expect(find.text('المتبقي'), findsWidgets);
      expect(find.text('60'), findsWidgets);

      // عودة للزيارات وحذف السجل بعداد dcConfirm.
      await tester.tap(
        find.byKey(const Key('psec-visits')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // v48 — البطاقات الموحدة صارت أطول: نطوي الملخص كي لا يسكن ⋮
      // البطاقة الأولى تحت الدائرة العائمة على شاشة الاختبار (600px).
      await tester.tap(
        find.byKey(const Key('pp-summary-toggle')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // الحذف عبر قائمة ⋮ للبطاقة (م11).
      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rr-del-0')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(
        find.byKey(const Key('dc-confirm')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final chk = container();
      addTearDown(chk.dispose);
      expect(chk.read(reposProvider).records.getById('r1'), isNull);
    });

    testWidgets('تعديل قيمة تركيبة يعيد الحصص من اللقطة المجمدة', (
      tester,
    ) async {
      await boot2(
        tester,
        seed: (c) {
          c.read(reposProvider).prosthetics.upsertLocal({
            'id': 'p1',
            'name': 'سالم',
            'patient_name': 'سالم',
            'clinic': 'ع1',
            'total': 500,
            'labValue': 200,
            'doctorShare': 90,
            'clinicShare': 210,
            'date': '2026-07-01',
            'payment': 'كاش',
            '_rateSnapshot': {'doctorPct': 30},
          });
        },
      );
      await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('patient-card-سالم')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('rr-edit-0')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(const Key('edit-amount-input')), '600');
      await tester.enterText(find.byKey(const Key('edit-lab-input')), '100');
      await tester.tap(
        find.byKey(const Key('edit-amount-save')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final c2 = container();
      addTearDown(c2.dispose);
      final p = c2.read(reposProvider).prosthetics.getById('p1')!;
      expect(jsNumOr0(p['total']), 600);
      expect(jsNumOr0(p['labValue']), 100);
      // صافي 500 × 30% لقطة = 150 طبيب / 350 عيادة.
      expect(jsNumOr0(p['doctorShare']), 150);
      expect(jsNumOr0(p['clinicShare']), 350);
    });
  });
}
