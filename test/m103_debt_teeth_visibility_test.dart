/// اختبار م103 الحارس — بلاغ المالك: «معالجة جديدة بأسنان محددة تُحفظ ثم
/// لا تظهر في بطاقة الملف، وإعادة فتح المحدد تجدها فارغة».
///
/// **السبب الجذري المثبت** (من صفوف الخادم الحي): المعالجة الدَّينية تكتب
/// الأسنان على سجل أصل الدين (isDebt) — وهو **مخفي** من قائمة الملف
/// (توافق Vue: القيود بلا أصل الدين) — بينما الصف الظاهر «دفعة أولى (دين)»
/// والدين كلاهما بلا نسخة تقرير، فتبدو الأسنان مختفية والمحدد فارغاً.
///
/// الحرّاس الثلاثة هنا:
///  1) إنشاء معالجة دَينية بأسنان ⇒ بطاقة الملف الظاهرة تعرض الرقاقات
///     (نسخة التقرير على الدين — إصلاح record_saver).
///  2) فتح «تحديد الأسنان» من البطاقة الظاهرة ⇒ الاختيار السابق حاضر،
///     وتعديلُه يوحّد النسخ الثلاث (دفعة/دين/أصل مخفي — إصلاح المحرر).
///  3) بيانات قديمة (دينها بلا نسخة) ⇒ ملاذ العرض يصعد لسجل الأصل المخفي
///     فتظهر الأسنان بلا أي تعديل بيانات (شفاء رجعي).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/records/tooth_chart.dart';

import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinics': ['ع1'],
    'services': ['خلع'],
    'payments': ['كاش'],
  };

  setUp(() => tmp = Directory.systemTemp.createTempSync('m103_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(
    WidgetTester tester, {
    required void Function(ProviderContainer c) seed,
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
    c.read(reposProvider).settings.set('app.config', config());
    seed(c);
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
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await settle(tester);
  }

  /// إنشاء معالجة دَينية بأسنان عبر مسار الحفظ الحقيقي نفسه (ما تستدعيه
  /// شاشة الإضافة حرفياً) — UR:6 دائم + UL:2 لبني (إطباق مختلط).
  void seedDebtTreatment(ProviderContainer c) {
    saveNewRecord(
      c.read(reposProvider),
      config(),
      const SaveRecordInput(
        name: 'سالم',
        date: '01/06/2026',
        amount: 300,
        clinic: 'ع1',
        service: 'خلع',
        payment: 'كاش',
        isDebt: true,
        firstPay: 100,
        report: {
          'entries': [
            {
              'id': 'e1',
              'service': 'خلع',
              'cost': 300,
              'teeth': [
                {'q': 'UR', 'n': 6},
                {'q': 'UL', 'n': 2, 'd': 'P'},
              ],
            },
          ],
          'meta': {'name': 'سالم'},
        },
      ),
    );
  }

  testWidgets(
    'م103/1+2 — معالجة دَينية: الأسنان ظاهرة والمحدد ممتلئ والنسخ موحدة',
    (tester) async {
      await boot(tester, seed: seedDebtTreatment);
      await openProfile(tester);

      // ١) البطاقة الظاهرة (دفعة أولى) تعرض الرقاقات: 6 دائم وB لبني.
      expect(
        find.byKey(const Key('rr-teeth-empty')),
        findsNothing,
        reason: 'م103: عمود الأسنان ليس فارغاً في بطاقة المعالجة الدَّينية',
      );
      expect(find.text('6'), findsWidgets);
      expect(find.text('B'), findsWidgets);

      // ٢) فتح المحدد من البطاقة الظاهرة: الاختيار السابق حاضر.
      await tester.ensureVisible(find.byKey(const Key('rr-kebab-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.text('تحديد الأسنان المعالجة'),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(
        find.byKey(const Key('tr-sel-UR:6')),
        findsOneWidget,
        reason: 'م103: المحدد يفتح على الاختيار المحفوظ لا فارغاً',
      );
      expect(find.byKey(const Key('tr-sel-UL:2:P')), findsOneWidget);

      // إضافة LL:3 ثم حفظ — النسخ الثلاث تتوحد.
      final rect = tester.getRect(find.byKey(const Key('tooth-chart')));
      final scale = rect.width / chartLogicalSize.width;
      final cc = toothRect('LL', 3).center;
      await tester.tapAt(rect.topLeft + Offset(cc.dx * scale, cc.dy * scale));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('tr-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('3'), findsWidgets, reason: 'الرقاقة الجديدة ظاهرة');

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final repos = chk.read(reposProvider);
      Set<String> keysOf(Object? report) {
        final entries = report is Map ? report['entries'] : report;
        return {
          for (final e in (entries as List? ?? const []))
            if (e is Map)
              for (final t in (e['teeth'] as List? ?? const []))
                if (t is Map && jsNumOr0(t['_deleted']) != 1)
                  '${t['q']}:${jsNumOr0(t['n']).toInt()}'
                      '${'${t['d'] ?? ''}' == 'P' ? ':P' : ''}',
        };
      }

      const want = {'UR:6', 'UL:2:P', 'LL:3'};
      final debt = repos.debts.getAll().single;
      expect(keysOf(debt['report']), want, reason: 'نسخة الدين');
      final origin = repos.records.getAll().firstWhere(
        (r) => jsNumOr0(r['isDebt']) == 1,
      );
      expect(
        keysOf(origin['report']),
        want,
        reason: 'م103: سجل الأصل المخفي مُحدَّث أيضاً — لا تباعد نسخ',
      );
      final payRow = repos.records.getAll().firstWhere(
        (r) => jsNumOr0(r['isDebtPayment']) == 1,
      );
      expect(keysOf(payRow['report']), want, reason: 'الصف الظاهر المحرَّر');
    },
  );

  testWidgets(
    'م103/3 — شفاء رجعي: دين قديم بلا نسخة ⇒ العرض يصعد للأصل المخفي',
    (tester) async {
      await boot(
        tester,
        seed: (c) {
          seedDebtTreatment(c);
          // محاكاة بياناته القائمة (ما قبل م103): تجريد الدين من نسخة التقرير.
          final repos = c.read(reposProvider);
          final debt = repos.debts.getAll().single;
          final stripped = Map<String, Object?>.from(debt)..remove('report');
          repos.debts.upsertLocal(stripped);
        },
      );
      await openProfile(tester);

      // البطاقة الظاهرة تعرض أسنان الأصل المخفي رغم خلو الدين والدفعة.
      expect(
        find.byKey(const Key('rr-teeth-empty')),
        findsNothing,
        reason: 'م103: ملاذ الأصل يشفي البيانات القديمة بلا أي تعديل بيانات',
      );
      expect(find.text('6'), findsWidgets);
      expect(find.text('B'), findsWidgets);
    },
  );
}
