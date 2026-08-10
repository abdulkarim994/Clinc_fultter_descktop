/// اختبارات م4ب — الماليات فوق دوال المجاميع المثبتة + الإعدادات:
/// أرقام التقرير الشهري تطابق التوقع اليدوي على الشاشة، سداد دين من تبويب
/// المالية يقلب حالته، وتعديلات الإعدادات (عيادة/معالجة/نسب/اسم المركز)
/// تصل القاعدة وتنعكس في الهيدر والمحلّل فوراً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/rates/rate_snapshot.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinicRates': {
      'clinics': {
        'ع1': {
          'treatments': {'حشو': 40},
          'prosthetics': 30,
        },
      },
    },
    'clinics': ['ع1'],
    'services': ['حشو', 'تركيبات'],
    'payments': ['كاش', 'تحويل'],
  };

  setUp(() => tmp = Directory.systemTemp.createTempSync('m4b_'));
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
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // المُمرَّر العمودي فقط (حقول النص تحوي Scrollable أفقياً يشوّش .first).
  Finder vScrollable() => find
      .byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical,
      )
      .first;

  group('تبويب المالية (محور الخزينة/الديون/الأرباح)', () {
    testWidgets('الخزينة: بطاقات العيادة والإجمالي تطابق الحساب اليدوي', (
      tester,
    ) async {
      await seedAndBoot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          final today = getCurrentDate();
          // كاش 100 بنسبة 40 + تحويل 200 بنسبة 40 (لقطات) + تركيبة 500/مخبر 200
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'أ',
              date: today,
              amount: 100,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
            ),
          );
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'ب',
              date: today,
              amount: 200,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'تحويل',
            ),
          );
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'ج',
              date: today,
              amount: 500,
              clinic: 'ع1',
              service: 'تركيبات',
              payment: 'كاش',
              labValue: 200,
            ),
          );
          // دين هذا الشهر بدفعة أولى 100 ومتبقٍ 150
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'د',
              date: today,
              amount: 250,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
              isDebt: true,
              firstPay: 100,
            ),
          );
        },
      );

      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      // م108 — «المالية» صارت قائمة أقسام (بطاقات)، والخزينة قسمٌ يُفتح
      // بنقرة بطاقته؛ لم تكن كذلك حين كُتب الاختبار أصلاً.
      await tester.tap(
        find.byKey(const Key('fin-seg-treasury')),
        warnIfMissed: false,
      );
      await settle(tester);

      // م154 — الخزينة الجديدة: صف العيادة بإجماليها الشهري
      // (كاش 200 + تحويل 200 + تركيبات مدفوعة 500 = 900).
      expect(find.byKey(const Key('treasury-main')), findsOneWidget);
      expect(find.byKey(const Key('tr2-row-ع1')), findsOneWidget);
      expect(find.textContaining('900'), findsOneWidget);
      expect(find.byKey(const Key('tr2-row-anal')), findsOneWidget);
      expect(find.byKey(const Key('tr2-row-exp')), findsOneWidget);

      // تفصيل العيادة: جدول الحركات — المجموع الظاهر (الكل) = 400.
      await tester.tap(
        find.byKey(const Key('tr2-row-ع1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('tr2-visible-total')))
              .data,
          '400');
      expect(find.textContaining('دفعة أولى'), findsOneWidget);

      // الأرباح: إجمالي إيرادات الشهر = سجلات 400 + تركيبات 500 = 900.
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('fin-seg-profits')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('900'), findsWidgets);
    });

    testWidgets('v52: خيار الإعدادات يخفي شارة عدد الديون في المالية', (
      tester,
    ) async {
      await seedAndBoot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          // إعادة كتابة الإعدادات بالعلم مطفأً + دين مفتوح.
          repos.settings.set('app.config', {
            ...config(),
            'showDebtCountBadge': false,
          });
          saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'س',
              date: getCurrentDate(),
              amount: 250,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
              isDebt: true,
              firstPay: 100,
            ),
          );
        },
      );
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      // م133 — م125 حذفت ميزة شارة عدد الديون نهائياً (مزوّدها ومفتاح
      // إعدادها معاً)، فمفتاح fin-debt-badge لم يبق له أثر في lib/ إطلاقاً
      // بصرف النظر عن showDebtCountBadge؛ يبقى التأكيد صحيحاً (الشارة
      // غائبة رغم دين مفتوح) لكنه الآن يشهد على الحذف الدائم لا الخيار.
      expect(find.byKey(const Key('fin-debt-badge')), findsNothing);
      // م154 — الخزينة الجديدة بلا ذيل ديون (الديون في تبويبها):
      // نكتفي بفتح الخزينة والتأكد من صفوفها الجديدة.
      await tester.tap(
        find.byKey(const Key('fin-seg-treasury')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('tr2-row-ع1')), findsOneWidget);
    });

    testWidgets(
      'الديون: سداد قسط بتاريخ وطريقة دفع يقفل الدين وينشئ سجل الدفعة',
      (tester) async {
        await seedAndBoot(
          tester,
          seed: (c) {
            saveNewRecord(
              c.read(reposProvider),
              config(),
              SaveRecordInput(
                name: 'هند',
                date: getCurrentDate(),
                amount: 300,
                clinic: 'ع1',
                service: 'حشو',
                payment: 'كاش',
                isDebt: true,
                firstPay: 100,
              ),
            );
          },
        );
        await tester.tap(find.text('المالية'), warnIfMissed: false);
        await settle(tester);
        await tester.tap(
          find.byKey(const Key('fin-seg-debts')),
          warnIfMissed: false,
        );
        await settle(tester);

        // بطاقة الدين التوأم — الاسم والخدمة سطران وزر «تسجيل دفعة» ظاهر.
        // م133 — م110 حوّل البطاقة لجدول: السطر الفرعي يجمع نوع العلاج
        // وطريقة الدفع في نص واحد «حشو • كاش» لا نصين مستقلين.
        expect(find.text('هند'), findsWidgets);
        expect(find.textContaining('حشو'), findsWidgets);
        final chk0 = ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );
        final debtId =
            '${chk0.read(reposProvider).debts.getAll().single['id']}';
        chk0.dispose();
        await tester.ensureVisible(find.byKey(Key('debt-pay-$debtId')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key('debt-pay-$debtId')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.enterText(find.byKey(const Key('inst-amount')), '200');
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('inst-confirm')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.text('تم سداد الدين بالكامل!'), findsOneWidget);

        final chk = ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );
        addTearDown(chk.dispose);
        final d = chk.read(reposProvider).debts.getAll().single;
        expect(d['status'], 'paid');
        expect(jsNumOr0(d['remaining']), 0);
        expect((d['installments'] as List), hasLength(2));
        // سجل الدفعة المرتبط أُنشئ (يتغذى عليه الأرشيف والخزينة).
        final pays = chk
            .read(reposProvider)
            .records
            .getAll()
            .where((r) => jsNumOr0(r['isDebtPayment']) == 1)
            .toList();
        expect(pays, hasLength(2)); // الدفعة الأولى + قسط الإقفال
        expect(
          pays.any((r) => '${r['service']}'.startsWith('دفعة دين —')),
          isTrue,
        );
      },
    );

    testWidgets('تعديل الدين يعيد الاشتقاق وحذفه يزيل السجلات المرتبطة', (
      tester,
    ) async {
      await seedAndBoot(
        tester,
        seed: (c) {
          saveNewRecord(
            c.read(reposProvider),
            config(),
            SaveRecordInput(
              name: 'سعاد',
              date: getCurrentDate(),
              amount: 300,
              clinic: 'ع1',
              service: 'حشو',
              payment: 'كاش',
              isDebt: true,
              firstPay: 100,
            ),
          );
        },
      );
      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('fin-seg-debts')),
        warnIfMissed: false,
      );
      await settle(tester);
      final chk0 = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final debtId = '${chk0.read(reposProvider).debts.getAll().single['id']}';
      chk0.dispose();

      // م133 — م110 استبدل بطاقة الدين المطوية بجدول؛ قائمة الكباب صارت
      // ورقة خيارات سفلية (_openDebtMenu) تُفتح بالضغط المطول على صفّ
      // الدين، وعناصرها Text بلا مفاتيح فيُنقر عليها بنصها.
      // تعديل الإجمالي 300 ← 400: المتبقي يصبح 300 والحالة partial.
      await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(Key('debt-card-$debtId')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('تعديل بيانات الدين'), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('edit-debt-total')), '400');
      await tester.tap(
        find.byKey(const Key('edit-debt-save')),
        warnIfMissed: false,
      );
      await settle(tester);
      var chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      var d = chk.read(reposProvider).debts.getAll().single;
      expect(jsNumOr0(d['remaining']), 300);
      expect(d['status'], 'partial');
      // السجل الأصلي المرتبط تحدّث مبلغه أيضاً.
      final original = chk
          .read(reposProvider)
          .records
          .getAll()
          .firstWhere((r) => jsNumOr0(r['isDebtPayment']) != 1);
      expect(jsNumOr0(original['amount']), 400);
      chk.dispose();

      // الحذف بتأكيد مزدوج يزيل الدين وسجلاته — عبر ورقة الخيارات (نصاً).
      await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(Key('debt-card-$debtId')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('حذف الدين'), warnIfMissed: false);
      await settle(tester);
      // نافذة DoubleConfirm: الزر لا يعمل قبل انتهاء العداد (3 ثوانٍ).
      expect(find.byKey(const Key('dc-countdown')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('dc-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);
      // ما يزال الحوار قائماً (الضغط المبكر لا يمرّ).
      expect(find.byKey(const Key('dc-confirm')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(
        find.byKey(const Key('dc-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);
      chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      expect(chk.read(reposProvider).debts.getAll(), isEmpty);
      expect(chk.read(reposProvider).records.getAll(), isEmpty);
    });
  });

  group('الإعدادات', () {
    testWidgets(
      'اسم المركز وإضافة عيادة ونِسَبها تنعكس في الهيدر والقاعدة والمحلّل',
      (tester) async {
        await seedAndBoot(tester);
        expect(find.text('مركز الاختبار'), findsOneWidget);

        await tester.tap(find.byTooltip('الإعدادات'));
        await settle(tester);
        expect(find.text('الإعدادات'), findsWidgets);

        // اسم المركز — داخل مجموعة «معلومات المركز» المطوية
        await tester.tap(
          find.byKey(const Key('group-center')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('center-name-input')),
          'مركز الشفاء',
        );
        await tester.tap(
          find.byKey(const Key('center-name-save')),
          warnIfMissed: false,
        );
        await settle(tester);
        // تصريف Snackbar «تم الحفظ» كي لا يحجب رؤوس المجموعات السفلية.
        await tester.pump(const Duration(seconds: 5));
        // م92 — عُد للقائمة الرئيسية (كان: نقرة ثانية تطوي الأكورديون).
        await tester.tap(
          find.byKey(const Key('settings-section-back')),
          warnIfMissed: false,
        );
        await settle(tester);

        // إضافة عيادة — قسم «العيادات والمعالجات»
        await tester.tap(
          find.byKey(const Key('group-clinic')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.scrollUntilVisible(
          find.byKey(const Key('new-clinic-input')),
          250,
          scrollable: vScrollable(),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('new-clinic-input')),
          'عيادة الفتح',
        );
        await tester.ensureVisible(find.byKey(const Key('add-clinic')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('add-clinic')),
          warnIfMissed: false,
        );
        await settle(tester);
        // الصف المعروض (الحقل فُرِّغ بعد الإضافة): الإضافة وصلت فعلاً.
        expect(find.text('عيادة الفتح'), findsOneWidget);
        // م92 — رجوعٌ للقائمة ثم فتح قسم النسب.
        await tester.tap(
          find.byKey(const Key('settings-section-back')),
          warnIfMissed: false,
        );
        await settle(tester);

        // نِسَب العيادة الجديدة: تركيبات 35٪ وحشو 45٪ — لوحة سفلية
        await tester.ensureVisible(find.byKey(const Key('group-rates')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('group-rates')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.scrollUntilVisible(
          find.byKey(const Key('rates-card-عيادة الفتح')),
          250,
          scrollable: vScrollable(),
        );
        await tester.ensureVisible(
          find.byKey(const Key('rates-card-عيادة الفتح')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('rates-card-عيادة الفتح')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.enterText(find.byKey(const Key('rate-input-pros')), '35');
        await tester.enterText(find.byKey(const Key('rate-input-حشو')), '45');
        await tester.tap(
          find.byKey(const Key('rates-save')),
          warnIfMissed: false,
        );
        await settle(tester);

        // العودة للصدفة: رجوعان (القسم ثم الشاشة) — الهيدر تغيّر
        await tester.tap(
          find.byKey(const Key('settings-section-back')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
        await settle(tester);
        expect(find.text('مركز الشفاء'), findsOneWidget);

        // القاعدة والمحلّل
        final chk = ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );
        addTearDown(chk.dispose);
        final cfg = Map<String, Object?>.from(
          chk.read(reposProvider).settings.get('app.config') as Map,
        );
        expect(cfg['centerName'], 'مركز الشفاء');
        expect((cfg['clinics'] as List), contains('عيادة الفتح'));
        expect(resolveDoctorPct(cfg, clinic: 'عيادة الفتح', isPros: true), 35);
        expect(
          resolveDoctorPct(cfg, clinic: 'عيادة الفتح', service: 'حشو'),
          45,
        );
        // نسب ع1 الأصلية لم تُمس
        expect(resolveDoctorPct(cfg, clinic: 'ع1', service: 'حشو'), 40);
      },
    );

    testWidgets('حذف معالجة بالرقاقة يزيلها من القائمة والقاعدة', (
      tester,
    ) async {
      await seedAndBoot(tester);
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('group-clinic')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م142 — «تركيبات» (الفهرس 1) صارت معالجةً محميّةً بلا زر حذف؛ نحذف
      // «حشو» (الفهرس 0، قابلة للحذف) لاختبار آلية الحذف بالرقاقة نفسها.
      await tester.scrollUntilVisible(
        find.byKey(const Key('svc-del-0')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('svc-del-0')), warnIfMissed: false);
      await settle(tester);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final cfg = Map<String, Object?>.from(
        chk.read(reposProvider).settings.get('app.config') as Map,
      );
      expect((cfg['services'] as List), isNot(contains('حشو')));
      expect((cfg['services'] as List), contains('تركيبات'));
    });
  });
}
