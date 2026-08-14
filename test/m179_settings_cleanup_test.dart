/// اختبارات م179 — تنظيف الإعدادات (قرارات المالك):
/// • الخيارات المحذوفة اختفت فعلاً: حفظ التبويب، العودة التلقائية،
///   إظهار الزر العائم، مفتاح/نافذة/«أرشفة الآن» للأرشفة، النسخ الاحتياطي.
/// • شريط التبويبات **أسفل افتراضياً** (بلا أي إعداد) والزر العائم ظاهر.
/// • قسم «حول التطبيق»: بلا بطاقة حالة المزامنة، وفيه واتساب + بريد.
/// • **علة سعر التحاليل الثلاثية**: الخروج من الإعدادات والعودة يجب أن
///   يُظهر السعر المحفوظ في الحقل لا حقلاً فارغاً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show kTriAnalysesCfgKey, triAnalysesPrice;
import 'package:dental_clinic_flutter/features/settings/settings_screen.dart'
    show kDeveloperEmail;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m179_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'services': ['حشو'],
        'payments': ['كاش'],
      };

  ProviderContainer container() => ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);

  Future<void> boot(WidgetTester tester,
      {void Function(ProviderContainer c)? seed}) async {
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
      .byWidgetPredicate((w) =>
          w is Scrollable && w.axisDirection == AxisDirection.down)
      .last;

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('الإعدادات'));
    await settle(tester);
  }

  /// الخروج من الإعدادات كما يفعل المستخدم: رجوعٌ من القسم إلى المحور
  /// ثم رجوعٌ من المحور إلى التطبيق (لا AppBar قياسي هنا).
  Future<void> leaveSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-section-back')),
        warnIfMissed: false);
    await settle(tester);
    await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
    await settle(tester);
  }

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

  group('م179 — الخيارات المحذوفة', () {
    testWidgets('الإشعارات: بلا «حفظ التبويب» ولا «العودة التلقائية»',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'notif');
      // التذكير باقٍ، والخيارَان اختفيا.
      expect(find.byKey(const Key('set-apptnotif')), findsOneWidget);
      expect(find.byKey(const Key('set-keeptab')), findsNothing);
      expect(find.byKey(const Key('set-followup')), findsNothing);
    });

    testWidgets('المظهر: بلا مفتاح «إظهار الزر العائم» ومواقعه باقية',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'theme');
      await tester.scrollUntilVisible(
        find.byKey(const Key('fab-center')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-visible')), findsNothing);
      expect(find.byKey(const Key('fab-center')), findsOneWidget);
      expect(find.byKey(const Key('tabbar-top')), findsOneWidget);
      expect(find.byKey(const Key('tabbar-bottom')), findsOneWidget);
    });

    testWidgets('التخزين: بلا نسخٍ احتياطي ولا تحكّم بالأرشفة',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'storage');
      // النسخ الاحتياطي بأزراره الثلاثة أُلغي بالكامل.
      expect(find.byKey(const Key('export-excel')), findsNothing);
      expect(find.byKey(const Key('export-json')), findsNothing);
      expect(find.byKey(const Key('import-json')), findsNothing);
      // تحكّم الأرشفة أُزيل (المفتاح والنافذة وأرشفة الآن).
      expect(find.byKey(const Key('set-archive')), findsNothing);
      expect(find.byKey(const Key('archive-window')), findsNothing);
      expect(find.byKey(const Key('archive-now')), findsNothing);
      // المزامنة نفسها باقية كما هي.
      expect(find.byKey(const Key('set-autosync')), findsOneWidget);
    });
  });

  group('م179 — حول التطبيق', () {
    testWidgets('بلا بطاقة حالة المزامنة، وفيه واتساب وبريد المطور',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'about');
      expect(find.text('حالة التطبيق والمزامنة'), findsNothing);
      expect(find.text('آخر مزامنة ناجحة'), findsNothing);
      expect(find.byKey(const Key('support-wa')), findsOneWidget);
      expect(find.byKey(const Key('support-mail')), findsOneWidget);
      expect(find.text(kDeveloperEmail), findsOneWidget);
      // نسخة التطبيق تبقى مرجعاً للتحقق.
      expect(find.byKey(const Key('appinfo-version')), findsOneWidget);
      // م179/ب — تنبيه المحجور عاد بطلب المالك لكنه **مشروط**: صفر
      // عناصر محجورة (حالة هذا الاختبار) = لا بطاقة ولا زر إطلاقاً.
      expect(find.byKey(const Key('quarantine-notice')), findsNothing);
      expect(find.byKey(const Key('quarantine-retry')), findsNothing);
    });
  });

  group('م179 — الافتراضيات المثبَّتة', () {
    testWidgets('شريط التبويبات أسفل بلا إعداد، والزر العائم ظاهر',
        (tester) async {
      await boot(tester); // config() بلا tabBarPosition ولا fabVisible
      // الزر العائم ظاهر افتراضياً.
      expect(find.byKey(const Key('fab-add')), findsOneWidget);
      // أسفل: مركز شريط التبويبات في النصف السفلي من الشاشة.
      final tabY = tester.getCenter(find.text('الحجوزات')).dy;
      final h = tester.getSize(find.byType(MaterialApp)).height;
      expect(tabY, greaterThan(h / 2),
          reason: 'الشريط يجب أن يكون أسفل افتراضياً');
    });
  });

  group('م179 — علة سعر التحاليل الثلاثية', () {
    testWidgets('السعر المحفوظ يظهر في الحقل بعد الخروج والعودة',
        (tester) async {
      await boot(tester, seed: (c) {
        final repos = c.read(reposProvider);
        final cfg = repos.settings.get('app.config') as Map<String, Object?>;
        repos.settings.set('app.config', {
          ...cfg,
          kTriAnalysesCfgKey: {
            'price': 150,
            'enabled': true,
            'repeatMonths': 6,
          },
        }, configBase: cfg);
      });
      await openSettings(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      // القيمة المخزّنة ظاهرة في الحقل من أول فتحة.
      expect(
        tester.widget<TextField>(find.byKey(const Key('tri-anal-price')))
            .controller!
            .text,
        '150',
      );

      // الخروج من الإعدادات ثم العودة — الحقل يجب أن يبقى مملوءاً.
      await leaveSettings(tester);
      await openSettings(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('tri-anal-price')))
            .controller!
            .text,
        '150',
        reason: 'العلة: الحقل كان يرجع فارغاً والقيمة محفوظة',
      );
      // والقيمة في الإعدادات لم تُمسّ.
      final chk = container();
      addTearDown(chk.dispose);
      expect(triAnalysesPrice(chk.read(appConfigProvider)), 150);
    });

    // 🔴 السبب الجذري (م179): `_closeSection` كانت تلتزم بسعر التحاليل
    // **دائماً** عند إغلاق أي قسم — ومتحكم الحقل يبدأ فارغاً إن لم تُبنَ
    // بطاقة التحاليل في الجلسة، فتُكتب القيمة 0 فوق السعر المحفوظ. أي:
    // «افتح الإعدادات ← أي قسم ← رجوع» كان يمحو السعر. هذا هو بلاغ المالك.
    testWidgets('الانحدار: إغلاق قسمٍ آخر لا يمحو سعر التحاليل المحفوظ',
        (tester) async {
      await boot(tester, seed: (c) {
        final repos = c.read(reposProvider);
        final cfg = repos.settings.get('app.config') as Map<String, Object?>;
        repos.settings.set('app.config', {
          ...cfg,
          kTriAnalysesCfgKey: {
            'price': 150,
            'enabled': true,
            'repeatMonths': 6,
          },
        }, configBase: cfg);
      });
      await openSettings(tester);
      // قسمٌ لا يحتوي بطاقة التحاليل إطلاقاً.
      await openGroup(tester, 'theme');
      await tester.tap(find.byKey(const Key('settings-section-back')),
          warnIfMissed: false);
      await settle(tester);

      final chk = container();
      addTearDown(chk.dispose);
      expect(triAnalysesPrice(chk.read(appConfigProvider)), 150,
          reason: 'إغلاق قسمٍ آخر لا يجوز أن يمس سعر التحاليل');
    });

    testWidgets('الانحدار: الخروج الكامل من الإعدادات لا يمحو السعر',
        (tester) async {
      await boot(tester, seed: (c) {
        final repos = c.read(reposProvider);
        final cfg = repos.settings.get('app.config') as Map<String, Object?>;
        repos.settings.set('app.config', {
          ...cfg,
          kTriAnalysesCfgKey: {
            'price': 200,
            'enabled': true,
            'repeatMonths': 6,
          },
        }, configBase: cfg);
      });
      await openSettings(tester);
      await openGroup(tester, 'notif');
      await leaveSettings(tester);

      final chk = container();
      addTearDown(chk.dispose);
      expect(triAnalysesPrice(chk.read(appConfigProvider)), 200);
    });

    testWidgets('التحصين: قيمة محفوظة لا يفرّغها الحقل ولو تأخرت النبضة',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      // كتابة في المخزن **بلا** نبضة إعادة قراءة (configRev لم يزد):
      // تحاكي اللقطة المتأخرة التي كانت تُفرِّغ الحقل — عبر حاوية
      // التطبيق نفسها كي تحمل الكتابة مالكَ الجلسة الصحيح.
      final appC = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      final repos = appC.read(reposProvider);
      final cfg = repos.settings.get('app.config') as Map<String, Object?>;
      repos.settings.set('app.config', {
        ...cfg,
        kTriAnalysesCfgKey: {'price': 90, 'enabled': true, 'repeatMonths': 6},
      }, configBase: cfg);
      // إعادة بناء البطاقة (رجوعٌ للمحور ثم فتح القسم) — البذر يقرأ طازجاً.
      await tester.tap(find.byKey(const Key('settings-section-back')),
          warnIfMissed: false);
      await settle(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('tri-anal-price')))
            .controller!
            .text,
        '90',
        reason: 'الحقل يعرض المحفوظ طازجاً ولا يفرغ',
      );
    });

    testWidgets('كتابة سعر جديد ثم الخروج والعودة تُظهره لا فراغاً',
        (tester) async {
      await boot(tester);
      await openSettings(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tri-anal-price')), '250');
      // الخروج المباشر من الإعدادات (بلا لمس خارج الحقل).
      await leaveSettings(tester);

      final chk = container();
      addTearDown(chk.dispose);
      expect(triAnalysesPrice(chk.read(appConfigProvider)), 250,
          reason: 'الخروج المباشر يجب أن يلتزم بالقيمة المكتوبة');

      await openSettings(tester);
      await openGroup(tester, 'clinic');
      await tester.scrollUntilVisible(
        find.byKey(const Key('tri-anal-price')),
        250,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const Key('tri-anal-price')))
            .controller!
            .text,
        '250',
      );
    });
  });
}
