/// اختبارات م104 — وحدة تلخيص الأسنان: التجميع الربعي، ضغط المدى (≥3)،
/// ترتيب الأرباع، اللبني بالحروف، FDI بأرقامه الكاملة، وتجاهل الشواهد —
/// ثم واجهة بطاقة الملف: فمٌ كامل = 4 خلايا مدى لا 32 رقاقة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/records/tooth_notation.dart';
import 'package:dental_clinic_flutter/features/records/tooth_summary.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  List<(String, String)> shape(List<ToothGroupLabel> gs) => [
    for (final g in gs) (g.quadrant, g.text),
  ];

  group('م104/أ — الضغط إلى مدى', () {
    test('ربع كامل ⇒ خلية مدى واحدة 1-8', () {
      final gs = summarizeTeethRefs([
        for (var n = 1; n <= 8; n++) (q: 'UR', n: n, primary: false),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('UR', '1-8')]);
      expect(gs.single.palmerBorder, isTrue);
    });
    test('فم كامل (32 سناً) ⇒ 4 خلايا فقط بترتيب الأرباع', () {
      final gs = summarizeTeethRefs([
        for (final q in ['LL', 'UR', 'LR', 'UL']) // دخل مبعثر عمداً
          for (var n = 1; n <= 8; n++) (q: q, n: n, primary: false),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [
        ('UR', '1-8'),
        ('UL', '1-8'),
        ('LR', '1-8'),
        ('LL', '1-8'),
      ]);
    });
    test('غير المتتالي قائمة، والثلاثي فأكثر مدى، والثنائي صريح', () {
      final gs = summarizeTeethRefs([
        (q: 'UR', n: 1, primary: false),
        (q: 'UR', n: 3, primary: false),
        (q: 'UR', n: 4, primary: false),
        (q: 'UR', n: 5, primary: false),
        (q: 'UR', n: 7, primary: false),
        (q: 'UR', n: 8, primary: false),
      ], system: NotationSystem.palmer);
      // 1 | 3-5 (مدى) | 7,8 (ثنائي صريح).
      expect(shape(gs), [('UR', '1,3-5,7,8')]);
    });
    test('سن واحدة ⇒ رمزها المفرد (كما اليوم)', () {
      final gs = summarizeTeethRefs([
        (q: 'LL', n: 6, primary: false),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('LL', '6')]);
    });
    test('التكرار لا يضاعف', () {
      final gs = summarizeTeethRefs([
        (q: 'UR', n: 6, primary: false),
        (q: 'UR', n: 6, primary: false),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('UR', '6')]);
    });
  });

  group('م104/ب — اللبني والإطباق المختلط', () {
    test('طقم لبني كامل بربع ⇒ A-E', () {
      final gs = summarizeTeethRefs([
        for (var n = 1; n <= 5; n++) (q: 'UL', n: n, primary: true),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('UL', 'A-E')]);
      expect(gs.single.primary, isTrue);
    });
    test('دائم ولبني بنفس الربع ⇒ مجموعتان (الدائم أولاً)', () {
      final gs = summarizeTeethRefs([
        (q: 'UR', n: 2, primary: true),
        (q: 'UR', n: 6, primary: false),
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('UR', '6'), ('UR', 'B')]);
    });
  });

  group('م104/ج — FDI: أرقام كاملة للطرفين وبلا إطار', () {
    test('فك علوي كامل ⇒ 11-18 و21-28', () {
      final gs = summarizeTeethRefs([
        for (final q in ['UR', 'UL'])
          for (var n = 1; n <= 8; n++) (q: q, n: n, primary: false),
      ], system: NotationSystem.fdi);
      expect(shape(gs), [('UR', '11-18'), ('UL', '21-28')]);
      expect(gs.first.palmerBorder, isFalse);
    });
    test('لبني FDI ⇒ 51-55، ومتفرق ⇒ 51,53', () {
      expect(
        shape(
          summarizeTeethRefs([
            for (var n = 1; n <= 5; n++) (q: 'UR', n: n, primary: true),
          ], system: NotationSystem.fdi),
        ),
        [('UR', '51-55')],
      );
      expect(
        shape(
          summarizeTeethRefs([
            (q: 'UR', n: 1, primary: true),
            (q: 'UR', n: 3, primary: true),
          ], system: NotationSystem.fdi),
        ),
        [('UR', '51,53')],
      );
    });
  });

  group('م105/أ — نموذج الشبكة الصليبية', () {
    test('ربع واحد ⇒ null (يسقط لخلايا القوس)', () {
      expect(
        toothCrossModel([
          (q: 'UR', n: 1, primary: false),
          (q: 'UR', n: 5, primary: false),
        ], system: NotationSystem.palmer),
        isNull,
      );
      expect(toothCrossModel(const [], system: NotationSystem.palmer), isNull);
    });
    test('فك علوي كامل: يمين المريض تنازلي 8-1 ويساره تصاعدي 1-8', () {
      final m = toothCrossModel([
        for (final q in ['UR', 'UL'])
          for (var n = 1; n <= 8; n++) (q: q, n: n, primary: false),
      ], system: NotationSystem.palmer)!;
      expect((m.upperRight, m.upperLeft), ('8-1', '1-8'));
      expect(m.hasUpper, isTrue);
      expect(m.hasLower, isFalse);
    });
    test('فم كامل: الأقسام الأربعة باتجاهيها', () {
      final m = toothCrossModel([
        for (final q in ['UR', 'UL', 'LR', 'LL'])
          for (var n = 1; n <= 8; n++) (q: q, n: n, primary: false),
      ], system: NotationSystem.palmer)!;
      expect(m.upperRight, '8-1');
      expect(m.upperLeft, '1-8');
      expect(m.lowerRight, '8-1');
      expect(m.lowerLeft, '1-8');
      expect(m.hasUpper && m.hasLower, isTrue);
    });
    test('المتفرق تنازلياً على اليمين: 8,5-3,1', () {
      final m = toothCrossModel([
        for (final n in [1, 3, 4, 5, 8]) (q: 'UR', n: n, primary: false),
        (q: 'UL', n: 1, primary: false),
      ], system: NotationSystem.palmer)!;
      expect(m.upperRight, '8,5-3,1');
      expect(m.upperLeft, '1');
    });
    test('لبني كصورة المالك: E-A | A-E، وFDI بأرقام كاملة', () {
      final palmer = toothCrossModel([
        for (final q in ['UR', 'UL'])
          for (var n = 1; n <= 5; n++) (q: q, n: n, primary: true),
      ], system: NotationSystem.palmer)!;
      expect((palmer.upperRight, palmer.upperLeft), ('E-A', 'A-E'));

      final fdi = toothCrossModel([
        for (final q in ['UR', 'UL', 'LR', 'LL'])
          for (var n = 1; n <= 8; n++) (q: q, n: n, primary: false),
      ], system: NotationSystem.fdi)!;
      expect(fdi.upperRight, '18-11');
      expect(fdi.upperLeft, '21-28');
      expect(fdi.lowerRight, '48-41');
      expect(fdi.lowerLeft, '31-38');
    });
    test('فك سفلي فقط: hasUpper=false (نصف الشبكة السفلي)', () {
      final m = toothCrossModel([
        (q: 'LR', n: 6, primary: false),
        (q: 'LL', n: 6, primary: false),
      ], system: NotationSystem.palmer)!;
      expect(m.hasUpper, isFalse);
      expect(m.hasLower, isTrue);
      expect((m.lowerRight, m.lowerLeft), ('6', '6'));
    });
    test('إطباق مختلط داخل القسم: الدائم ثم اللبني', () {
      final m = toothCrossModel([
        (q: 'UR', n: 6, primary: false),
        (q: 'UR', n: 2, primary: true),
        (q: 'UL', n: 3, primary: false),
      ], system: NotationSystem.palmer)!;
      expect(m.upperRight, '6,B');
      expect(m.upperLeft, '3');
    });
  });

  group('م104/هـ — بطاقة الملف: فم كامل = 4 خلايا مدى', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m104_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> bootWithFullMouth(
      WidgetTester tester, {
      String? notation,
    }) async {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'services': ['تنظيف'],
        'payments': ['كاش'],
        // م133 — صيغة العنصر الواعي بالعدم بطلب المحلل.
        'toothNotation': ?notation,
      });
      c.read(reposProvider).records.upsertLocal({
        'id': 'r1',
        'name': 'سالم',
        'patient_name': 'سالم',
        'clinic': 'ع1',
        'amount': 500,
        'date': '01/06/2026',
        'service': 'تنظيف',
        'payment': 'كاش',
        'report': [
          {
            'id': 'e1',
            'service': 'تنظيف',
            'cost': 500,
            'teeth': [
              for (final q in ['UR', 'UL', 'LR', 'LL'])
                for (var n = 1; n <= 8; n++) {'q': q, 'n': n},
            ],
          },
        ],
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
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('patient-card-سالم')),
        warnIfMissed: false,
      );
      // ضختان: بدء انتقال الدفع ثم إتمامه (نمط settle في بقية العدد).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Palmer: فم كامل ⇒ الشبكة الصليبية (م105)', (tester) async {
      await bootWithFullMouth(tester);
      // يمين المريض تنازلي (8-1) في الفكين، ويساره تصاعدي (1-8).
      expect(
        find.text('8-1'),
        findsNWidgets(2),
        reason: 'م105: قسما يمين المريض',
      );
      expect(
        find.text('1-8'),
        findsNWidgets(2),
        reason: 'م105: قسما يسار المريض',
      );
      expect(find.byKey(const Key('rr-teeth-empty')), findsNothing);
    });

    testWidgets('FDI: فم كامل ⇒ الشبكة بأرقام كاملة', (tester) async {
      await bootWithFullMouth(tester, notation: 'fdi');
      for (final range in ['18-11', '21-28', '48-41', '31-38']) {
        expect(find.text(range), findsOneWidget, reason: 'قسم $range');
      }
    });
  });

  group('م104/د — من عناصر التخزين مباشرة', () {
    test('يقرأ وسم d ويتجاهل شواهد الحذف', () {
      final gs = summarizeTeethMaps([
        {'q': 'UR', 'n': 6},
        {'q': 'UR', 'n': 2, 'd': 'P'},
        {'q': 'UR', 'n': 7, '_deleted': 1},
      ], system: NotationSystem.palmer);
      expect(shape(gs), [('UR', '6'), ('UR', 'B')]);
    });
    test('فارغ ⇒ فارغ، وربع تالف ⇒ ملاذ UR', () {
      expect(summarizeTeethMaps(const [], system: NotationSystem.fdi), isEmpty);
      final gs = summarizeTeethRefs([
        (q: 'غريب', n: 1, primary: false),
      ], system: NotationSystem.fdi);
      expect(shape(gs), [('UR', '11')]);
    });
  });
}
