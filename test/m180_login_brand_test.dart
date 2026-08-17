/// اختبارات م180/د — شاشة الدخول الجديدة وهوية DENTSHINE:
/// • المبدّل المنزلق: يمين «تسجيل الدخول» ويسار «إنشاء حساب جديد»،
///   والتبديل يبدّل الحقول (لا طيَّ أسفل الشاشة بعد الآن).
/// • «نسيت كلمة المرور؟»: حوار ببريد ثم إرسال حقيقي عبر خدمة المصادقة —
///   ورسالة محايدة لا تفصح عن وجود الحساب.
/// • الهوية: DENTSHINE + «لعيادة أكثر ذكاءً وتنظيمًا» + شعار الأيقونة.
/// • اسم المركز الافتراضي القديم يبقى «غير مكتمل الإعداد» (توافق).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/auth/auth_contracts.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// خدمة مصادقة مزيفة: تلتقط نداء إعادة التعيين (ونجاحه/فشله).
class _FakeAuth implements AuthService {
  _FakeAuth({this.throwOnReset});

  final String? throwOnReset;
  final List<String> resetCalls = [];

  /// م186 — نداءات إتمام الاستعادة بالرمز (بريد، رمز، كلمة جديدة).
  final List<(String, String, String)> confirmCalls = [];

  @override
  AuthUser? restoreSession() => null;

  @override
  Future<AuthUser> login(String email, String password,
          {bool remember = false}) async =>
      throw UnimplementedError();

  @override
  Future<void> register(String email, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls.add(email);
    if (throwOnReset != null) throw Exception(throwOnReset);
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    confirmCalls.add((email, code, newPassword));
    if (code != '123456') throw Exception('الرمز غير صحيح');
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m180d_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester, {_FakeAuth? auth}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbDirProvider.overrideWithValue(tmp.path),
        if (auth != null) authServiceProvider.overrideWithValue(auth),
      ],
      child: const DentalApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('م180/د — الهوية', () {
    testWidgets('الشعار الرسمي والشعار النصي الجديد', (tester) async {
      await boot(tester);
      // م182 — لوحة الشعار تحمل «DENTSHINE PRO» داخلها، فحُذف السطر
      // النصّي المكرَّر أسفلها وبقيت الجملة التعريفية وحدها.
      expect(find.text('لعيادة أكثر ذكاءً وتنظيمًا'), findsOneWidget);
      expect(find.text('DENTSHINE'), findsNothing,
          reason: 'م182: الاسم داخل الشعار نفسه — لا تكرار نصّي تحته');
      expect(find.text('نظام إدارة العيادة المتكامل'), findsNothing);
      expect(find.text('طب الأسنان الرقمي'), findsNothing);
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'assets/icon/icon-512.png'),
          findsOneWidget);
      // م182 — حوافّ مستديرة لا قصّ دائري (الدائري كان يبتر اسم الشعار
      // وشريطه السفلي).
      expect(find.byType(ClipOval), findsNothing,
          reason: 'م182: لا قصّ دائري للشعار بعد الآن');
    });

