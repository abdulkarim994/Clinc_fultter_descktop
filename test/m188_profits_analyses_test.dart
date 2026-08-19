/// اختبارات م188 — إيراد التحاليل الثلاثية إيرادٌ خاصٌّ بالعيادة.
///
/// طلب المالك: «التحاليل الثلاثية تحت المصروفات صفٌّ إضافي — إيرادها خاصٌّ
/// بالعيادة».
///
/// **التصحيح المُثبَت هنا قبل الإصلاح:** التحاليل لم تكن تُقسَم مع الطبيب
/// خطأً — بل كانت **غائبةً عن الأرباح كلها** نصّاً: شرط `isAnalysis` يستبعدها
/// في [getMonthRecs] (حارس الأرباح والأرشيف والخزينة) وفي [yearTotals]. فهذا
/// البند إظهارُ إيرادٍ مفقود، لا إصلاحُ قسمة. ولذلك يحرس أول اختبارٍ أدناه
/// أن الإيراد وحصة الطبيب **لا تتغيّران** بوجود التحاليل — وإلا لدخلت
/// قاعدة النِّسَب من حيث لا نريد.
///
/// العقد المحروس:
///     صافي ربح العيادة = حصة العيادة − المصروفات + التحاليل
///     وعند إطفاء النِّسَب: الإيراد − المختبرات − المصروفات + التحاليل
library;

import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';
import 'package:dental_clinic_flutter/features/finance/profits_tables.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

/// صفّ تحليلٍ (كما يكتبه الحافظ: علمٌ رقمي ومبلغٌ وطريقة دفع).
JMap anal({
  required String id,
  required String date,
  required num amount,
  String clinic = 'ع1',
  String? incomeDate,
}) => {
      'id': id,
      'isAnalysis': 1,
      'analysisName': 'التحاليل الثلاثية',
      'name': 'مريض $id',
      'date': date,
      'incomeDate': ?incomeDate,
      'clinic': clinic,
      'clinic_id': clinic,
      'amount': amount,
      'payment': 'كاش',
    };

/// سجل علاجٍ مقبوض عادي.
JMap rec({
  required String id,
  required String date,
  required num amount,
  String clinic = 'ع1',
  num doctorPct = 40,
}) => {
      'id': id,
      '_t': 'r',
      'date': date,
      'clinic': clinic,
      'clinic_id': clinic,
      'name': 'مريض $id',
      'amount': amount,
      'payment': 'كاش',
      'isDebt': 0,
      'isPros': 0,
      'isDebtPayment': 0,
      '_rateSnapshot': {'doctorPct': doctorPct},
    };

