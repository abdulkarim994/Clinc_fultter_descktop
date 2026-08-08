/// اختبارات م88/ب — وصل الحزمة الرسمية: المخزن الآمن، الترحيل، موزّع
/// الجلسات، ومستقبِل عودة المكتب.
///
///  ما لا يُختبر هنا (يحتاج جهازاً): دورة المتصفح الحقيقية وdeep-link
///  أندرويد وKeystore/DPAPI الفعليان. المُختبر: **كل** المنطق حولها —
///  بمخزنٍ بديل وجسرٍ مزيّف وطلبات HTTP حقيقية على المستقبِل المحلي.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/core/auth/auth_contracts.dart';
import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/data/cloud/session_store.dart';
import 'package:dental_clinic_flutter/data/cloud/supabase_auth_service.dart';
import 'package:dental_clinic_flutter/data/cloud/supabase_boot.dart';
import 'package:dental_clinic_flutter/features/auth/oauth_signin.dart';
import 'package:dental_clinic_flutter/features/auth/supabase_oauth_signin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart'
    show GoTrueClient, Session;

/// مخزن مفتاح/قيمة في الذاكرة — بديل مخزن أسرار النظام في الاختبارات.
class InMemoryKv implements AsyncKv {
  final map = <String, String>{};
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('فكٌّ متعذّر (محاكاة عطل Keystore)');
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// جسر جلسة مزيّف — يحاكي الحزمة الرسمية دون منصّة.
class FakeBridge implements SdkSessionBridge {
  SdkSessionInfo? session;
  String freshToken = 'sdk-fresh-token';
  String? forcedToken = 'sdk-forced-token';
  int freshCalls = 0;
  int forceCalls = 0;
  int signOuts = 0;

  @override
  SdkSessionInfo? current() => session;

  @override
  Future<String?> freshAccessToken() async {
    freshCalls++;
    return freshToken;
  }

