/// اختبارات م93 — إعدادات الحساب: كلمة المرور وحذف الحساب.
///
///  الخادم الحيّ لا يُلمس (سياسة SETUP_SUPABASE_AR + لا اعتمادات إدارية).
///  فكلُّ المنطق يُختبَر بمزيّفات: MockClient لـGoTrue/RPC، ومقابسُ حقنٍ
///  لـAccountAdmin (تطهير R2 والمسح المحلي) — تماماً كعزل م88/م87.
library;

import 'dart:convert';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/auth/auth_contracts.dart';
import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/features/auth/account_admin.dart';
import 'package:dental_clinic_flutter/features/settings/account_section.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// وحدة تحكّم مصادقة مزيّفة: تعيد حالةً موقَّعة بلا طبقة القاعدة كلها،
/// كي يُختبَر جسم القسم وحده (يقرأ authProvider للبريد فقط).
class _FakeAuth extends AuthController {
  @override
  AuthState build() =>
      const SignedIn(AuthUser(uid: 'uid-1', email: 'doc@clinic.ly'));
}

const _base = 'https://proj.supabase.co';

String _sessionJson({String access = 'access-1'}) => jsonEncode({
      'access_token': access,
      'refresh_token': 'r-1',
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {'id': 'uid-1', 'email': 'doc@clinic.ly'},
    });

/// عميل GoTrue فوق موجّهٍ يحاكي مسارات الخادم المعنية بم93.
GotrueClient _client(
  MockClientHandler handler, {
  List<http.BaseRequest>? sink,
}) =>
    GotrueClient(
      baseUrl: _base,
      anonKey: 'anon',
      httpClient: MockClient((req) async {
        sink?.add(req);
        return handler(req);
      }),
    );

