/// اختبارات م190 — جدول الأرباح والخسائر السنوي بعد إعادة التصميم،
/// وتناظرُ أعمدة سجل التحاليل وفتحُ ملف المريض منه.
///
/// طلب المالك: «الجدول يقرأ كقصّة»: الإيراد ← المختبرات ← صافيها ←
/// الحصّتان ← المصروفات ← التحاليل ← **صافي إيراد العيادة** آخِراً مظلَّلاً؛
/// وحذفُ الأسطر الثلاثة التي كانت تحت الجدول لأنها صارت أعمدة. وللهاتف
/// جدولٌ مختصر (إيرادٌ بعد المختبرات، بلا عمود مصروفات، وصافٍ شامل) مع
/// علامةِ توضيحٍ وأيقونةِ تكبير.
///
/// العقد المحروس هنا: **ما تعرضه الأعمدة يساوي ما يعرضه الصفّ الأخير**،
/// فلا يقرأ المالك رقمين متخالفين لنفس المعنى في جدولٍ واحد.
library;

import 'package:dental_clinic_flutter/features/finance/profits_logic.dart';
import 'package:dental_clinic_flutter/features/finance/profits_tables.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

const _pct = 50;

/// تركيبة بقيمة معمل (الحصص مجمّدة كما يكتبها الحافظ).
JMap pros({
  required String id,
  required String date,
  required num total,
  required num lab,
}) {
  final net = total - lab;
  final doc = (net * _pct / 100).round();
  return {
    'id': id,
    '_t': 'p',
    'date': date,
    'clinic': 'ع1',
    'clinic_id': 'ع1',
    'name': 'مريض $id',
    'total': total,
    'labValue': lab,
    'doctorShare': doc,
    'clinicShare': net - doc,
    'payment': 'كاش',
    'isDebt': 0,
    '_rateSnapshot': {'doctorPct': _pct},
  };
}

JMap anal({required String id, required String date, required num amount}) => {
      'id': id,
      'isAnalysis': 1,
      'analysisName': 'التحاليل الثلاثية',
      'name': 'مريض $id',
      'date': date,
      'clinic': 'ع1',
      'clinic_id': 'ع1',
      'amount': amount,
      'payment': 'كاش',
    };

YearReport buildReport({bool withLab = true, bool withAnal = true}) =>
    yearReport('2026',
        records: [
          if (withAnal) anal(id: 'a1', date: '2026-08-03', amount: 300),
        ],
        prosthetics: [
          if (withLab) pros(id: 'p1', date: '2026-08-05', total: 3000, lab: 1200),
        ],
        debts: const [],
        doctorPct: _pct,
        expensesOf: (m) => m == '2026-08' ? 200 : 0);