    test('اسم المركز الافتراضي: الجديد والقديم كلاهما «غير مُعَدّ»', () {
      expect(kAppBrandName, 'DENTSHINE');
      expect(
          isAccountConfigured(
              {'centerName': 'DENTSHINE', 'clinics': ['ع']}),
          isFalse);
      expect(
          isAccountConfigured(
              {'centerName': 'طب الأسنان الرقمي', 'clinics': ['ع']}),
          isFalse,
          reason: 'حساب قديم بالاسم الافتراضي يبقى غير مكتمل');
      expect(
          isAccountConfigured({'centerName': 'مركز حقيقي', 'clinics': ['ع']}),
          isTrue);
    });
  });

  group('م180/د — المبدّل المنزلق', () {
    testWidgets('التبديل يبدّل الحقول والأزرار بين الوضعين',
        (tester) async {
      await boot(tester);
      // وضع الدخول (الافتراضي).
      expect(find.byKey(const Key('auth-switcher')), findsOneWidget);
      expect(find.byKey(const Key('login-btn')), findsOneWidget);
      expect(find.byKey(const Key('register-btn')), findsNothing);
      // لتبويب الإنشاء.
      await tester.tap(find.byKey(const Key('auth-tab-register')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.byKey(const Key('register-btn')));
      await tester.pump();
      expect(find.byKey(const Key('register-btn')), findsOneWidget);
      expect(find.byKey(const Key('login-btn')), findsNothing);
      // ورجوعاً لتبويب الدخول.
      await tester.ensureVisible(find.byKey(const Key('auth-tab-login')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth-tab-login')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('login-btn')), findsOneWidget);
      expect(find.byKey(const Key('register-btn')), findsNothing);
    });
  });

  group('م180/د + م186 — نسيت كلمة المرور (تدفق الرمز داخل التطبيق)', () {
    testWidgets('الإرسال ثم حوار الرمز ثم تعيين الكلمة عبر الخدمة',
        (tester) async {
      final auth = _FakeAuth();
      await boot(tester, auth: auth);
      await tester.ensureVisible(find.byKey(const Key('forgot-password')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('forgot-dialog')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('forgot-email')), 'doc@clinic.ly');
      await tester.tap(find.byKey(const Key('forgot-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // نداء حقيقي بالبريد المُدخل + رسالة محايدة.
      expect(auth.resetCalls, ['doc@clinic.ly']);
      expect(find.textContaining('أرسلنا رمز التحقق'), findsOneWidget);

      // م186 — الخطوة الثانية تُفتح تلقائياً: الرمز + الكلمة وتأكيدها.
      expect(find.byKey(const Key('reset-dialog')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('reset-code')), '123456');
      await tester.enterText(
          find.byKey(const Key('reset-newpass')), 'newpass12');
      await tester.enterText(
          find.byKey(const Key('reset-confirm')), 'newpass11');
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pump();
      // تطابقٌ مفقود ⇒ خطأ داخل الحوار بلا أي نداء.
      expect(find.byKey(const Key('reset-error')), findsOneWidget);
      expect(auth.confirmCalls, isEmpty);
      await tester.enterText(
          find.byKey(const Key('reset-confirm')), 'newpass12');
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(auth.confirmCalls,
          [('doc@clinic.ly', '123456', 'newpass12')]);
      expect(find.byKey(const Key('reset-dialog')), findsNothing);
      // فخ §9 — SnackBars تصطف: نصرّف «أرسلنا رمز التحقق» (4 ثوانٍ)
      // بإطارٍ لخروجها وإطارٍ لدخول التالية ثم نتحقق.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('تم تغيير كلمة المرور'), findsOneWidget);
    });

    testWidgets('رمز خاطئ ⇒ الخطأ داخل الحوار ويبقى مفتوحاً للتصحيح',
        (tester) async {
      final auth = _FakeAuth();
      await boot(tester, auth: auth);
      await tester.ensureVisible(find.byKey(const Key('forgot-password')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('forgot-email')), 'doc@clinic.ly');
      await tester.tap(find.byKey(const Key('forgot-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('reset-code')), '000000');
      await tester.enterText(
          find.byKey(const Key('reset-newpass')), 'newpass12');
      await tester.enterText(
          find.byKey(const Key('reset-confirm')), 'newpass12');
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('reset-dialog')), findsOneWidget,
          reason: 'م186: الحوار لا يُغلق — يصحح المستخدم ويعيد');
      expect(find.textContaining('الرمز غير صحيح'), findsOneWidget);
    });

    testWidgets('فشل الإرسال يُعرض خطأً صريحاً لا صمتاً', (tester) async {
      final auth = _FakeAuth(throwOnReset: 'تعذّر الاتصال بالخادم');
      // (لا يصل لحوار الرمز أصلاً — الإرسال نفسه فشل.)
      await boot(tester, auth: auth);
      await tester.ensureVisible(find.byKey(const Key('forgot-password')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('forgot-password')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('forgot-email')), 'x@y.com');
      await tester.tap(find.byKey(const Key('forgot-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('تعذّر الاتصال بالخادم'), findsOneWidget);
    });
  });
}