void main() {
  const month = '2026-08';
  const pct = 40;

  group('م188 — التحاليل لا تدخل الإيراد ولا حصة الطبيب', () {
    test('وجودها لا يغيّر إجمالي الشهر ولا الحصتين (الحارس الأهم)', () {
      final treat = [rec(id: 'r1', date: '$month-02', amount: 1000)];
      final withAnal = [
        ...treat,
        anal(id: 'a1', date: '$month-03', amount: 300),
      ];
      final a = getMonthlyReport(treat, const [], const [], month, pct);
      final b = getMonthlyReport(withAnal, const [], const [], month, pct);
      expect(b.grandTotal, a.grandTotal, reason: 'م188: لا تدخل الإيراد');
      expect(b.doctorTotal, a.doctorTotal, reason: 'م188: لا حصة للطبيب');
      expect(b.clinicTotal, a.clinicTotal,
          reason: 'حصة العيادة قبل الإضافة تبقى كما هي — الإضافة بالصافي');
    });

    test('إيراد التحاليل يُجمع للشهر بمنع تكرار المعرّف', () {
      final rows = [
        anal(id: 'a1', date: '$month-03', amount: 300),
        anal(id: 'a1', date: '$month-03', amount: 300), // مكرر بالمزامنة
        anal(id: 'a2', date: '$month-09', amount: 200),
        anal(id: 'a3', date: '2026-07-30', amount: 999), // شهرٌ آخر
      ];
      expect(analysesRevenue(rows, period: month), 500);
    });

    test('يوم الاحتساب: incomeDate يتقدّم على date', () {
      final rows = [
        // كُتب بتموز لكن قُبض بآب ⇒ إيراد آب.
        anal(
            id: 'a1',
            date: '2026-07-28',
            incomeDate: '$month-01',
            amount: 400),
      ];
      expect(analysesRevenue(rows, period: month), 400);
      expect(analysesRevenue(rows, period: '2026-07'), 0);
    });

    test('البادئة تصلح للسنة كما للشهر (دالةٌ واحدة)', () {
      final rows = [
        anal(id: 'a1', date: '2026-03-05', amount: 100),
        anal(id: 'a2', date: '2026-11-05', amount: 250),
        anal(id: 'a3', date: '2025-11-05', amount: 700), // سنةٌ أخرى
      ];
      expect(analysesRevenue(rows, period: '2026'), 350);
    });
  });

  group('م188 — العقد: صافي العيادة يُعاد جمعه بالتحاليل', () {
    test('الشهر: صافي = العيادة − المصروفات + التحاليل', () {
      final rows = [
        rec(id: 'r1', date: '2026-08-02', amount: 1000),
        anal(id: 'a1', date: '2026-08-03', amount: 300),
      ];
      final rep = yearReport('2026',
          records: rows,
          prosthetics: const [],
          debts: const [],
          doctorPct: pct,
          expensesOf: (m) => m == '2026-08' ? 200 : 0);
      final aug = rep.months[7];
      expect(aug.analyses, 300);
      expect(aug.clinic, 600); // 1000 − 400 حصة الطبيب
      expect(aug.net, 700, reason: '600 − 200 + 300');
      expect(aug.net, aug.clinic - aug.expenses + aug.analyses);
      // وفرع إطفاء النِّسَب: الإيراد − المعمل − المصروفات + التحاليل.
      expect(aug.netOff, 1100, reason: '1000 − 0 − 200 + 300');
    });

    test('السنة: تحاليلها مجموع أشهرها والصافي يوافق', () {
      final rows = [
        rec(id: 'r1', date: '2026-03-02', amount: 1000),
        anal(id: 'a1', date: '2026-03-03', amount: 300),
        anal(id: 'a2', date: '2026-09-03', amount: 250),
      ];
      final rep = yearReport('2026',
          records: rows,
          prosthetics: const [],
          debts: const [],
          doctorPct: pct);
      expect(rep.analyses, 550);
      expect(rep.months[2].analyses, 300);
      expect(rep.months[8].analyses, 250);
      expect(rep.net, rep.clinic - rep.expenses + rep.analyses);
      // مجموع صافيات الأشهر = صافي السنة (لا انجراف ولا إغفال).
      num sumNet = 0;
      for (final m in rep.months) {
        sumNet += m.net;
      }
      expect(sumNet, rep.net);
      num sumOff = 0;
      for (final m in rep.months) {
        sumOff += m.netOff;
      }
      expect(sumOff, rep.netOff,
          reason: 'م188: فرع إطفاء النِّسَب كان يُغفل المعمل بصفوف الأشهر '
              'فما طابق سطر السنة — أُصلح');
    });

    test('شهرٌ لا فيه إلا تحاليل ليس فارغاً (وإلا بَهَتَ وصافيه رقم)', () {
      final rep = yearReport('2026',
          records: [anal(id: 'a1', date: '2026-05-03', amount: 120)],
          prosthetics: const [],
          debts: const [],
          doctorPct: pct);
      final may = rep.months[4];
      expect(may.isEmpty, isFalse);
      expect(may.net, 120);
      expect(rep.months[3].isEmpty, isTrue, reason: 'نيسان بلا شيء');
    });

    test('بلا تحاليل: كل الأرقام كما كانت قبل م188 (لا انحدار)', () {
      final rows = [rec(id: 'r1', date: '2026-08-02', amount: 1000)];
      final rep = yearReport('2026',
          records: rows,
          prosthetics: const [],
          debts: const [],
          doctorPct: pct,
          expensesOf: (m) => m == '2026-08' ? 200 : 0);
      expect(rep.analyses, 0);
      expect(rep.net, rep.clinic - rep.expenses);
      expect(rep.months[7].net, 400); // 600 − 200
    });
  });

  group('م188 — الصفّ في جدول الإجمالي العام', () {
    Future<void> pumpGrand(
      WidgetTester t, {
      required num analyses,
      bool showDoctor = true,
    }) async {
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ProfitsGrandTable(
                revenue: 1400,
                doctor: 700,
                clinic: 700,
                expenses: 100,
                analyses: analyses,
                showDoctor: showDoctor,
              ),
            ),
          ),
        ),
      ));
      await t.pump();
    }

    String txt(WidgetTester t, String k) =>
        t.widget<Text>(find.byKey(Key(k))).data!;

    testWidgets('صفٌّ تحت المصروفات، وصافي العيادة يُعاد جمعه',
        (t) async {
      await pumpGrand(t, analyses: 300);
      expect(txt(t, 'prof-grand-exp'), '100');
      expect(txt(t, 'prof-grand-analyses'), '300');
      expect(txt(t, 'prof-grand-clinic-net'), '900',
          reason: '700 − 100 + 300');
      // الترتيب رأسياً: المصروفات ثم التحاليل ثم الصافي (طلب المالك).
      final yExp = t.getCenter(find.byKey(const Key('prof-grand-exp'))).dy;
      final yAna =
          t.getCenter(find.byKey(const Key('prof-grand-analyses'))).dy;
      final yNet =
          t.getCenter(find.byKey(const Key('prof-grand-clinic-net'))).dy;
      expect(yExp, lessThan(yAna));
      expect(yAna, lessThan(yNet));
      // وقيمته تحت عمود «ربح العيادة» هندسياً — كالمصروفات.
      final xClinic =
          t.getCenter(find.byKey(const Key('prof-grand-clinic'))).dx;
      final xAna =
          t.getCenter(find.byKey(const Key('prof-grand-analyses'))).dx;
      expect((xClinic - xAna).abs(), lessThan(1.0));
      // ولا حصة للطبيب في هذا الصفّ: خليته شرطة.
      expect(find.text('إيراد التحاليل (+)'), findsOneWidget);
    });

    testWidgets('صفرٌ ⇒ لا صفّ إطلاقاً (الجدول كما كان)', (t) async {
      await pumpGrand(t, analyses: 0);
      expect(find.byKey(const Key('prof-grand-analyses-row')), findsNothing);
      expect(txt(t, 'prof-grand-clinic-net'), '600');
    });

    testWidgets('النِّسَب مطفأة: الصفّ حاضر والصافي يجمعه', (t) async {
      await pumpGrand(t, analyses: 300, showDoctor: false);
      expect(txt(t, 'prof-grand-analyses'), '300');
      expect(txt(t, 'prof-grand-clinic-net'), '1,600',
          reason: '1400 − 0 معمل − 100 + 300');
    });
  });
}