Future<void> pumpTable(
  WidgetTester t, {
  required YearReport rep,
  bool full = true,
  double width = 1000,
}) async {
  await t.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: YearPnlTable(report: rep, full: full, dense: !full),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

String txt(WidgetTester t, String k) =>
    t.widget<Text>(find.byKey(Key(k))).data!;

void main() {
  group('م190 — الجدول الكامل (الكمبيوتر)', () {
    testWidgets('الأعمدة التسعة بالترتيب المطلوب', (t) async {
      await pumpTable(t, rep: buildReport());
      for (final h in [
        'الشهر',
        'الإيراد',
        'المختبرات',
        'بعد المختبرات',
        'الطبيب',
        'العيادة',
        'المصروفات',
        'التحاليل',
        'صافي العيادة',
      ]) {
        expect(find.text(h), findsOneWidget, reason: 'العمود «$h» غائب');
      }
      // الترتيب أفقياً (RTL): الإيراد يمين المختبرات، والصافي أقصى اليسار.
      final xRev = t.getCenter(find.text('الإيراد')).dx;
      final xLab = t.getCenter(find.text('المختبرات')).dx;
      final xAfter = t.getCenter(find.text('بعد المختبرات')).dx;
      final xExp = t.getCenter(find.text('المصروفات')).dx;
      final xAnal = t.getCenter(find.text('التحاليل')).dx;
      final xNet = t.getCenter(find.text('صافي العيادة')).dx;
      expect(xRev, greaterThan(xLab));
      expect(xLab, greaterThan(xAfter));
      expect(xExp, greaterThan(xAnal));
      expect(xAnal, greaterThan(xNet), reason: 'الصافي آخر عمود');
    });

    testWidgets('لا أسطر تحت الجدول — صارت أعمدة (طلب المالك)', (t) async {
      await pumpTable(t, rep: buildReport());
      expect(find.text('قيمة المختبرات (−)'), findsNothing);
      expect(find.text('صافي بعد المختبرات'), findsNothing);
      expect(find.text('إيراد التحاليل (+) — للعيادة'), findsNothing);
    });

    testWidgets('عمودا المختبرات والتحاليل يغيبان حين لا قيمة لهما',
        (t) async {
      await pumpTable(
          t, rep: buildReport(withLab: false, withAnal: false));
      expect(find.text('المختبرات'), findsNothing);
      expect(find.text('بعد المختبرات'), findsNothing);
      expect(find.text('التحاليل'), findsNothing);
      // وتبقى بقية الأعمدة كما هي.
      expect(find.text('المصروفات'), findsOneWidget);
      expect(find.text('صافي العيادة'), findsOneWidget);
    });

    testWidgets('صفّ السنة: كل عمودٍ برقمه، والصافي يطابق المعادلة',
        (t) async {
      final rep = buildReport();
      await pumpTable(t, rep: rep);
      expect(txt(t, 'prof-pnl-lab'), '1,200');
      expect(txt(t, 'prof-pnl-after-lab'), '1,800');
      expect(txt(t, 'prof-pnl-analyses'), '300');
      // 900 (حصة العيادة) − 200 مصروفات + 300 تحاليل = 1,000.
      expect(rep.net, 1000);
      expect(rep.afterLab, rep.doctor + rep.clinic);
    });
  });

  group('م190 — الجدول المختصر (الهاتف)', () {
    testWidgets('الإيراد بعد المختبرات، ولا عمود مصروفات', (t) async {
      await pumpTable(t, rep: buildReport(), full: false, width: 400);
      expect(find.text('المصروفات'), findsNothing,
          reason: 'م190: مطويٌّ داخل الصافي — لا مساحة في الهاتف');
      expect(find.text('المختبرات'), findsNothing);
      expect(find.text('الصافي'), findsOneWidget);
      // صفّ السنة: الإيراد المعروض = 3,000 − 1,200 = 1,800.
      expect(find.text('1,800'), findsWidgets);
      expect(find.text('3,000'), findsNothing,
          reason: 'الإجمالي قبل المعمل لا يظهر في المختصر');
    });

    testWidgets('علامة التوضيح تفتح معادلة الصافي بأرقامها', (t) async {
      await pumpTable(t, rep: buildReport(), full: false, width: 400);
      await t.tap(find.byKey(const Key('prof-pnl-net-info')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('prof-pnl-net-help')), findsOneWidget);
      expect(find.text('− قيمة المختبرات'), findsOneWidget);
      expect(find.text('+ إيراد التحاليل (للعيادة)'), findsOneWidget);
      expect(find.text('صافي إيراد العيادة'), findsOneWidget);
      await t.tap(find.byKey(const Key('prof-pnl-net-help-ok')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('prof-pnl-net-help')), findsNothing);
    });

    testWidgets('الضغط على صافي شهرٍ يشرح **أرقام ذلك الشهر**', (t) async {
      await pumpTable(t, rep: buildReport(), full: false, width: 400);
      await t.tap(find.byKey(const Key('prof-pnl-net-2026-08')));
      await t.pumpAndSettle();
      expect(find.text('صافي أغسطس — من أين جاء؟'), findsOneWidget);
    });
  });
}
