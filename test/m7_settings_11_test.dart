/// اختبارات م7 — الإعدادات 1:1 مع الأصل:
///   • وحدات: إعادة تسمية العيادة المتعاقبة، النسخ الاحتياطي JSON ذهاباً
///     وإياباً، xlsx صالح، حساب وقت الدور وقالب رسالته.
///   • واجهة: الوضع الداكن يبدّل النسق ويثبت في metadata، سعر المعالجة
///     يملأ قيمة السجل، شعار مرفوع يصل config ويُعاين ويُحذف، حذف دين
///     بعداد dcConfirm (وإطفاؤه يمرّ مباشرة)، الشريط السفلي والزر العائم،
///     وقت الدور المتوقع للمضافين.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/queue/queue_screen.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/settings_actions.dart';
import 'package:dental_clinic_flutter/features/settings/settings_screen.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m7_'));
  tearDown(() {
    BrandColors.darkMode = false; // لا تسريب بين الاختبارات
    tmp.deleteSync(recursive: true);
  });

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
    'payments': ['كاش'],
    'labs': ['مخبر النور'],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  group('الوحدات — أفعال الإعدادات', () {
    test('إعادة تسمية العيادة تكتسح الجداول الأربعة وقائمة config', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', config());
      repos.records.upsertLocal({
        'id': 'r1',
        'name': 'أ',
        'clinic': 'ع1',
        'amount': 10,
      });
      repos.records.upsertLocal({
        'id': 'r2',
        'name': 'ب',
        'clinic': 'أخرى',
        'amount': 10,
      });
      repos.prosthetics.upsertLocal({
        'id': 'p1',
        'name': 'ج',
        'clinic': 'ع1',
        'total': 100,
      });
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'د',
        'clinic': 'ع1',
        'remaining': 50,
      });
      repos.appointments.upsertLocal({
        'id': 'a1',
        'name': 'هـ',
        'clinic': 'ع1',
      });

      final touched = renameClinicCascade(repos, 'ع1', 'عيادة الرحمة');
      expect(touched, 4);
      expect(repos.records.getById('r1')!['clinic'], 'عيادة الرحمة');
      expect(repos.records.getById('r2')!['clinic'], 'أخرى');
      expect(repos.prosthetics.getById('p1')!['clinic'], 'عيادة الرحمة');
      expect(repos.debts.getById('d1')!['clinic'], 'عيادة الرحمة');
      expect(repos.appointments.getById('a1')!['clinic'], 'عيادة الرحمة');
      final cfg = repos.settings.get('app.config') as Map;
      expect(cfg['clinics'], ['عيادة الرحمة']);
      // مفتاح clinicRates لا يُعاد تسميته — مطابقة حرفية للأصل.
      expect(
        ((cfg['clinicRates'] as Map)['clinics'] as Map).containsKey('ع1'),
        isTrue,
      );
    });

    test('نسخة JSON ذهاباً وإياباً تعيد الصفوف والإعدادات', () {
      final c = container();
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', config());
      repos.records.upsertLocal({
        'id': 'r1',
        'name': 'أ',
        'clinic': 'ع1',
        'amount': 100,
      });
      repos.debts.upsertLocal({
        'id': 'd1',
        'name': 'ب',
        'remaining': 40,
        'status': 'partial',
      });
      final json = buildBackupJson(repos);
      c.dispose();

      // قاعدة جديدة فارغة (مجلد آخر) تستعيد النسخة.
      final tmp2 = Directory.systemTemp.createTempSync('m7b_');
      addTearDown(() => tmp2.deleteSync(recursive: true));
      final c2 = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp2.path),
        ],
      );
      addTearDown(c2.dispose);
      final repos2 = c2.read(reposProvider);
      final count = restoreBackupJson(repos2, json);
      expect(count, 2);
      expect(repos2.records.getById('r1')!['amount'], 100);
      expect(repos2.debts.getById('d1')!['status'], 'partial');
      expect(
        (repos2.settings.get('app.config') as Map)['centerName'],
        'مركز الاختبار',
      );
      // الصفوف المستعادة متقذرة — جاهزة للدفع سحابياً (عمود SQL).
      final dirtyRow = c2.read(localDbProvider).queryFirst(
        'SELECT _dirty AS dirty FROM records WHERE id = ?',
        const ['r1'],
      );
      expect(jsNumOr0(dirtyRow?['dirty']), 1);
    });

    test('xlsx مبني يدوياً: توقيع zip وأوراق عربية Thlaath', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', config());
      repos.records.upsertLocal({
        'id': 'r1',
        'name': 'أ',
        'clinic': 'ع1',
        'service': 'حشو',
        'amount': 100,
        'payment': 'كاش',
        'date': '2026-07-01',
      });
      final bytes = buildBackupXlsx(repos);
      expect(String.fromCharCodes(bytes.take(2)), 'PK');
      final content = String.fromCharCodes(bytes);
      // أسماء أجزاء الأرشيف الثلاثة موجودة.
      expect(content.contains('xl/worksheets/sheet1.xml'), isTrue);
      expect(content.contains('xl/worksheets/sheet3.xml'), isTrue);
    });

    test('وقت الدور: addMinutes مثبت داخل اليوم وقالب الرسالة يملأ', () {
      expect(addMinutesHHMM('09:00', 0), '09:00');
      expect(addMinutesHHMM('09:00', 30), '09:30');
      expect(addMinutesHHMM('23:50', 30), '23:59'); // مثبت
      expect(addMinutesHHMM('', 15), '09:15'); // الافتراضي
      expect(addMinutesHHMM('16:00', 3 * 15), '16:45');

      final msg = buildQueueMsg(
        {'centerName': 'مركزنا', 'queueWaTemplate': null},
        {'patient_name': 'سعاد', 'est_time': '10:15'},
        'ع1',
      );
      expect(msg.contains('سعاد'), isTrue);
      expect(msg.contains('مركزنا'), isTrue);
      expect(msg.contains('ع1'), isTrue);
      expect(msg.contains('10:15'), isTrue);
    });
  });

  group('الواجهة — الإعدادات 1:1', () {
    Future<void> boot(
      WidgetTester tester, {
      void Function(ProviderContainer c)? seed,
      ImagePick? logoPick,
    }) async {
      final c = container();
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
            if (logoPick != null) logoPickProvider.overrideWithValue(logoPick),
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

    Finder vScrollable() => find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;

    Future<void> openGroup(WidgetTester tester, String id) async {
      await tester.scrollUntilVisible(
        find.byKey(Key('group-$id')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('group-$id')), warnIfMissed: false);
      await settle(tester);
    }

    Future<void> hitKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)), warnIfMissed: false);
      await settle(tester);
    }

    testWidgets('الوضع الداكن: التبديل يبدّل النسق ويثبت في metadata', (
      tester,
    ) async {
      await boot(tester);
      expect(BrandColors.darkMode, isFalse);
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await openGroup(tester, 'theme');
      await hitKey(tester, 'theme-dark');
      expect(BrandColors.darkMode, isTrue);
      // ثبت في metadata (توأم dental_theme).
      final c = container();
      addTearDown(c.dispose);
      final row = c.read(localDbProvider).queryFirst(
        'SELECT value FROM metadata WHERE key = ?',
        const ['dental_theme'],
      );
      expect(row?['value'], 'dark');
      // العودة للفاتح.
      await hitKey(tester, 'theme-light');
      expect(BrandColors.darkMode, isFalse);
    });

    testWidgets('سعر المعالجة المحفوظ يملأ قيمة السجل عند اختيارها', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          final cfg = Map<String, Object?>.from(
            repos.settings.get('app.config') as Map,
          );
          repos.settings.set('app.config', {
            ...cfg,
            'servicePrices': {'حشو': 120},
          });
        },
      );
      // م133 — بعد م110+: نموذج الإضافة صار ورقةً سفلية تُفتح من الزر
      // العائم `fab-add` (لا شاشة «الرئيسية» — أصبحت «دخل اليوم» الآن)،
      // فتبويب «الرئيسية» الافتراضي يكفي؛ نفتح الورقة مباشرة.
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('rec-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('حشو').last, warnIfMissed: false);
      await settle(tester);
      final amount = tester.widget<TextField>(
        find.byKey(const Key('rec-amount')),
      );
      expect(amount.controller!.text, '120');
    });

    testWidgets('الشعار: رفع عبر المنتقي المحقون يصل config ثم يُحذف', (
      tester,
    ) async {
      // PNG حقيقي 1×1 (شفاف) — المعاينة تفكّه فعلاً.
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      await boot(tester, logoPick: () async => ('logo.png', png));
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await openGroup(tester, 'center');
      await hitKey(tester, 'logo-upload');

      var c = container();
      var cfg = Map<String, Object?>.from(
        c.read(reposProvider).settings.get('app.config') as Map,
      );
      c.dispose();
      expect('${cfg['logo']}'.startsWith('data:image/png;base64,'), isTrue);
      expect(base64Decode('${cfg['logo']}'.split('base64,').last), png);

      // الحذف يعيد الشعار فارغاً.
      await hitKey(tester, 'logo-remove');
      c = container();
      cfg = Map<String, Object?>.from(
        c.read(reposProvider).settings.get('app.config') as Map,
      );
      c.dispose();
      expect('${cfg['logo']}', '');
    });

    testWidgets(
      'حماية الديون: الإطفاء من مجموعة الحماية يجعل الحذف يمرّ بلا نافذة',
      (tester) async {
        await boot(
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
        // أطفئ تأكيد الديون.
        await tester.tap(find.byTooltip('الإعدادات'));
        await settle(tester);
        await openGroup(tester, 'protect');
        await hitKey(tester, 'dc-on-debt');
        // م92 — رجوعان: من صفحة القسم إلى القائمة ثم من الإعدادات للصدفة.
        await tester.tap(
          find.byKey(const Key('settings-section-back')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
        await settle(tester);

        // احذف الدين — لا نافذة عدّاد.
        await tester.tap(find.text('المالية'), warnIfMissed: false);
        await settle(tester);
        await tester.tap(
          find.byKey(const Key('fin-seg-debts')),
          warnIfMissed: false,
        );
        await settle(tester);
        final c0 = container();
        final debtId = '${c0.read(reposProvider).debts.getAll().single['id']}';
        c0.dispose();
        // م133 — لا زر «كباب» ظاهرٌ في DebtCard الحالية؛ الضغط المطوّل على
        // البطاقة نفسها يفتح قائمة ورقية سفلية (`_openDebtMenu`)، وعنصر
        // الحذف فيها بلا Key فنطاله بنصّه («حذف الدين»).
        await tester.ensureVisible(find.byKey(Key('debt-card-$debtId')));
        await tester.pumpAndSettle();
        await tester.longPress(
          find.byKey(Key('debt-card-$debtId')),
          warnIfMissed: false,
        );
        await settle(tester);
        await tester.tap(find.text('حذف الدين'), warnIfMissed: false);
        await settle(tester);
        expect(find.byKey(const Key('dc-confirm')), findsNothing);
        final chk = container();
        addTearDown(chk.dispose);
        expect(chk.read(reposProvider).debts.getAll(), isEmpty);
      },
    );

    testWidgets('شريط تبويبات سفلي + الزر العائم يقفز للرئيسية', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          final cfg = Map<String, Object?>.from(
            repos.settings.get('app.config') as Map,
          );
          repos.settings.set('app.config', {
            ...cfg,
            'tabBarPosition': 'bottom',
            'fabVisible': true,
            'fabPosition': 'center',
          });
        },
      );
      // م172 — الزر العائم «+» صار في «الرئيسية» فقط (قرار المالك):
      // نبقى عليها — الشريط السفلي يُفحص من هنا (ظاهر بكل التبويبات).
      // الشريط السفلي: تبويب المالية يقع أسفل منتصف الشاشة.
      final fin = tester.getCenter(find.text('المالية'));
      final h = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(fin.dy > h / 2, isTrue);
      // الزر العائم ظاهر ويفتح نموذج الإضافة.
      expect(find.byKey(const Key('fab-add')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fab-add')));
      await settle(tester);
      // م133 — بعد م110+: الزر يفتح ورقةً سفلية (`openAddRecordSheet`) لا
      // شاشةً تستبدل الصدفة، فالزر العائم يبقى في الشجرة تحت الورقة —
      // الجوهر المطلوب هو ظهور نموذج الإضافة، لا اختفاء الزر.
      expect(find.byKey(const Key('rec-service')), findsOneWidget);
    });

    testWidgets('الدور: المضاف يحمل وقتاً متوقعاً من إعدادات التوقيت', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          final cfg = Map<String, Object?>.from(
            repos.settings.get('app.config') as Map,
          );
          repos.settings.set('app.config', {
            ...cfg,
            'bookingSystem': 'queue', // الافتراضي الحقيقي تقليدي
            'queueMorningStart': '10:00',
            'queueSlotMin': 20,
          });
        },
      );
      await tester.tap(find.text('الحجوزات'), warnIfMissed: false);
      await settle(tester);
      await tester.tap(find.byKey(const Key('clinic-ع1')), warnIfMissed: false);
      await settle(tester);
      // م177 — الإضافة صارت ورقةً منبثقة من الزر الدائري.
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('queue-fab-add')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('queue-add-name')), 'سعاد');
      await tester.tap(
        find.byKey(const Key('queue-add-go')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.enterText(find.byKey(const Key('queue-add-name')), 'ليلى');
      await tester.tap(
        find.byKey(const Key('queue-add-go')),
        warnIfMissed: false,
      );
      await settle(tester);
      // م177 — إغلاق الورقة (نقرة خارجها) يحرّر مساحة القائمة.
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      final chk = container();
      addTearDown(chk.dispose);
      final rows =
          chk.read(reposProvider).queue.getByClinicDate('ع1', getCurrentDate())
            ..sort((a, b) => jsNumOr0(a['seq']).compareTo(jsNumOr0(b['seq'])));
      expect(rows, hasLength(2));
      expect(rows[0]['est_time'], '10:00'); // (1-1)×20
      expect(rows[1]['est_time'], '10:20'); // (2-1)×20
      // م56/v62 — بنظام ١٢ ساعة: وقت الأول يظهر مرتين (لوحة «التالي»
      // البطلة + بطاقته)، والثاني على بطاقته فقط.
      expect(find.textContaining('🕐 10:00 AM'), findsNWidgets(2));
      expect(find.textContaining('🕐 10:20 AM'), findsOneWidget);
    });

    // م179 — اختبار واجهة «استعادة JSON» حُذف: بطاقة النسخ الاحتياطي
    // أُلغيت بالكامل (قرار المالك). المنطق النقي (buildBackupJson /
    // restoreBackupJson) يبقى مختبَراً في مجموعة الوحدات أعلاه.
  });
}
