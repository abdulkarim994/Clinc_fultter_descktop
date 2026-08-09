/// م152 — سد ثغرتي تجاوز قاعدة تكرار التحليل (بلاغ المالك 2026-08-10).
///
/// (أ) ثغرة الهوية: كانت المطابقة تقف عند اختلاف معرّفَي المريض ولا تسقط
///     للاسم أبداً — فمرّ التحليل المكرر لنفس الاسم بهاتفٍ مختلف أو بلا
///     هاتف. القاعدة المؤكدة: **لكل اسم مرة واحدة** — الاسم المطبَّع أساس
///     المطابقة والمعرّف إضافة.
/// (ب) حارسا الكاتبَين بالمعرّفات المختلطة: لا صف مخالف مهما اختلف المعرّف.
/// (ج) بوابة «الزيارة السريعة»: علامة التحاليل مؤشرة والمريض محجوب ⇒
///     حوار رسالة الخطأ ويتوقف الحفظ كله (لا زيارة ولا تحليل).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart'
    show arNorm;
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate, jsTruthy;
import 'package:dental_clinic_flutter/features/patients/quick_visit_sheet.dart'
    show showQuickVisitSheet;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// م133 — `Override` تُصدَّر من `misc.dart` في Riverpod 3 لا من الجذر.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = getCurrentDate();

  JMap triRow({
    required String id,
    required String name,
    String? patientId,
    String? date,
  }) => {
        'id': id,
        'isAnalysis': 1,
        'analysisName': kTriAnalysesName,
        'name': name,
        'patient_name': name,
        'patient_id': ?patientId,
        'amount': 50,
        'payment': 'كاش',
        'date': date ?? today,
      };

  group('م152/أ — هوية المريض: الاسم أساس المطابقة والمعرّف إضافة', () {
    test('نفس الاسم بمعرّفين مختلفين = نفس المريض (كان يمرّ — الثغرة)', () {
      final rows = [triRow(id: 'a1', name: 'محمد', patientId: 'p:091:محمد')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p:092:محمد', patientName: 'محمد', normalize: arNorm),
        today,
        reason: 'اختلاف المعرّفين لا يلغي مطابقة الاسم',
      );
    });

    test('نفس الاسم — طرفٌ بمعرّف وطرفٌ بلا معرّف = نفس المريض', () {
      final rows = [triRow(id: 'a1', name: 'محمد', patientId: 'p:091:محمد')];
      expect(
        lastTriAnalysisDate(rows, patientName: 'محمد', normalize: arNorm),
        today,
      );
    });

    test('التطبيع العربي: «إبراهيم» تحجب «ابراهيم» بمعرّفين مختلفين', () {
      final rows =
          [triRow(id: 'a1', name: 'إبراهيم', patientId: 'p:091:إبراهيم')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p:x', patientName: 'ابراهيم', normalize: arNorm),
        today,
      );
    });

    test('نفس المعرّف باسمٍ مختلف = نفس المريض (إعادة تسمية)', () {
      final rows = [triRow(id: 'a1', name: 'محمد', patientId: 'p1')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p1', patientName: 'محمد القديم', normalize: arNorm),
        today,
      );
    });

    test('اسمان مختلفان بمعرّفين مختلفين = مريضان (يمرّ)', () {
      final rows = [triRow(id: 'a1', name: 'محمد', patientId: 'p1')];
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p2', patientName: 'خالد', normalize: arNorm),
        isNull,
      );
    });
  });

  group('م152/ب — حارسا الكاتبَين بالمعرّفات المختلطة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m152_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    JMap config() => {
          'centerName': 'مركز الاختبار',
          'doctorPct': 50,
          'clinics': ['الصفوة'],
          'services': ['حشو'],
          'payments': ['كاش', 'تحويل'],
          kTriAnalysesCfgKey: {
            'enabled': true,
            'price': 50,
            'repeatMonths': 6,
          },
        };

    ProviderContainer container() => ProviderContainer(overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ]);

    int analCount(ProviderContainer c) => c
        .read(reposProvider)
        .records
        .getAll()
        .where((r) => jsTruthy(r['isAnalysis']))
        .length;

    test('زيارة بهاتفٍ ثم أخرى بلا هاتف (معرّفان مختلفان) — التحليل الثاني '
        'يُسقطه صمام saveNewRecord (كان يُكتب — الثغرة)', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      SaveRecordResult visit({String phone = '', AnalysisInput? anal}) =>
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'محمد',
              date: today,
              amount: 200,
              clinic: 'الصفوة',
              service: 'حشو',
              payment: 'كاش',
              phone: phone,
              analysis: anal,
            ),
          );
      final anal = AnalysisInput(
          name: kTriAnalysesName, price: 50, payment: 'كاش');
      visit(phone: '0911111111', anal: anal); // الأول — يُكتب.
      expect(analCount(c), 1);
      visit(phone: '', anal: anal); // نفس الاسم بلا هاتف — يُصَدّ.
      expect(analCount(c), 1, reason: 'لا صف مخالف رغم اختلاف المعرّف');
      visit(phone: '0922222222', anal: anal); // هاتف ثالث — يُصَدّ.
      expect(analCount(c), 1);
    });

    test('addAnalysisToVisit بمعرّفٍ مختلف لنفس الاسم يُصَدّ', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      final e1 = saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'محمد',
          date: today,
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          phone: '0911111111',
        ),
      ).entryId;
      expect(
        addAnalysisToVisit(repos,
            analysisOf: e1,
            patientName: 'محمد',
            patientId: 'p:0911111111:محمد',
            clinic: 'الصفوة',
            date: today,
            cfg: config(),
            payment: 'كاش'),
        isTrue,
      );
      // محاولة ثانية بمعرّف هويةٍ آخر لنفس الاسم (زيارة بلا هاتف).
      expect(
        addAnalysisToVisit(repos,
            analysisOf: e1,
            patientName: 'محمد',
            patientId: 'p::محمد',
            clinic: 'الصفوة',
            date: today,
            cfg: config(),
            payment: 'تحويل'),
        isFalse,
        reason: 'الاسم يحجب مهما اختلف المعرّف',
      );
      expect(analCount(c), 1);
    });
  });

  group('م152/ج — بوابة «الزيارة السريعة»: إيقاف الحفظ كله برسالة الخطأ',
      () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m152qv_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    JMap config() => {
          'centerName': 'مركز الاختبار',
          'doctorPct': 50,
          'clinics': ['الصفوة'],
          'services': ['حشو'],
          'payments': ['كاش', 'تحويل'],
          'servicePrices': {'حشو': 150},
          kTriAnalysesCfgKey: {
            'enabled': true,
            'price': 50,
            'repeatMonths': 6,
          },
        };

    List<Override> overrides() => [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ];

    testWidgets('مريض له تحليل اليوم: الحفظ بعلامة التحاليل يُحجب برسالة '
        'المواصفة ولا تُكتب زيارة ولا تحليل', (t) async {
      // بذر: زيارة بتحليل لمحمد (بهاتفٍ — معرّف هوية مختلف عن الورقة).
      final seedC = ProviderContainer(overrides: overrides());
      final repos = seedC.read(reposProvider);
      repos.settings.set('app.config', config());
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'محمد',
          date: today,
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          phone: '0911111111',
          analysis: AnalysisInput(
              name: kTriAnalysesName, price: 50, payment: 'كاش'),
        ),
      );
      final before = repos.records.getAll().length;
      seedC.dispose();

      await t.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showQuickVisitSheet(
                        ctx,
                        name: 'محمد',
                        clinic: 'الصفوة',
                        onFullOptions: () {},
                      ),
                      child: const Text('فتح'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('فتح'));
      await t.pumpAndSettle();

      // اختيار المعالجة (يملأ السعر) ثم تأشير التحاليل.
      await t.tap(find.byKey(const Key('qv-service')));
      await t.pumpAndSettle();
      await t.tap(find.text('حشو').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('qv-analysis-toggle')));
      await t.pumpAndSettle();

      // الحفظ ⇒ حوار الحجب بنص المواصفة، ولا كتابة إطلاقاً.
      await t.tap(find.byKey(const Key('qv-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tri-repeat-blocked-msg')), findsOneWidget,
          reason: 'رسالة الحجب ظهرت');
      final blocked = t.widget<Text>(
          find.byKey(const Key('tri-repeat-blocked-msg')));
      expect(blocked.data, contains('لا يمكن إجراء تحليل ثلاثي جديد'));
      expect(blocked.data, contains('6 أشهر على الأقل'));

      final chk = ProviderContainer(overrides: overrides());
      addTearDown(chk.dispose);
      expect(chk.read(reposProvider).records.getAll().length, before,
          reason: 'الحفظ توقف كله — لا زيارة ولا تحليل');
    });

    testWidgets('بلا علامة التحاليل: الحفظ يمرّ طبيعياً رغم الحجب', (t) async {
      final seedC = ProviderContainer(overrides: overrides());
      final repos = seedC.read(reposProvider);
      repos.settings.set('app.config', config());
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'محمد',
          date: today,
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          analysis: AnalysisInput(
              name: kTriAnalysesName, price: 50, payment: 'كاش'),
        ),
      );
      final before = seedC.read(reposProvider).records.getAll().length;
      seedC.dispose();

      await t.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showQuickVisitSheet(
                        ctx,
                        name: 'محمد',
                        clinic: 'الصفوة',
                        onFullOptions: () {},
                      ),
                      child: const Text('فتح'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('فتح'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('qv-service')));
      await t.pumpAndSettle();
      await t.tap(find.text('حشو').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('qv-save')));
      await t.pumpAndSettle();

      final chk = ProviderContainer(overrides: overrides());
      addTearDown(chk.dispose);
      expect(chk.read(reposProvider).records.getAll().length, before + 1,
          reason: 'الزيارة العادية تمرّ — الحجب على التحليل وحده');
    });
  });
}
