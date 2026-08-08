/// اختبارات م88 — جسر دخول Google عبر Supabase Auth.
///
///  دورةُ Google الحقيقية (متصفّح + PKCE + deep-link) تحتاج جهازاً واعتمادات،
///  فلا تُختبَر في الصندوق. لكن **كل المنطق حولها** يُختبَر هنا بمزيّفٍ
///  للمزوّد: أول دخول ⇒ إعداد إجباري، دخولٌ عائد ⇒ ترحيبٌ باسمه، والخروج.
///  وهذا هو جواب سؤال التوجيه: البوابة القائمة تتكفّل بالفرق تلقائياً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/oauth_signin.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// مزوّد OAuth مزيّف: يعيد هويةً مختارة، أو يرمي كإلغاءٍ من المستخدم.
class _FakeOAuth implements OAuthSignIn {
  _FakeOAuth(this.result, {this.throwing = false});
  final OAuthResult result;
  final bool throwing;
  int calls = 0;
  @override
  Future<OAuthResult> signInWithGoogle() async {
    calls++;
    if (throwing) throw const OAuthUnavailable('أُلغيَ');
    return result;
  }
}

void main() {
  group('م88 — دخول Google', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m88_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    const googleUser = OAuthResult(
      uid: 'google-uid-1',
      email: 'dr.ahmad@gmail.com',
      displayName: 'د. أحمد',
    );

    ProviderContainer container(OAuthSignIn oauth) => ProviderContainer(
          overrides: [
            dbDirProvider.overrideWithValue(tmp.path),
            oauthSignInProvider.overrideWithValue(oauth),
          ],
        );

    test('أول دخول: يضبط الجلسة والهوية والاسم المعروض', () async {
      final c = container(_FakeOAuth(googleUser));
      addTearDown(c.dispose);
      await c.read(authProvider.notifier).signInWithGoogle();

      final state = c.read(authProvider);
      expect(state, isA<SignedIn>());
      final u = (state as SignedIn).user;
      expect(u.uid, 'google-uid-1');
      expect(u.displayName, 'د. أحمد', reason: 'م88: الاسم للترحيب');
      expect(c.read(localDbProvider).getOwnerUid(), 'google-uid-1',
          reason: 'م88: بيانات العيادة تُربَط بـ auth.uid');
      expect(c.read(authProvider.notifier).justLoggedIn, isTrue,
          reason: 'م88: دخولٌ صريح ⇒ ترحيب لا فتحٌ صامت');
    });

    test('الإلغاء/التعذّر يُرمى ولا يُسجّل دخولاً', () async {
      final c = container(_FakeOAuth(googleUser, throwing: true));
      addTearDown(c.dispose);
      await expectLater(
        c.read(authProvider.notifier).signInWithGoogle(),
        throwsA(isA<OAuthUnavailable>()),
      );
      expect(c.read(authProvider), isA<SignedOut>());
    });

    test('الافتراض «غير مُفعَّل» يشرح ولا ينهار', () async {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);
      await expectLater(
        c.read(authProvider.notifier).signInWithGoogle(),
        throwsA(isA<OAuthUnavailable>()),
      );
    });

    testWidgets('أول دخول Google ⇒ شاشة الإعداد الإجبارية', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          oauthSignInProvider.overrideWithValue(_FakeOAuth(googleUser)),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // زر Google حاضرٌ في شاشة الدخول.
      expect(find.byKey(const Key('google-signin-btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('google-signin-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // مستخدمٌ جديد بلا إعداد ⇒ البوابة تفرض شاشة اسم المركز والعيادة.
      expect(find.text('مرحباً بك'), findsOneWidget,
          reason: 'م88: جديد ⇒ إعداد إجباري (جواب سؤال التوجيه)');
      expect(find.byType(AppShellScreen), findsNothing);
    });

    testWidgets('م88/ج — «تسجيل الخروج» من الإعداد الإجباري ثم عودةٌ إليه',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          oauthSignInProvider.overrideWithValue(_FakeOAuth(googleUser)),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('google-signin-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('مرحباً بك'), findsOneWidget);

      // المخرجُ الصغير (طلب المالك): دخل بالحساب الخطأ ⇒ يخرج لشاشة الدخول.
      await tester.ensureVisible(find.byKey(const Key('gate-logout')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gate-logout')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('google-signin-btn')), findsOneWidget,
          reason: 'م88/ج: الخروج من الإعداد يعيد لشاشة الدخول');

      // وعودتُه بنفس الحساب ⇒ الإعدادُ الإجباري نفسه — الإجبارية تصمد.
      await tester.tap(find.byKey(const Key('google-signin-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('مرحباً بك'), findsOneWidget,
          reason: 'م88/ج: لا يدخل الرئيسية حتى يكمل الإعداد');
      expect(find.byType(AppShellScreen), findsNothing);
    });

    testWidgets('دخول Google عائد ⇒ ترحيبٌ باسمه ثم الرئيسية', (tester) async {
      // بذر: نفس مستخدم Google أكمل الإعداد سابقاً.
      final seed = ProviderContainer(overrides: [
        dbDirProvider.overrideWithValue(tmp.path),
        oauthSignInProvider.overrideWithValue(_FakeOAuth(googleUser)),
      ]);
      await seed.read(authProvider.notifier).signInWithGoogle();
      seed.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز النور',
        'clinics': ['عيادة'],
      });
      markSetupComplete(seed.read(localDbProvider), 'google-uid-1');
      seed.dispose();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          oauthSignInProvider.overrideWithValue(_FakeOAuth(googleUser)),
        ],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('google-signin-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // عائدٌ مكتمل الإعداد ⇒ ترحيبٌ يحمل اسمه (لا شاشة إعداد).
      expect(find.textContaining('د. أحمد'), findsOneWidget,
          reason: 'م88: عائد ⇒ ترحيبٌ باسم Google');
      expect(find.text('مرحباً بك'), findsNothing);

      // استنزافُ مؤقّتات الترحيب (حدّ قراءة 2.8ث + تلاشٍ) حتى تنتقل للرئيسية،
      // فلا يبقى مؤقّتٌ معلّق عند نهاية الاختبار.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AppShellScreen), findsOneWidget);
    });

    test('الخروج بعد دخول Google ينظّف الجلسة', () async {
      final c = container(_FakeOAuth(googleUser));
      addTearDown(c.dispose);
      await c.read(authProvider.notifier).signInWithGoogle();
      await c.read(authProvider.notifier).logout();
      expect(c.read(authProvider), isA<SignedOut>());
      expect(c.read(localDbProvider).getOwnerUid(), isNull);
    });
  });
}
