/// اختبارات م186 — شاشة الدخول: بطاقة ثابتة الحجم + حقول موحّدة + رمز
/// الاستعادة.
///
/// بلاغ المالك: «المربع بكبر وبصغر وقت اختار تسجيل دخول وانقل لإنشاء
/// حساب جديد» — كتلة الدخول كانت تُخفى كلها وتُبنى كتلة إنشاءٍ مختلفة
/// فيقفز ارتفاع البطاقة ويتنقل زر Google من أسفل لأعلى.
///
/// العقود المحروسة هنا:
///   • **ارتفاع البطاقة البيضاء لا يتغير بالتبديل** — يُقاس بالبكسل.
///   • البريد وكلمة المرور **نفس الصندوقين** في التبويبين (متحكمان
///     مشتركان: المكتوب يبقى) وموضعاهما لا يتحركان.
///   • تبويب الإنشاء: حقل «تأكيد كلمة المرور» + تحقق التطابق قبل النداء.
///   • Google مسار دخولٍ حصراً — لا يظهر في تبويب الإنشاء.
///   • عميل GoTrue: نقطة verify للرمز ترسل الحمولة الصحيحة وتترجم
///     أخطاء الرمز عربياً.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('م186/أ — البطاقة ثابتة الحجم', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m186_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('التبديل بين التبويبين لا يغيّر ارتفاع البطاقة بكسلاً',
        (tester) async {
      await boot(tester);
      final card = find.byKey(const Key('login-glass-card'));
      final loginSize = tester.getSize(card);

      await tester.tap(find.byKey(const Key('auth-tab-register')));
      await tester.pumpAndSettle();
      final registerSize = tester.getSize(card);

      expect(registerSize.height, loginSize.height,
          reason: 'م186: «المربع بكبر وبصغر» — الارتفاع يجب ألا يتحرك');
      expect(registerSize.width, loginSize.width);

      // ورجوعاً — نفس القياس.
      await tester.tap(find.byKey(const Key('auth-tab-login')));
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, loginSize.height);
    });

    testWidgets('صندوقا البريد وكلمة المرور لا يتحركان من مكانيهما',
        (tester) async {
      await boot(tester);
      final emailBefore =
          tester.getTopLeft(find.byType(TextField).at(0));
      final passBefore = tester.getTopLeft(find.byType(TextField).at(1));

      await tester.tap(find.byKey(const Key('auth-tab-register')));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byType(TextField).at(0)), emailBefore,
          reason: 'م186: مربع الإيميل «مكانه» في التبويبين حرفياً');
      expect(tester.getTopLeft(find.byType(TextField).at(1)), passBefore);
      // الحقل الثالث الجديد: تأكيد كلمة المرور.
      expect(find.byKey(const Key('reg-confirm')), findsOneWidget);
    });

    testWidgets('المكتوب يبقى عند التبديل (متحكمان مشتركان)',
        (tester) async {
      await boot(tester);
      await tester.enterText(
          find.byType(TextField).at(0), 'doc@clinic.ly');
      await tester.enterText(find.byType(TextField).at(1), 'secret12');
      await tester.tap(find.byKey(const Key('auth-tab-register')));
      await tester.pumpAndSettle();
      expect(find.text('doc@clinic.ly'), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-tab-login')));
      await tester.pumpAndSettle();
      expect(find.text('doc@clinic.ly'), findsOneWidget);
    });

    testWidgets('Google في الدخول فقط، وتطابق الكلمتين شرط الإنشاء',
        (tester) async {
      await boot(tester);
      expect(find.byKey(const Key('google-signin-btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth-tab-register')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('google-signin-btn')), findsNothing,
          reason: 'م186: Google مسار دخولٍ حصراً');
      // تطابق مفقود ⇒ رسالة عربية بلا أي نداء تسجيل.
      await tester.enterText(
          find.byType(TextField).at(0), 'doc@clinic.ly');
      await tester.enterText(find.byType(TextField).at(1), 'secret12');
      await tester.enterText(
          find.byKey(const Key('reg-confirm')), 'مختلفة');
      await tester.tap(find.byKey(const Key('register-btn')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
    });
  });

  group('م186/ب — عميل رمز الاستعادة', () {
    GotrueClient client(MockClientHandler h) => GotrueClient(
        baseUrl: 'https://proj.supabase.co',
        anonKey: 'anon',
        httpClient: MockClient(h));

    test('verifyRecoveryCode يرسل الحمولة الصحيحة ويعيد جلسة', () async {
      late Map<String, Object?> sent;
      final c = client((req) async {
        expect(req.url.path, endsWith('/auth/v1/verify'));
        sent = Map<String, Object?>.from(jsonDecode(req.body) as Map);
        return http.Response(
            jsonEncode({
              'access_token': 'recovery-token',
              'refresh_token': 'r',
              'expires_at':
                  DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              'user': {'id': 'u1', 'email': 'doc@clinic.ly'},
            }),
            200,
            headers: {
              'content-type': 'application/json; charset=utf-8'
            });
      });
      final s = await c.verifyRecoveryCode(' doc@clinic.ly ', ' 123456 ');
      expect(sent,
          {'type': 'recovery', 'email': 'doc@clinic.ly', 'token': '123456'});
      expect(s.accessToken, 'recovery-token');
    });

    test('رمز خاطئ/منتهٍ ⇒ رسالة عربية واحدة واضحة', () async {
      final c = client((req) async => http.Response(
          jsonEncode({
            'code': 403,
            'error_code': 'otp_expired',
            'msg': 'Token has expired or is invalid',
          }),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await expectLater(
        c.verifyRecoveryCode('doc@clinic.ly', '000000'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message',
            contains('الرمز غير صحيح أو انتهت صلاحيته'))),
      );
    });

    test('translateAuthError: حالات الرمز لا تمسّ الرسائل القائمة', () {
      expect(translateAuthError('Token has expired or is invalid'),
          contains('اطلب رمزاً جديداً'));
      expect(translateAuthError('Invalid login credentials'),
          'البريد أو كلمة المرور غير صحيحة');
    });
  });
}
