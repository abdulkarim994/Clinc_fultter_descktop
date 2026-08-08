/// إعادة إنتاج بلاغ المالك (بعد البناء 101): «بعد التحديد عم تختفي من
/// بطاقة المريض الأسنان المحددة» — رحلة كاملة على تطبيقٍ حقيقي:
/// ملف مريض ← ⋮ ← تحديد الأسنان ← (دائم ثم لبني) ← حفظ ← فحص رقاقات
/// البطاقة والقاعدة. تُختبر إعادةُ الفتح أيضاً (الجولة الثانية هي مسار
/// «الاختفاء» المرجّح: توفيقٌ يعيد الكتابة).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/records/tooth_chart.dart';
import 'package:dental_clinic_flutter/features/records/tooth_notation.dart';
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
    'services': ['حشو'],
    'payments': ['كاش'],
  };

  setUp(() => tmp = Directory.systemTemp.createTempSync('m101_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> seedAndBoot(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seed,
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
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapTooth(
    WidgetTester tester,
    String q,
    int n, {
    Dentition dentition = Dentition.adult,
  }) async {
    final rect = tester.getRect(find.byKey(const Key('tooth-chart')));
    final scale = rect.width / chartLogicalSize.width;
    final c = toothRect(q, n, dentition: dentition).center;
    await tester.tapAt(rect.topLeft + Offset(c.dx * scale, c.dy * scale));
    await tester.pump();
  }

  Future<void> openProfileAndSelector(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('rr-kebab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rr-kebab-0')), warnIfMissed: false);
    await settle(tester);
    // بالنص لا بالمفتاح: rr-teeth-0 مفتاحٌ لبند القائمة ولرقاقات البطاقة
    // معاً (سليم في التطبيق — لكنه يلتبس على الباحث حين تظهر الرقاقات).
    await tester.tap(find.text('تحديد الأسنان المعالجة'), warnIfMissed: false);
    await settle(tester);
  }

  testWidgets('جولتان: دائم ثم لبني — الرقاقات لا تختفي من البطاقة', (
    tester,
  ) async {
    await seedAndBoot(
      tester,
      seed: (c) {
        c.read(reposProvider).records.upsertLocal({
          'id': 'r1',
          'name': 'سالم',
          'patient_name': 'سالم',
          'clinic': 'ع1',
          'amount': 300,
          'date': '01/06/2026',
          'service': 'حشو',
          'payment': 'كاش',
        });
      },
    );

    // ── الجولة 1: سن دائم UR:6 ──
    await openProfileAndSelector(tester);
    // الافتراض: الطقم الدائم.
    expect(
      tester
          .widget<SegmentedButton<Dentition>>(
            find.byKey(const Key('tr-dentition')),
          )
          .selected,
      {Dentition.adult},
    );
    await tapTooth(tester, 'UR', 6);
    await tester.tap(find.byKey(const Key('tr-confirm')), warnIfMissed: false);
    await settle(tester);
    expect(
      find.byKey(const Key('rr-teeth-0')),
      findsOneWidget,
      reason: 'الجولة 1: رقاقات الأسنان ظاهرة بعد الحفظ',
    );
    expect(find.text('6'), findsWidgets);

    // ── الجولة 2 (مسار البلاغ): إعادة الفتح وإضافة لبني B ──
    await tester.ensureVisible(find.byKey(const Key('rr-kebab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rr-kebab-0')), warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.text('تحديد الأسنان المعالجة'), warnIfMissed: false);
    await settle(tester);
    // السن الدائم المحفوظ ما يزال محدداً (رقاقته حاضرة).
    expect(
      find.byKey(const Key('tr-sel-UR:6')),
      findsOneWidget,
      reason: 'الجولة 2: التحديد السابق حاضر عند إعادة الفتح',
    );
    await tester.tap(find.text('لبني'));
    await tester.pumpAndSettle();
    await tapTooth(tester, 'UL', 2, dentition: Dentition.primary);
    expect(find.byKey(const Key('tr-sel-UL:2:P')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tr-confirm')), warnIfMissed: false);
    await settle(tester);

    // البطاقة تعرض الرقاقتين معاً — لا اختفاء.
    expect(
      find.byKey(const Key('rr-teeth-0')),
      findsOneWidget,
      reason: 'الجولة 2: رقاقات الأسنان ظاهرة بعد الحفظ اللبني',
    );
    expect(find.text('6'), findsWidgets, reason: 'سن الدائم لم يختفِ');
    expect(find.text('B'), findsWidgets, reason: 'سن اللبني ظاهر بحرفه');

    // القاعدة: {q,n} للدائم كما هو + وسم d:P للبني.
    final chk = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    addTearDown(chk.dispose);
    final rec = chk.read(reposProvider).records.getAll().single;
    final report = rec['report'] as List;
    final teeth = [
      for (final e in report)
        for (final t in ((e as Map)['teeth'] as List? ?? const []))
          if (t is Map) Map<String, Object?>.from(t),
    ];
    expect(
      teeth.any((t) => t['q'] == 'UR' && t['n'] == 6 && t['d'] == null),
      isTrue,
      reason: 'الدائم بلا وسم',
    );
    expect(
      teeth.any((t) => t['q'] == 'UL' && t['n'] == 2 && t['d'] == 'P'),
      isTrue,
      reason: 'اللبني بوسمه',
    );
  });

  testWidgets('متغيرات الهاتف: FDI مفعل + تكبير خط + أسنان قائمة قديمة', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await seedAndBoot(
      tester,
      seed: (c) {
        final repos = c.read(reposProvider);
        // إعداد FDI (كما لو فعّله المالك من الإعدادات).
        repos.settings.set('app.config', {...config(), 'toothNotation': 'fdi'});
        // سجل قديم بأسنان محفوظة بالشكل التاريخي {q,n} + قيد خدمة بلا أسنان
        // + شاهدة حذف — أشكال البيانات الواقعية الثلاثة معاً.
        repos.records.upsertLocal({
          'id': 'r1',
          'name': 'سالم',
          'patient_name': 'سالم',
          'clinic': 'ع1',
          'amount': 300,
          'date': '01/06/2026',
          'service': 'حشو',
          'payment': 'كاش',
          'report': [
            {
              'id': 'e1',
              'service': 'حشو',
              'cost': 300,
              'teeth': [
                {'q': 'UR', 'n': 3},
                {'q': 'LL', 'n': 5, '_deleted': 1},
              ],
            },
            {'id': 'e2', 'service': 'تنظيف', 'cost': 0},
          ],
        });
      },
    );

    // البطاقة تعرض السن القائم بترميز FDI (13) قبل أي تعديل.
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await settle(tester);
    expect(
      find.text('13'),
      findsWidgets,
      reason: 'قبل التعديل: UR:3 بترميز FDI ظاهرة',
    );

    // فتح المحدد وإضافة UR:6 ثم حفظ.
    await tester.ensureVisible(find.byKey(const Key('rr-kebab-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rr-kebab-0')), warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.text('تحديد الأسنان المعالجة'), warnIfMissed: false);
    await settle(tester);
    expect(
      find.byKey(const Key('tr-sel-UR:3')),
      findsOneWidget,
      reason: 'التحديد المسبق للسن القائمة حاضر',
    );
    await tapTooth(tester, 'UR', 6);
    await tester.tap(find.byKey(const Key('tr-confirm')), warnIfMissed: false);
    await settle(tester);

    // البطاقة بعد الحفظ: 13 و16 ظاهرتان — لا اختفاء.
    expect(
      find.byKey(const Key('rr-teeth-empty')),
      findsNothing,
      reason: 'عمود الأسنان ليس فارغاً بعد الحفظ',
    );
    // م104 — سنّا الربع الواحد يُجمعان في خلية واحدة «13,16».
    expect(
      find.text('13,16'),
      findsWidgets,
      reason: 'القديمة والجديدة معاً في مجموعة الربع',
    );

    // القاعدة: القيد الخدمي بلا أسنان لم يُفسد، والشاهدة عولجت كما كان.
    final chk = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    addTearDown(chk.dispose);
    final rec = chk.read(reposProvider).records.getAll().single;
    final report = rec['report'] as List;
    expect(report, hasLength(2), reason: 'قيدا التقرير باقيان');
  });
}
