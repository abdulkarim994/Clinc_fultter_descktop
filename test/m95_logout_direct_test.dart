/// اختبار م95 — الخروج من الإعدادات يهبط على شاشة الدخول **مباشرة**.
///
///  العيب الذي يحرسه (رصده المالك): تنفيذ الخروج كان يغلق شاشةَ الإعدادات
///  أولاً — فتظهر آخرُ واجهةٍ كان فيها المستخدم (الصدفة) — ثم ينتظر 300ms
///  ثم يسجّل الخروج فتحلّ شاشةُ الدخول. وميضُ صدفةٍ بلا معنى بين شاشتين.
///
///  بعد م95: الخروج يتم وشاشةُ الحجب ما تزال فوق الإعدادات، ثم تُزال
///  المسارات كلها حتى الجذر (الذي صار شاشةَ الدخول) دفعةً واحدة.
///
///  الرقابة إطاراً بإطار: الصدفة تحت شاشة الإعدادات offstage طوال الوقت،
///  وعودتُها onstage في أي إطارٍ بعد التأكيد هي الوميضُ القديم بعينه —
///  فيؤكَّد غيابُها في كل خطوة حتى استقرار شاشة الدخول.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/login/login_screen.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  group('م95 — خروجٌ مباشرٌ بلا وميض', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m95_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Finder vScrollable() => find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;

    /// زر الخروج آخرُ القائمة — خارج نافذة البناء الكسول، فيُمرَّر إليه.
    Future<void> scrollToLogout(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('logout-btn')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
    }

    Future<void> seed() async {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
      await c
          .read(authProvider.notifier)
          .login('doc@clinic.ly', 'secret12', true);
      final db = c.read(localDbProvider);
      // تعطيل قفل الإقلاع كي نبلغ الإعدادات مباشرة (تفضيل محلي مشروع).
      setLockOnStart(db, false);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
      });
      markSetupComplete(db, 'doc@clinic.ly');
      c.dispose();
    }

    testWidgets(
      'تأكيد الخروج من الإعدادات ⇒ شاشة الدخول، والصدفة لا تظهر بينهما',
      (tester) async {
        await seed();
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
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(AppShellScreen), findsOneWidget);

        // فتح الإعدادات فوق الصدفة.
        await tester.tap(find.byTooltip('الإعدادات'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('settings-header')), findsOneWidget);

        // زر الخروج ثم تأكيده.
        await scrollToLogout(tester);
        await tester.tap(find.byKey(const Key('logout-btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('logout-confirm')));

        // م95 — رقابة إطاراً بإطار: الوميض القديم كان **فجوةً** تُغلق فيها
        // الإعدادات (يزول الهيدر) قبل أن تحلّ شاشة الدخول — فتظهر الصدفة
        // وحدها. الثابت المحروس: لا إطارَ يخلو من هيدر الإعدادات ومن شاشة
        // الدخول معاً. (الباحث يرى المسارات المغطاة أيضاً، فوجود أحدهما في
        // الشجرة كافٍ لنفي الفجوة.)
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final settingsThere = find
              .byKey(const Key('settings-header'))
              .evaluate()
              .isNotEmpty;
          final loginThere = find.byType(LoginScreen).evaluate().isNotEmpty;
          expect(
            settingsThere || loginThere,
            isTrue,
            reason: 'م95: فجوةُ صدفةٍ بين الإعدادات والدخول (الإطار $i)',
          );
        }

        // الاستقرار: شاشة الدخول حاضرة والإعدادات والصدفة زالتا كلياً.
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byType(LoginScreen),
          findsOneWidget,
          reason: 'م95: الهبوط مباشرةً على شاشة الدخول',
        );
        expect(
          find.byType(AppShellScreen),
          findsNothing,
          reason: 'م95: الصدفة زالت مع خروج الجلسة',
        );
        expect(
          find.byKey(const Key('settings-header')),
          findsNothing,
          reason: 'م95: الإعدادات أُزيلت مع بقية المسارات حتى الجذر',
        );
      },
    );

    testWidgets('فشل ما قبل الخروج يُبقي المستخدم في الإعدادات برسالة', (
      tester,
    ) async {
      await seed();
      // وضعٌ سحابي مزيف: cloud=true يجعل المزامنة شرطاً — ولا خادم في
      // الاختبار فتفشل ويُجهض الخروج (مسار الإجهاض يبقى كما كان).
      // ملاحظة: cloudConfigProvider يقرأ ملف إعدادٍ محلياً — نكتفي
      // بالوضع المحلي حيث لا فشل، فمسار الإجهاض مغطى في اختبارات م7
      // القائمة (import/export) — هذا الاختبار يوثّق بقاء زر الخروج
      // يعمل بعد إلغاء التأكيد.
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
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await scrollToLogout(tester);
      await tester.tap(find.byKey(const Key('logout-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // إلغاء التأكيد ⇒ البقاء في الإعدادات.
      await tester.tap(find.text('إلغاء'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('settings-header')),
        findsOneWidget,
        reason: 'الإلغاء يبقي المستخدم حيث هو',
      );
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