  @override
  Future<String?> forceRefresh() async {
    forceCalls++;
    return forcedToken;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    session = null;
  }
}

/// مخزن جلسة بسيط في الذاكرة لاختبارات الموزّع.
class MemStore implements SessionStore {
  String? v;
  @override
  String? read() => v;
  @override
  void write(String sessionJson) => v = sessionJson;
  @override
  void delete() => v = null;
}

String _sessionJson(String uid, String email,
        {String access = 'tok-a', String refresh = 'ref-a'}) =>
    jsonEncode({
      'access_token': access,
      'refresh_token': refresh,
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {'id': uid, 'email': email},
    });

/// عميل GoTrue فوق HTTP مزيّف يعيد جلسة صالحة لأي دخول.
GotrueClient _fakeGotrue() => GotrueClient(
      baseUrl: 'https://fake.supabase.co',
      anonKey: 'anon',
      httpClient: MockClient((req) async => http.Response(
          _sessionJson('pw-uid-1', 'dr@clinic.ly'), 200,
          headers: {'content-type': 'application/json'})),
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m88b_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('م88/ب — مخزن الجلسة', () {
    test('FileSessionStore يطابق سلوك session.json التاريخي', () {
      final store = FileSessionStore(tmp.path);
      expect(store.read(), isNull);
      store.write('{"x":1}');
      // نفس الملف والمسار حرفياً — توافق خلفي مع كل ما كُتب قبل م88.
      expect(File(p.join(tmp.path, 'session.json')).existsSync(), isTrue);
      expect(store.read(), '{"x":1}');
      store.delete();
      expect(File(p.join(tmp.path, 'session.json')).existsSync(), isFalse);
      expect(store.read(), isNull);
    });

    test('الترحيل: session.json صالح ⇒ يُنقل للمخزن الآمن ويُحذف الملف',
        () async {
      final legacy = _sessionJson('u-legacy', 'old@clinic.ly');
      File(p.join(tmp.path, 'session.json')).writeAsStringSync(legacy);
      final kv = InMemoryKv();

      final store = await SecureSessionStore.load(kv: kv, dbDir: tmp.path);

      expect(store.read(), legacy, reason: 'الجلسة تبقى حيّة بعد التحديث');
      expect(kv.map[SecureSessionStore.storageKey], legacy,
          reason: 'النسخة الدائمة صارت في مخزن الأسرار');
      expect(File(p.join(tmp.path, 'session.json')).existsSync(), isFalse,
          reason: 'لا تبقى نسخة اعتماد نصّية بعد نجاح النقل');
    });

    test('الترحيل: النسخة الآمنة القائمة تفوز ويُمحى الملف النصّي', () async {
      final secure = _sessionJson('u-secure', 'new@clinic.ly');
      final stale = _sessionJson('u-stale', 'stale@clinic.ly');
      final kv = InMemoryKv()..map[SecureSessionStore.storageKey] = secure;
      File(p.join(tmp.path, 'session.json')).writeAsStringSync(stale);

      final store = await SecureSessionStore.load(kv: kv, dbDir: tmp.path);

      expect(store.read(), secure);
      expect(File(p.join(tmp.path, 'session.json')).existsSync(), isFalse);
    });

    test('الترحيل: ملف تالف لا يُرحَّل ولا يُحذف ولا ينهار', () async {
      File(p.join(tmp.path, 'session.json')).writeAsStringSync('ليس json');
      final kv = InMemoryKv();

      final store = await SecureSessionStore.load(kv: kv, dbDir: tmp.path);

      expect(store.read(), isNull);
      expect(kv.map, isEmpty);
      // يبقى للفحص اليدوي — الحذف حصراً بعد نقلٍ ناجح.
      expect(File(p.join(tmp.path, 'session.json')).existsSync(), isTrue);
    });

    test('عطل قراءة المخزن الآمن ⇒ بلا جلسة، لا انهيار ولا رجوع للنص',
        () async {
      final kv = InMemoryKv()..failReads = true;
      final store = await SecureSessionStore.load(kv: kv, dbDir: tmp.path);
      expect(store.read(), isNull);
    });

    test('الكتابة والحذف: فوريان في الذاكرة ويلحقان بالمخزن الآمن', () async {
      final kv = InMemoryKv();
      final store = await SecureSessionStore.load(kv: kv, dbDir: tmp.path);

      store.write('{"s":1}');
      expect(store.read(), '{"s":1}', reason: 'القراءة المتزامنة فورية');
      await Future<void>.delayed(Duration.zero);
      expect(kv.map[SecureSessionStore.storageKey], '{"s":1}');

      store.delete();
      expect(store.read(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(kv.map.containsKey(SecureSessionStore.storageKey), isFalse);
    });
  });

  group('م88/ب — موزّع الجلسات (محرّك واحد لكل نوع)', () {
    test('جلسة Google في الجسر ⇒ الاستعادة والرموز كلها من الجسر', () async {
      final bridge = FakeBridge()
        ..session = const SdkSessionInfo(
            uid: 'g-uid', email: 'dr.g@gmail.com', displayName: 'د. أحمد');
      final svc = SupabaseAuthService(
          client: _fakeGotrue(),
          dbDir: tmp.path,
          store: MemStore(),
          sdk: bridge);
      addTearDown(svc.dispose);

      final u = svc.restoreSession();
      expect(u, isNotNull);
      expect(u!.uid, 'g-uid');
      expect(u.displayName, 'د. أحمد', reason: 'الاسم يصل لرسالة الترحيب');

      expect(await svc.validAccessToken(), 'sdk-fresh-token');
      expect(bridge.freshCalls, 1, reason: 'الرمز الطازج من الحزمة لا غيرها');
      expect(await svc.forceRefresh(), 'sdk-forced-token');
      expect(bridge.forceCalls, 1);
    });

    test('لا جلسة في الجسر ⇒ المسار القائم كما هو (كلمة المرور)', () async {
      final store = MemStore()..v = _sessionJson('pw-uid', 'pw@clinic.ly');
      final bridge = FakeBridge(); // جسر حاضر لكن بلا جلسة
      final svc = SupabaseAuthService(
          client: _fakeGotrue(), dbDir: tmp.path, store: store, sdk: bridge);
      addTearDown(svc.dispose);

      final u = svc.restoreSession();
      expect(u!.uid, 'pw-uid');
      expect(await svc.validAccessToken(), 'tok-a',
          reason: 'رمز الجلسة القائمة — لا نداء للجسر');
      expect(bridge.freshCalls, 0);
    });

    test('دخول كلمة المرور يُسقط جلسة Google القائمة (محرّك واحد)', () async {
      final bridge = FakeBridge()
        ..session = const SdkSessionInfo(uid: 'g-uid', email: 'g@x.com');
      final store = MemStore();
      final svc = SupabaseAuthService(
          client: _fakeGotrue(), dbDir: tmp.path, store: store, sdk: bridge);
      addTearDown(svc.dispose);

      final u = await svc.login('dr@clinic.ly', 'password123', remember: true);
      expect(u.uid, 'pw-uid-1');
      expect(bridge.signOuts, 1,
          reason: 'محرّكان على رمز تحديثٍ واحد = سباق يقتل الجلسة');
      expect(store.v, isNotNull, reason: 'جلسة كلمة المرور حُفظت في المخزن');
    });

    test('الخروج مع جلسة Google ⇒ خروج الجسر + مسح مخزن كلمة المرور',
        () async {
      final bridge = FakeBridge()
        ..session = const SdkSessionInfo(uid: 'g-uid', email: 'g@x.com');
      final store = MemStore()..v = _sessionJson('pw-uid', 'pw@clinic.ly');
      final svc = SupabaseAuthService(
          client: _fakeGotrue(), dbDir: tmp.path, store: store, sdk: bridge);
      addTearDown(svc.dispose);

      await svc.logout();
      expect(bridge.signOuts, 1);
      expect(store.v, isNull);
      expect(svc.restoreSession(), isNull, reason: 'لا هوية بعد الخروج');
    });
  });

  group('م88/ب — مستقبِل عودة المكتب (loopback)', () {
    Future<String> httpGet(String url) async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close();
        return utf8.decodeStream(res);
      } finally {
        client.close();
      }
    }

    test('يستقبل ?code= ويعيد صفحة نجاح عربية', () async {
      final r = LoopbackCodeReceiver(port: 0); // منفذ عشوائي للاختبار
      await r.start();
      addTearDown(r.close);

      final page = await httpGet('${r.redirectUrl}/?code=abc123');
      expect(page, contains('اكتمل تسجيل الدخول'));
      expect(await r.waitForCode(timeout: const Duration(seconds: 2)),
          'abc123');
    });

    test('طلبات المتصفح الجانبية (favicon) لا تستهلك الانتظار', () async {
      final r = LoopbackCodeReceiver(port: 0);
      await r.start();
      addTearDown(r.close);

      await httpGet('${r.redirectUrl}/favicon.ico');
      await httpGet('${r.redirectUrl}/?code=later-code');
      expect(await r.waitForCode(timeout: const Duration(seconds: 2)),
          'later-code');
    });

    test('رفض المستخدم (access_denied) ⇒ OAuthUnavailable بعربية صريحة',
        () async {
      final r = LoopbackCodeReceiver(port: 0);
      await r.start();
      addTearDown(r.close);

      // يُربَط التوقّع **قبل** إطلاق الطلب: الخطأ يصل أثناء انتظار HTTP،
      // ومستقبلٌ أخطأ بلا مستمعٍ يُبلَّغ خطأً غير معالَج فيُفشل الاختبار.
      final wait = expectLater(
          r.waitForCode(timeout: const Duration(seconds: 2)),
          throwsA(isA<OAuthUnavailable>()
              .having((e) => e.message, 'message', contains('أُلغي'))));
      final page = await httpGet('${r.redirectUrl}/?error=access_denied');
      expect(page, contains('لم يكتمل تسجيل الدخول'));
      await wait;
    });

    test('انقضاء المهلة بلا عودة ⇒ OAuthUnavailable', () async {
      final r = LoopbackCodeReceiver(port: 0);
      await r.start();
      addTearDown(r.close);

      await expectLater(
          r.waitForCode(timeout: const Duration(milliseconds: 200)),
          throwsA(isA<OAuthUnavailable>()));
    });
  });

  group('م88/ج — المسار الأصلي (نافذة حسابات الجهاز) فوق signInWithIdToken',
      () {
    // عميل GoTrue حقيقي فوق HTTP مزيّف: يثبت أن idToken يذهب فعلاً إلى
    // نقطة grant_type=id_token الرسمية ويعود جلسةً كاملة.
    GoTrueClient idTokenClient(List<Uri> seen) => GoTrueClient(
          url: 'https://fake.supabase.co/auth/v1',
          headers: const {'apikey': 'anon'},
          autoRefreshToken: false,
          httpClient: MockClient((req) async {
            seen.add(req.url);
            return http.Response(
                jsonEncode({
                  'access_token': 'sdk-tok',
                  'token_type': 'bearer',
                  'expires_in': 3600,
                  'refresh_token': 'sdk-ref',
                  'user': {
                    'id': 'native-uid-1',
                    'aud': 'authenticated',
                    'email': 'dr.native@gmail.com',
                    'app_metadata': <String, Object?>{},
                    'user_metadata': {
                      'full_name': 'د. كريم',
                      'avatar_url': 'https://x/pic.png',
                    },
                    'created_at': '2026-08-01T00:00:00Z',
                  },
                }),
                200,
                headers: {'content-type': 'application/json'});
          }),
        );

    test('idToken من النافذة الأصلية ⇒ جلسة رسمية بهوية واسم Google',
        () async {
      final seen = <Uri>[];
      final client = idTokenClient(seen);
      var browserUsed = false;
      final oauth = SupabaseSdkOAuthSignIn(
        auth: () => client,
        useLoopback: false,
        nativeAuth: () async => 'fake-google-id-token',
        browserFlow: () async {
          browserUsed = true;
          throw StateError('يجب ألا يُفتح المتصفح والمسار الأصلي ناجح');
        },
      );

      final res = await oauth.signInWithGoogle();
      expect(res.uid, 'native-uid-1');
      expect(res.displayName, 'د. كريم');
      expect(res.avatarUrl, 'https://x/pic.png');
      expect(browserUsed, isFalse);
      expect(seen.single.queryParameters['grant_type'], 'id_token',
          reason: 'المسار الرسمي signInWithIdToken لا OAuth مخصص');
    });

    test('إلغاء المستخدم للنافذة الأصلية يُحترم — لا يُفتح متصفح بعده',
        () async {
      var browserUsed = false;
      final oauth = SupabaseSdkOAuthSignIn(
        auth: () => idTokenClient([]),
        useLoopback: false,
        nativeAuth: () async => throw const OAuthUnavailable('أُلغي الدخول.'),
        browserFlow: () async {
          browserUsed = true;
          throw StateError('لا مسار ثانٍ بعد إلغاء صريح');
        },
      );
      await expectLater(
          oauth.signInWithGoogle(),
          throwsA(isA<OAuthUnavailable>()
              .having((e) => e.message, 'message', contains('أُلغي'))));
      expect(browserUsed, isFalse);
    });

    test('تعذّر المسار الأصلي (عميل أندرويد غير مُنشأ) ⇒ سقوط رشيق للمتصفح',
        () async {
      var browserUsed = false;
      final oauth = SupabaseSdkOAuthSignIn(
        auth: () => idTokenClient([]),
        useLoopback: false,
        nativeAuth: () async =>
            throw StateError('DEVELOPER_ERROR: لا عميل أندرويد بعد'),
        browserFlow: () async {
          browserUsed = true;
          final s = Session.fromJson({
            'access_token': 'browser-tok',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'browser-ref',
            'user': {
              'id': 'browser-uid',
              'aud': 'authenticated',
              'email': 'dr@x.com',
              'app_metadata': <String, Object?>{},
              'created_at': '2026-08-01T00:00:00Z',
            },
          });
          return s!;
        },
      );
      final res = await oauth.signInWithGoogle();
      expect(browserUsed, isTrue, reason: 'زر يعمل دائماً خير من زر معطوب');
      expect(res.uid, 'browser-uid');
    });

    test('بلا معرّف عميل ويب: المسار الأصلي لا يُجرَّب أصلاً', () async {
      var browserUsed = false;
      final oauth = SupabaseSdkOAuthSignIn(
        auth: () => idTokenClient([]),
        useLoopback: false,
        // لا serverClientId ولا nativeAuth ⇒ سلوك ما قبل م88/ج حرفياً.
        browserFlow: () async {
          browserUsed = true;
          return Session.fromJson({
            'access_token': 't',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'u1',
              'aud': 'authenticated',
              'app_metadata': <String, Object?>{},
              'created_at': '2026-08-01T00:00:00Z',
            },
          })!;
        },
      );
      await oauth.signInWithGoogle();
      expect(browserUsed, isTrue);
    });
  });

