/// اختبارات م100/7 — الطقم اللبني: المفاتيح اللبنية `q:n:P`، هندسة
/// المخطط اللبني العشرينية، زر التبديل في الحوار، وكتابة وسم `d:'P'`
/// المتوافق عند الحفظ (صفوف الدائم تبقى `{q,n}` بايتاً ببايت).
library;

import 'package:dental_clinic_flutter/features/records/tooth_chart.dart';
import 'package:dental_clinic_flutter/features/records/tooth_notation.dart';
import 'package:dental_clinic_flutter/features/records/tooth_report_dialog.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م100/7-أ — المفاتيح اللبنية q:n:P (إضافية بحتة)', () {
    test('مفاتيح الدائم لا تتغير حرفاً، واللبني بلاحقة :P', () {
      expect(toothKey('UR', 6), 'UR:6');
      expect(toothKey('UR', 3, dentition: Dentition.primary), 'UR:3:P');
    });
    test('التفكيك يتقبل الشكلين ويسقط بأمان عند التلف', () {
      final adult = parseToothKey('LL:8');
      expect((adult.q, adult.n, adult.dentition),
          ('LL', 8, Dentition.adult));
      final prim = parseToothKey('UL:5:P');
      expect((prim.q, prim.n, prim.dentition),
          ('UL', 5, Dentition.primary));
      final bad = parseToothKey('غريب');
      expect((bad.q, bad.n, bad.dentition), ('UR', 1, Dentition.adult));
    });
    test('toothFromKey: وسم d:\'P\' للّبني فقط — الدائم {q,n} كما كان', () {
      expect(toothFromKey('UR:6'), {'q': 'UR', 'n': 6});
      expect(toothFromKey('UR:3:P'), {'q': 'UR', 'n': 3, 'd': 'P'});
    });
    test('toothKeyOfTooth يقرأ الوسم (وغيابه = دائم — بيانات قديمة)', () {
      expect(toothKeyOfTooth({'q': 'UR', 'n': 6}), 'UR:6');
      expect(toothKeyOfTooth({'q': 'UR', 'n': 3, 'd': 'P'}), 'UR:3:P');
    });
    test('toothLabelFromKey: لاحقة المفتاح تفرض الطقم اللبني', () {
      final palmer =
          toothLabelFromKey('UR:3:P', system: NotationSystem.palmer);
      expect(palmer.text, 'C'); // A B C — الناب اللبني
      expect(palmer.palmerBorder, isTrue);
      expect(
          toothLabelFromKey('UR:3:P', system: NotationSystem.fdi).text,
          '53'); // ISO 3950: الربع اللبني الأعلى الأيمن = 5
    });
  });

  group('م100/7-ب — هندسة المخطط اللبني', () {
    test('عشرون سناً: خمسة لكل ربع', () {
      expect(primaryToothData.length, 20);
      for (final q in ['UR', 'UL', 'LR', 'LL']) {
        expect(primaryToothData.where((t) => t.$1 == q).length, 5,
            reason: 'الربع $q');
      }
    });
    test('تناظر مرآتي حول منتصف اللوحة (x\' = 320−x−w)', () {
      for (var n = 1; n <= 5; n++) {
        final r = primaryToothData.firstWhere(
            (t) => t.$1 == 'UR' && t.$2 == n);
        final l = primaryToothData.firstWhere(
            (t) => t.$1 == 'UL' && t.$2 == n);
        expect(l.$3, 320 - r.$3 - r.$4, reason: 'الموضع $n');
        expect(l.$4, r.$4);
        expect(l.$5, r.$5);
      }
    });
    test('toothAt اللبني يعيد مفتاحاً بلاحقة :P، والدائم كما كان', () {
      final cPrim =
          toothRect('UR', 3, dentition: Dentition.primary).center;
      expect(toothAt(cPrim, dentition: Dentition.primary), 'UR:3:P');
      // انحدار: النداء القديم (بلا معامل) يطابق سلوكه التاريخي حرفياً.
      expect(toothAt(toothRect('UR', 6).center), 'UR:6');
      expect(toothRect('UR', 1), const Rect.fromLTWH(144, 73, 14, 34));
    });
  });

  group('م100/7-ج — الحوار: تبديل الطقم والحفظ بالوسم', () {
    Future<ToothReportResult?> resultFuture = Future.value();

    Future<void> openDialog(WidgetTester tester,
        {List<Map<String, Object?>> entries = const [],
        NotationSystem system = NotationSystem.palmer}) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                resultFuture = showToothReportDialog(
                  context,
                  teethOnly: true,
                  entries: entries,
                  notation: system,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> tapTooth(WidgetTester tester, String q, int n,
        {Dentition dentition = Dentition.adult}) async {
      final rect = tester.getRect(find.byKey(const Key('tooth-chart')));
      final scale = rect.width / chartLogicalSize.width;
      final c = toothRect(q, n, dentition: dentition).center;
      await tester.tapAt(rect.topLeft + Offset(c.dx * scale, c.dy * scale));
      await tester.pump();
    }

    testWidgets('التبديل للّبني ثم نقر C يختار UR:3:P ويعرض حرفها',
        (tester) async {
      await openDialog(tester);
      // الافتراض: الطقم الدائم (حالة زر التبديل في صف العنوان).
      SegmentedButton<Dentition> seg() =>
          tester.widget<SegmentedButton<Dentition>>(
              find.byKey(const Key('tr-dentition')));
      expect(seg().selected, {Dentition.adult});
      await tester.tap(find.text('لبني'));
      await tester.pumpAndSettle();
      expect(seg().selected, {Dentition.primary});

      await tapTooth(tester, 'UR', 3, dentition: Dentition.primary);
      expect(find.byKey(const Key('tr-sel-UR:3:P')), findsOneWidget);
      expect(find.text('C'), findsWidgets); // رقاقة Palmer بحرف الناب

      // نقرة ثانية تلغي الاختيار (نفس سلوك الدائم).
      await tapTooth(tester, 'UR', 3, dentition: Dentition.primary);
      expect(find.byKey(const Key('tr-sel-UR:3:P')), findsNothing);
    });

    testWidgets('إطباق مختلط: دائم + لبني معاً، والحفظ يسم اللبني فقط',
        (tester) async {
      await openDialog(tester);
      await tapTooth(tester, 'UR', 6); // دائم
      await tester.tap(find.text('لبني'));
      await tester.pumpAndSettle();
      await tapTooth(tester, 'LL', 2, dentition: Dentition.primary);

      // الاختيار محفوظ عبر التبديل — الرقاقتان ظاهرتان معاً.
      expect(find.byKey(const Key('tr-sel-UR:6')), findsOneWidget);
      expect(find.byKey(const Key('tr-sel-LL:2:P')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tr-confirm')));
      await tester.pumpAndSettle();
      final res = await resultFuture;
      final teeth = [
        for (final e in res!.entries)
          ...activeTeeth(e['teeth']),
      ];
      expect(
          teeth.any((t) =>
              t['q'] == 'UR' && t['n'] == 6 && !t.containsKey('d')),
          isTrue,
          reason: 'صف الدائم يبقى {q,n} بلا وسم — التوافق');
      expect(
          teeth.any(
              (t) => t['q'] == 'LL' && t['n'] == 2 && t['d'] == 'P'),
          isTrue,
          reason: 'صف اللبني يحمل d:\'P\'');
    });

    testWidgets('فتح ذكي: ملف كل أسنانه لبنية يفتح على الطقم اللبني',
        (tester) async {
      await openDialog(tester, entries: [
        {
          'id': 'r1',
          'service': 'علاج',
          'cost': 0,
          'teeth': [
            {'q': 'UR', 'n': 2, 'd': 'P'},
          ],
        },
      ]);
      expect(
          tester
              .widget<SegmentedButton<Dentition>>(
                  find.byKey(const Key('tr-dentition')))
              .selected,
          {Dentition.primary},
          reason: 'الفتح الذكي يقلب الزر للّبني');
      // السن الموثقة سابقاً «مُعالَجة» بمفتاحها اللبني ورقاقتها B.
      expect(find.byKey(const Key('tr-sel-UR:2:P')), findsOneWidget);
      expect(find.text('B'), findsWidgets);
    });

    testWidgets('FDI لبني: الرقاقة تعرض رقمي ISO (54) لا الحرف',
        (tester) async {
      await openDialog(tester, system: NotationSystem.fdi);
      await tester.tap(find.text('لبني'));
      await tester.pumpAndSettle();
      await tapTooth(tester, 'UR', 4, dentition: Dentition.primary);
      expect(find.byKey(const Key('tr-sel-UR:4:P')), findsOneWidget);
      expect(find.text('54'), findsWidgets);
      expect(find.text('D'), findsNothing);
    });
  });

  group('م100/7-د — التوفيق يحفظ الوسم عبر إعادة الفتح', () {
    test('reconcileTeethOnly يبقي d:\'P\' للحاضر ويسمه للمضاف', () {
      final entries = [
        {
          'id': 'e1',
          'service': 'علاج',
          'cost': 0,
          'teeth': [
            {'q': 'UR', 'n': 6},
            {'q': 'UR', 'n': 2, 'd': 'P'},
          ],
        },
      ];
      // إبقاء الاثنين وإضافة لبني جديد LL:1:P.
      final out = reconcileTeethOnly(
          entries, {'UR:6', 'UR:2:P', 'LL:1:P'});
      final teeth = [...activeTeeth(out[0]['teeth'])];
      expect(teeth, hasLength(3));
      expect(teeth[0], {'q': 'UR', 'n': 6});
      expect(teeth[1], {'q': 'UR', 'n': 2, 'd': 'P'});
      expect(teeth[2], {'q': 'LL', 'n': 1, 'd': 'P'});
      // وإسقاط اللبني وحده لا يمس الدائم بنفس الموضع.
      final out2 = reconcileTeethOnly(entries, {'UR:6'});
      expect([...activeTeeth(out2[0]['teeth'])], [
        {'q': 'UR', 'n': 6},
      ]);
    });
  });
}