void main() {
  group('م93/أ — GotrueClient: الهوية وكلمة المرور', () {
    test('userProviders يقرأ identities ويكتشف موفّر email', () async {
      final c = _client((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/auth/v1/user')) {
          return http.Response(
              jsonEncode({
                'id': 'uid-1',
                'identities': [
                  {'provider': 'google'},
                  {'provider': 'email'},
                ],
              }),
              200);
        }
        return http.Response('{}', 404);
      });
      final p = await c.userProviders('tok');
      expect(p, containsAll(<String>{'google', 'email'}));
    });

    test('userProviders: Google وحده ⇒ بلا email', () async {
      final c = _client((req) async => http.Response(
          jsonEncode({
            'id': 'uid-1',
            'identities': [
              {'provider': 'google'}
            ],
          }),
          200));
      final p = await c.userProviders('tok');
      expect(p, contains('google'));
      expect(p.contains('email'), isFalse);
    });

    test('updatePassword يرسل PUT مع Bearer وحقل password', () async {
      final calls = <http.BaseRequest>[];
      final bodies = <String>[];
      final c = GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          calls.add(req);
          bodies.add(req.body);
          if (req.method == 'PUT' &&
              req.url.path.endsWith('/auth/v1/user')) {
            return http.Response(jsonEncode({'id': 'uid-1'}), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      await c.updatePassword('tok-9', 'newsecret8');
      expect(calls.single.headers['authorization'], 'Bearer tok-9');
      expect(jsonDecode(bodies.single)['password'], 'newsecret8');
    });

    test('updatePassword يترجم ضعف الكلمة عربياً', () async {
      final c = _client((req) async => http.Response(
          jsonEncode({'msg': 'Password should be at least 6 characters'}),
          422));
      await expectLater(
        c.updatePassword('tok', 'x'),
        throwsA(predicate((e) => '$e'.contains('كلمة المرور ضعيفة'))),
      );
    });
  });

  group('م93/ب — GotrueClient: حذف الحساب (RPC)', () {
    test('deleteMyAccount ينجح على 2xx بمسار rpc الصحيح', () async {
      final calls = <http.BaseRequest>[];
      final c = _client((req) async {
        if (req.url.path.endsWith('/rest/v1/rpc/delete_my_account')) {
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      }, sink: calls);
      await c.deleteMyAccount('tok');
      expect(calls.single.headers['authorization'], 'Bearer tok');
      expect(calls.single.url.path, endsWith('/rpc/delete_my_account'));
    });

    test('غياب الدالة (404) ⇒ AccountRpcMissing', () async {
      final c = _client((req) async => http.Response('Not Found', 404));
      await expectLater(
          c.deleteMyAccount('tok'), throwsA(isA<AccountRpcMissing>()));
    });

    test('غياب الدالة (PGRST202 بجسم JSON) ⇒ AccountRpcMissing', () async {
      final c = _client((req) async => http.Response(
          jsonEncode({
            'code': 'PGRST202',
            'message': 'Could not find function public.delete_my_account'
          }),
          400));
      await expectLater(
          c.deleteMyAccount('tok'), throwsA(isA<AccountRpcMissing>()));
    });

    test('خطأ عام (500) ⇒ AuthException لا AccountRpcMissing', () async {
      final c = _client((req) async =>
          http.Response(jsonEncode({'message': 'boom'}), 500));
      await expectLater(
        c.deleteMyAccount('tok'),
        throwsA(allOf(isA<AuthException>(),
            isNot(isA<AccountRpcMissing>()))),
      );
    });
  });

  group('م93/ج — AccountAdmin: قرارات كلمة المرور', () {
    AccountAdmin admin(
      MockClientHandler handler, {
      List<String>? purged,
      List<String>? events,
    }) =>
        AccountAdmin(
          client: _client(handler),
          accessToken: () async => 'tok',
          email: 'doc@clinic.ly',
          purgeImages: () async => events?.add('purge'),
          wipeLocal: () async => events?.add('wipe'),
        );

    test('passwordState: email ⇒ hasPassword، وإلا noPassword', () async {
      final has = admin((req) async => http.Response(
          jsonEncode({'identities': [{'provider': 'email'}]}), 200));
      expect(await has.passwordState(), AccountPasswordState.hasPassword);

      final none = admin((req) async => http.Response(
          jsonEncode({'identities': [{'provider': 'google'}]}), 200));
      expect(await none.passwordState(), AccountPasswordState.noPassword);
    });

    test('passwordState: فشل الشبكة ⇒ unknown (لا انهيار)', () async {
      final a = admin((req) async => http.Response('err', 500));
      expect(await a.passwordState(), AccountPasswordState.unknown);
    });

    test('setPassword (Google) يحدّث بلا إعادة مصادقة', () async {
      var signIns = 0, puts = 0;
      final a = admin((req) async {
        if (req.url.toString().contains('grant_type=password')) {
          signIns++;
          return http.Response(_sessionJson(), 200);
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/auth/v1/user')) {
          puts++;
          return http.Response(jsonEncode({'id': 'uid-1'}), 200);
        }
        return http.Response('{}', 404);
      });
      await a.setPassword('newsecret8');
      expect(signIns, 0, reason: 'م93: التعيين أول مرة بلا قديمة');
      expect(puts, 1);
    });

    test('setPassword يرفض كلمةً قصيرة قبل أي نداء', () async {
      final a = admin((req) async => http.Response('{}', 200));
      await expectLater(
        a.setPassword('short'),
        throwsA(predicate((e) => '$e'.contains('8 أحرف'))),
      );
    });

    test('resetPassword: قديمة صحيحة ⇒ إعادة مصادقة ثم تحديث', () async {
      final order = <String>[];
      final a = admin((req) async {
        if (req.url.toString().contains('grant_type=password')) {
          order.add('reauth');
          final body = jsonDecode(req.body) as Map;
          if (body['password'] == 'oldpass12') {
            return http.Response(_sessionJson(), 200);
          }
          return http.Response(
              jsonEncode({'msg': 'Invalid login credentials'}), 400);
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/auth/v1/user')) {
          order.add('update');
          return http.Response(jsonEncode({'id': 'uid-1'}), 200);
        }
        return http.Response('{}', 404);
      });
      await a.resetPassword(
          oldPassword: 'oldpass12', newPassword: 'newsecret8');
      expect(order, ['reauth', 'update'],
          reason: 'م93: التحقق من القديمة يسبق التحديث');
    });

    test('resetPassword: قديمة خاطئة ⇒ رفضٌ ولا تحديث', () async {
      var puts = 0;
      final a = admin((req) async {
        if (req.url.toString().contains('grant_type=password')) {
          return http.Response(
              jsonEncode({'msg': 'Invalid login credentials'}), 400);
        }
        if (req.method == 'PUT' && req.url.path.endsWith('/auth/v1/user')) {
          puts++;
          return http.Response('{}', 200);
        }
        return http.Response('{}', 404);
      });
      await expectLater(
        a.resetPassword(oldPassword: 'wrong', newPassword: 'newsecret8'),
        throwsA(predicate(
            (e) => '$e'.contains('القديمة غير صحيحة'))),
      );
      expect(puts, 0, reason: 'م93: لا تحديث دون إثبات القديمة');
    });
  });

  group('م93/د — AccountAdmin: تدفّق الحذف', () {
    test('نجاح: RPC أولاً ثم تطهير R2 ثم المسح المحلي', () async {
      final order = <String>[];
      final a = AccountAdmin(
        client: _client((req) async {
          if (req.url.path.endsWith('/rpc/delete_my_account')) {
            order.add('rpc');
            return http.Response('', 204);
          }
          return http.Response('{}', 404);
        }),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => order.add('purge'),
        wipeLocal: () async => order.add('wipe'),
      );
      await a.deleteAccount();
      expect(order, ['rpc', 'purge', 'wipe'],
          reason: 'م93: الخادم مصدر الحقيقة أولاً، ثم R2، ثم المحلي');
    });

    test('الدالة غير مطبَّقة ⇒ إجهاض نظيف: لا تطهير ولا مسح', () async {
      final order = <String>[];
      final a = AccountAdmin(
        client: _client((req) async => http.Response('Not Found', 404)),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => order.add('purge'),
        wipeLocal: () async => order.add('wipe'),
      );
      await expectLater(
          a.deleteAccount(), throwsA(isA<AccountRpcMissing>()));
      expect(order, isEmpty,
          reason: 'م93: لا حالة نصف محذوفة قبل تطبيق 0031');
    });

    test('فشل تطهير R2 لا يُفشل الحذف — الحساب زال من المصدر', () async {
      final order = <String>[];
      final a = AccountAdmin(
        client: _client((req) async {
          if (req.url.path.endsWith('/rpc/delete_my_account')) {
            return http.Response('', 204);
          }
          return http.Response('{}', 404);
        }),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => throw Exception('R2 down'),
        wipeLocal: () async => order.add('wipe'),
      );
      await a.deleteAccount();
      expect(order, ['wipe'],
          reason: 'م93: R2 أفضل جهد؛ المسح المحلي يتم رغم فشله');
    });

    test('جلسة منتهية (بلا رمز) ⇒ خطأ واضح قبل أي نداء', () async {
      var rpc = 0;
      final a = AccountAdmin(
        client: _client((req) async {
          rpc++;
          return http.Response('', 204);
        }),
        accessToken: () async => null,
        email: 'doc@clinic.ly',
        purgeImages: () async {},
        wipeLocal: () async {},
      );
      await expectLater(
        a.deleteAccount(),
        throwsA(predicate((e) => '$e'.contains('انتهت الجلسة'))),
      );
      expect(rpc, 0);
    });
  });

  group('م93/هـ — واجهة القسم (بمقابس محقونة)', () {
    AccountAdmin fakeAdmin(
      MockClientHandler handler, {
      List<String>? events,
    }) =>
        AccountAdmin(
          client: _client(handler),
          accessToken: () async => 'tok',
          email: 'doc@clinic.ly',
          purgeImages: () async => events?.add('purge'),
          wipeLocal: () async => events?.add('wipe'),
        );

    Future<void> pump(WidgetTester tester, AccountAdmin admin) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          accountAdminProvider.overrideWithValue(admin),
          authProvider.overrideWith(_FakeAuth.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AccountSection()),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('البريد يُعرض، والعنوان «تعيين» لحساب Google', (tester) async {
      await pump(
          tester,
          fakeAdmin((req) async => http.Response(
              jsonEncode({'identities': [{'provider': 'google'}]}), 200)));
      expect(find.text('doc@clinic.ly'), findsOneWidget);
      // Google بلا كلمة مرور ⇒ لا حقل «الحالية»، والزر «تعيين».
      expect(find.byKey(const Key('account-pw-old')), findsNothing);
      expect(find.text('تعيين كلمة المرور'), findsWidgets);
    });

    testWidgets('حساب بكلمة مرور ⇒ حقل الحالية والعنوان «إعادة تعيين»',
        (tester) async {
      await pump(
          tester,
          fakeAdmin((req) async => http.Response(
              jsonEncode({'identities': [{'provider': 'email'}]}), 200)));
      expect(find.byKey(const Key('account-pw-old')), findsOneWidget);
      expect(find.text('إعادة تعيين كلمة المرور'), findsWidgets);
    });

    testWidgets('عدّاد الحذف يعطّل التأكيد 5 ثوانٍ ثم يُسلّحه', (tester) async {
      await pump(
          tester,
          fakeAdmin((req) async => http.Response(
              jsonEncode({'identities': [{'provider': 'email'}]}), 200)));
      await tester.tap(find.byKey(const Key('account-delete-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('account-delete-title')), findsOneWidget);

      FilledButton confirmBtn() => tester.widget<FilledButton>(
          find.byKey(const Key('account-delete-confirm')));
      expect(confirmBtn().onPressed, isNull,
          reason: 'م93: الزر معطّل أثناء العدّ');

      // بعد 5 نبضات ثانية يُسلَّح.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(confirmBtn().onPressed, isNotNull,
          reason: 'م93: يُسلَّح بعد انقضاء العدّاد');
    });

    testWidgets('تأكيد الحذف ينفّذ التدفّق (RPC ثم مسح)', (tester) async {
      final events = <String>[];
      await pump(
          tester,
          fakeAdmin(
            (req) async {
              if (req.url.path.endsWith('/rpc/delete_my_account')) {
                events.add('rpc');
                return http.Response('', 204);
              }
              return http.Response(
                  jsonEncode({'identities': [{'provider': 'email'}]}), 200);
            },
            events: events,
          ));
      await tester.tap(find.byKey(const Key('account-delete-btn')));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.byKey(const Key('account-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(events, containsAllInOrder(['rpc', 'purge', 'wipe']),
          reason: 'م93: الحذف من الواجهة ينفّذ التدفّق الكامل');
    });
  });
}
