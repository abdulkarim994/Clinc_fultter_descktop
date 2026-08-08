/// اختبار م58 — ورقة الزيارة السريعة (الدائرة العائمة في ملف المريض):
///   • الدائرة تفتح ورقة مختزلة بهوية المريض (لا حقول اسم/هاتف)
///   • اختيار المعالجة يملأ سعرها تلقائياً ويبقى حراً للتعديل
///   • الحفظ يمر بمسار saveNewRecord الموحد: سجل جديد بعيادة المريض
///     واسمه وهاتفه المعروف، مختوم dirty للمزامنة
///   • وضع «دين» بدفعة أولى ينشئ الدين المرتبط بنفس منطق الرئيسية
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m58_'));
  tearDown(() {
    BrandColors.darkMode = false;
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> boot(WidgetTester tester) async {
    final c = container();
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز م58',
      'clinics': ['ع1'],
      'services': ['حشو', 'خلع', 'تركيبات'],
      'payments': ['كاش', 'تحويل'],
      'servicePrices': {'حشو': 120},
      'labs': ['مخبر النور'],
      'labTypes': [
        {'name': 'زيركون', 'defaultPrice': 300},
      ],
    });
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'أحمد',
      'patient_name': 'أحمد',
      'clinic': 'ع1',
      'service': 'خلع',
      'amount': 50,
      'payment': 'كاش',
      'phone': '0911111111',
      'date': getCurrentDate(),
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
    await tester.pump(const Duration(milliseconds: 200));
    // فتح السجلات ← العيادة ← ملف المريض.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await settle(tester);
    await tester.tap(
      find.byKey(const Key('clinic-card-ع1')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(find.text('أحمد').first, warnIfMissed: false);
    await settle(tester);
  }

  testWidgets(
    'الدائرة العائمة: اختيار المعالجة يملأ السعر والحفظ يسجل الزيارة',
    (tester) async {
      await boot(tester);

      await tester.tap(
        find.byKey(const Key('pp-add-visit')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(
        find.text('زيارة جديدة — أحمد'),
        findsOneWidget,
        reason: 'هوية المريض في العنوان — لا حقل اسم',
      );

      // اختيار المعالجة يملأ سعرها (سلوك م55).
      await tester.tap(
        find.byKey(const Key('qv-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('حشو').last, warnIfMissed: false);
      await settle(tester);
      final amount = tester.widget<TextField>(
        find.byKey(const Key('qv-amount')),
      );
      expect(amount.controller!.text, '120');

      // تعديل حر ثم حفظ. م60 — طريقة الدفع صارت قائمة منسدلة (qv-pay).
      await tester.enterText(find.byKey(const Key('qv-amount')), '150');
      await tester.tap(find.byKey(const Key('qv-pay')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.text('تحويل').last, warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.byKey(const Key('qv-save')), warnIfMissed: false);
      await settle(tester);

      // السجل حُفظ بمسار الرئيسية الموحد: عيادة المريض واسمه وهاتفه.
      final c = container();
      addTearDown(c.dispose);
      final recs = c
          .read(reposProvider)
          .records
          .getAll()
          .where((r) => r['service'] == 'حشو')
          .toList();
      expect(recs, hasLength(1));
      expect(recs.first['name'], 'أحمد');
      expect(recs.first['clinic'], 'ع1');
      expect(jsNumOr0(recs.first['amount']), 150);
      expect(recs.first['payment'], 'تحويل');
      expect(
        recs.first['phone'],
        '0911111111',
        reason: 'الهاتف المعروف يرافق السجل بلا حقل ظاهر',
      );
      expect(
        jsNumOr0(recs.first['_dirty']),
        1,
        reason: 'مختوم للمزامنة الفورية',
      );
    },
  );

  testWidgets(
    'م59: تركيبة من النافذة — النوع يملأ سعر الوحدة وقيمة المخبر تُحسب وتُحفظ في جدول التركيبات',
    (tester) async {
      await boot(tester);

      await tester.tap(
        find.byKey(const Key('pp-add-visit')),
        warnIfMissed: false,
      );
      await settle(tester);

      // اختيار «تركيبات» يُظهر القسم المضغوط.
      await tester.tap(
        find.byKey(const Key('qv-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('تركيبات').last, warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('qv-prostype')), findsOneWidget);

      // النوع يملأ سعر الوحدة الافتراضي وقيمة المخبر (1 × 300).
      await tester.tap(
        find.byKey(const Key('qv-prostype')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('زيركون').last, warnIfMissed: false);
      await settle(tester);
      var unitPrice = tester.widget<TextField>(
        find.byKey(const Key('qv-unitprice')),
      );
      expect(unitPrice.controller!.text, '300');
      var labValue = tester.widget<TextField>(
        find.byKey(const Key('qv-labvalue')),
      );
      expect(labValue.controller!.text, '300');

      // وحدتان ⇒ قيمة المخبر 600.
      await tester.enterText(find.byKey(const Key('qv-units')), '2');
      await settle(tester);
      labValue = tester.widget<TextField>(find.byKey(const Key('qv-labvalue')));
      expect(labValue.controller!.text, '600');

      // اختيار المخبر + الإجمالي 900 ثم حفظ.
      await tester.tap(find.byKey(const Key('qv-lab')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.text('مخبر النور').last, warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('qv-amount')), '900');
      await tester.tap(find.byKey(const Key('qv-save')), warnIfMissed: false);
      await settle(tester);

      // الحفظ في جدول التركيبات بفرع ip الحرفي.
      final c = container();
      addTearDown(c.dispose);
      final pros = c.read(reposProvider).prosthetics.getAll();
      expect(pros, hasLength(1));
      expect(pros.first['name'], 'أحمد');
      expect(jsNumOr0(pros.first['total']), 900);
      expect(jsNumOr0(pros.first['labValue']), 600);
      expect(pros.first['prosType'], 'زيركون');
      expect(jsNumOr0(pros.first['prosUnits']), 2);
      expect(pros.first['labName'], 'مخبر النور');
    },
  );

  testWidgets('وضع دين بدفعة أولى ينشئ الدين المرتبط بمنطق الرئيسية نفسه', (
    tester,
  ) async {
    await boot(tester);

    await tester.tap(
      find.byKey(const Key('pp-add-visit')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('qv-service')), warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.text('حشو').last, warnIfMissed: false);
    await settle(tester);
    // تفعيل الدين + دفعة أولى 40 من 120.
    await tester.tap(find.byKey(const Key('qv-debt')), warnIfMissed: false);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('qv-firstpay')), '40');
    await tester.tap(find.byKey(const Key('qv-save')), warnIfMissed: false);
    await settle(tester);

    final c = container();
    addTearDown(c.dispose);
    final debts = c.read(reposProvider).debts.getAll();
    expect(debts, hasLength(1));
    expect(debts.first['name'], 'أحمد');
    expect(
      jsNumOr0(debts.first['remaining']),
      80,
      reason: '120 - دفعة أولى 40 = 80 متبقياً',
    );
  });

  testWidgets('م60: التخطيط الجديد يعرض العناصر المطلوبة والحاسبة', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(
      find.byKey(const Key('pp-add-visit')),
      warnIfMissed: false,
    );
    await settle(tester);
    // الحاسبة في الزاوية + تحديد الأسنان + القيمة والدفع في التخطيط.
    expect(find.byKey(const Key('qv-calc')), findsOneWidget);
    expect(find.byKey(const Key('qv-teeth')), findsOneWidget);
    expect(find.byKey(const Key('qv-amount')), findsOneWidget);
    expect(find.byKey(const Key('qv-date')), findsOneWidget);
    expect(find.text('تحديد الأسنان'), findsOneWidget);
  });

  testWidgets('م60: الحاسبة تحسب وتُدرج الناتج في حقل القيمة', (tester) async {
    await boot(tester);
    await tester.tap(
      find.byKey(const Key('pp-add-visit')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('qv-calc')), warnIfMissed: false);
    await settle(tester);
    // 120 + 30 = 150 ثم إدراج.
    for (final k in ['1', '2', '0', '+', '3', '0']) {
      await tester.tap(find.byKey(Key('calc-$k')), warnIfMissed: false);
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('calc-insert')), warnIfMissed: false);
    await settle(tester);
    final amount = tester.widget<TextField>(find.byKey(const Key('qv-amount')));
    expect(
      amount.controller!.text,
      '150',
      reason: 'ناتج الحاسبة أُدرج في القيمة',
    );
  });

  testWidgets('م61: عملية النسبة المئوية في الحاسبة (200 × 50% = 100)', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(
      find.byKey(const Key('pp-add-visit')),
      warnIfMissed: false,
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('qv-calc')), warnIfMissed: false);
    await settle(tester);
    for (final k in ['2', '0', '0', '×', '5', '0', '%', '=']) {
      await tester.tap(find.byKey(Key('calc-$k')), warnIfMissed: false);
      await tester.pump();
    }
    final display = tester.widget<Text>(find.byKey(const Key('calc-display')));
    expect(display.data, '100', reason: '50% ⇒ 0.5 ثم 200 × 0.5 = 100');
  });
}