  group('م88/ب — مخازن الحزمة الآمنة', () {
    test('مفتاح جلسة الحزمة يطابق اشتقاقها الافتراضي حرفياً', () {
      expect(sdkSessionKeyFor('https://qajgqatflmiiwqznxfha.supabase.co'),
          'sb-qajgqatflmiiwqznxfha-auth-token');
    });

    test('SecureSdkLocalStorage: دورة حفظ/فحص/قراءة/حذف كاملة', () async {
      final kv = InMemoryKv();
      final s = SecureSdkLocalStorage(kv: kv, key: 'sb-x-auth-token');
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('{"access_token":"t"}');
      expect(await s.hasAccessToken(), isTrue);
      expect(await s.accessToken(), '{"access_token":"t"}');
      expect(kv.map['sb-x-auth-token'], isNotNull,
          reason: 'القيمة في مخزن الأسرار لا في SharedPreferences');
      await s.removePersistedSession();
      expect(await s.hasAccessToken(), isFalse);
    });

    test('SecureGotrueAsyncStorage: مُتحقِّق PKCE ببادئة معزولة', () async {
      final kv = InMemoryKv();
      final s = SecureGotrueAsyncStorage(kv: kv);
      await s.setItem(key: 'code-verifier', value: 'v123');
      expect(await s.getItem(key: 'code-verifier'), 'v123');
      expect(kv.map.keys.single, startsWith('dental.sdk.'),
          reason: 'بادئة تمنع التصادم مع مفاتيحنا في المخزن المشترك');
      await s.removeItem(key: 'code-verifier');
      expect(await s.getItem(key: 'code-verifier'), isNull);
    });
  });
}
