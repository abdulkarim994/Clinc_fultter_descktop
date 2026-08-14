/// اختبارات م180/ب — ميزة «نسبة المعالجات» (مطفأة افتراضياً):
/// • المنطق النقي: الإطفاء ⇒ نسبة حية صفر ولقطات جديدة بصفر؛ اللقطات
///   القديمة محفوظة حرفياً (effectiveDoctorPct لقطةً-أولاً).
/// • الترحيل: حساب قديم ضبط doctorPct ⇒ يتفعّل تلقائياً مرة واحدة؛
///   حساب جديد بلا نسب ⇒ يبقى مطفأً.
/// • الواجهة: عند الإطفاء تختفي أعمدة «ربح الطبيب/ربح العيادة» من
///   الأرباح، والصافي = الإيراد − المصروفات، ويظهر مفتاح الإعدادات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/rates/rate_snapshot.dart';
import 'package:dental_clinic_flutter/features/print/treatment_tables.dart'
    show effectiveDoctorPct;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  group('م180 — المنطق النقي', () {
    test('الدلالة الثلاثية: صريح يُحترم، وإرث النسب يفعّل، والجديد مطفأ',
        () {
      final legacy = <String, Object?>{
        'doctorPct': 60,
        'clinicRates': {
          'clinics': {
            'ع1': {'treatments': {'حشو': 70}, 'prosthetics': 40},
          },
        },
      };
      // غياب العلم + نسب قديمة ⇒ مفعّلة (توافق الحسابات القائمة).
      expect(resolveDoctorPct(legacy, clinic: 'ع1', service: 'حشو'), 70);
      // إطفاء صريح ⇒ صفر مهما كانت الإعدادات.
      legacy['ratesEnabled'] = false;
      expect(resolveDoctorPct(legacy, clinic: 'ع1', service: 'حشو'), 0);
      expect(resolveDoctorPct(legacy, clinic: 'ع1', isPros: true), 0);
      // تفعيل صريح ⇒ القيم المضبوطة.
      legacy['ratesEnabled'] = true;
      expect(resolveDoctorPct(legacy, clinic: 'ع1', isPros: true), 40);
      // حساب جديد بلا أي نسب ⇒ مطفأة.
      expect(resolveDoctorPct(const {}, clinic: 'ع1', service: 'حشو'), 0);
    });

    test('لقطة جديدة أثناء الإطفاء تُختم بصفر — وتبقى صفراً بعد التفعيل',
        () {
      // إطفاء صريح (المالك أطفأها من الإعدادات رغم نسبه القديمة).
      final off = <String, Object?>{'doctorPct': 50, 'ratesEnabled': false};
      final snap = buildRateSnapshot(off, clinic: 'ع1', service: 'حشو');
      expect(snap['doctorPct'], 0);
      expect(snap['clinicPct'], 100);
      // سجل حُفظ أثناء الإطفاء: حتى مع تفعيل لاحق تبقى حصته للعيادة.
      final rec = {'amount': 100, '_rateSnapshot': snap};
      expect(effectiveDoctorPct(rec, 50), 0);
    });

    test('اللقطات القديمة محفوظة حرفياً رغم الإطفاء (لقطةً-أولاً)', () {
      final oldRec = {
        'amount': 100,
        '_rateSnapshot': {'v': 1, 'doctorPct': 35, 'clinicPct': 65},
      };
      // fallback صفر (الميزة مطفأة) — اللقطة تتقدم عليه دائماً.
      expect(effectiveDoctorPct(oldRec, 0), 35);
    });

    test('ratesFeatureEnabled: الغياب مطفأة، والإرث يفعّل، والصريح يحسم',
        () {
      expect(ratesFeatureEnabled(const {}), isFalse);
      expect(ratesFeatureEnabled(const {'doctorPct': 50}), isTrue);
      expect(
          ratesFeatureEnabled(const {
            'clinicRates': {'clinics': {'ع1': {}}},
          }),
          isTrue);
      expect(
          ratesFeatureEnabled(
              const {'doctorPct': 50, 'ratesEnabled': false}),
          isFalse);
      expect(ratesFeatureEnabled(const {'ratesEnabled': true}), isTrue);
    });
  });

  group('م180 — الترحيل والواجهة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m180b_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ProviderContainer> boot(
      WidgetTester tester,
      Map<String, Object?> config, {
      void Function(ProviderContainer c)? seed,
    }) async {
      final c = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config);
      seed?.call(c);
      c.dispose();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      return ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
    }

    testWidgets('ترحيل: doctorPct قديم ⇒ ratesEnabled=true تلقائياً',
        (tester) async {
      final c = await boot(tester, {
        'centerName': 'م', 'clinics': ['ع1'], 'services': ['حشو'],
        'payments': ['كاش'], 'doctorPct': 50,
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.read(ratesEnabledProvider), isTrue,
          reason: 'حساب قائم يستعمل النسب يبقى مفعلاً بعد التحديث');
    });

    testWidgets('حساب جديد بلا نسب ⇒ يبقى مطفأً', (tester) async {
      final c = await boot(tester, {
        'centerName': 'م', 'clinics': ['ع1'], 'services': ['حشو'],
        'payments': ['كاش'],
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.read(ratesEnabledProvider), isFalse);
    });

    testWidgets(
        'الأرباح الشهرية عند الإطفاء: لا أعمدة حصص والصافي = إيراد−مصروفات',
        (tester) async {
      final year = '${DateTime.now().year}';
      final month = '${DateTime.now().month}'.padLeft(2, '0');
      await boot(
        tester,
        {
          'centerName': 'م', 'clinics': ['ع1'], 'services': ['حشو'],
          'payments': ['كاش'],
        },
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            {
              'centerName': 'م', 'clinics': ['ع1'],
              'services': ['حشو'], 'payments': ['كاش'],
            },
            SaveRecordInput(
              name: 'أحمد', date: '$year-$month-05', amount: 1000,
              clinic: 'ع1', service: 'حشو', payment: 'كاش',
            ),
          );
          c.read(reposProvider).expenses.upsert({
            'id': 'e1', 'date': '$year-$month-06', 'amount': 100,
            'category': 'كهرباء', 'payment': 'كاش',
          });
        },
      );
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('fin-seg-profits')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // لا أعمدة حصص إطلاقاً.
      expect(find.text('ربح الطبيب'), findsNothing);
      expect(find.text('ربح العيادة'), findsNothing);
      // الإجمالي 1,000 والصافي 900 (كله للعيادة).
      final scroll = find
          .descendant(
            of: find.byKey(const Key('profits-section')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
          find.byKey(const Key('prof-grand-clinic-net')), 200,
          scrollable: scroll);
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('prof-grand-revenue')))
            .data,
        '1,000',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('prof-grand-clinic-net')))
            .data,
        '900',
      );
      // سجلٌ حُفظ أثناء الإطفاء: لقطته صفر (كله للعيادة في البيانات).
      final chk = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      final rec = chk.read(reposProvider).records.getAll().first;
      expect(effectiveDoctorPct(rec, 50), 0);
    });

    testWidgets('مفتاح الإعدادات: يظهر ويخفي بطاقات نسب العيادات',
        (tester) async {
      await boot(tester, {
        'centerName': 'م', 'clinics': ['ع1'], 'services': ['حشو'],
        'payments': ['كاش'],
      });
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final scroll = find
          .byWidgetPredicate((w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down)
          .last;
      await tester.scrollUntilVisible(
          find.byKey(const Key('group-rates')), 300,
          scrollable: scroll);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('group-rates')),
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // مطفأة: المفتاح ظاهر وبطاقة العيادة مخفية.
      expect(find.byKey(const Key('set-rates-enabled')), findsOneWidget);
      expect(find.byKey(const Key('rates-card-ع1')), findsNothing);
      // تفعيلها يُظهر بطاقات العيادات.
      await tester.tap(find.byKey(const Key('set-rates-enabled')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('rates-card-ع1')), findsOneWidget);
    });
  });
}
