/// اختبارات م68/دفعة ثانٍ-أ — «تذكّرني = لا» يمحو الجلسة المحفوظة سابقاً.
///
/// العيب الأصلي (H4): `login(remember:false)` كان يضبط `_persist=false` قبل
/// نداء `_writeSessionFile`، فتعود الدالة فوراً دون لمس الملف — ويبقى
/// `session.json` من دخولٍ سابق «بالتذكّر» حاملاً **رموز حسابٍ آخر**. المنشئ
/// يقرأ الملف عند الإقلاع التالي فتُستعاد الهوية السابقة: تسريب رموز بين
/// حسابين على جهاز عيادة مشترك، وعكس ما طلبه المستخدم صراحةً.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/data/cloud/supabase_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _base = 'https://proj.supabase.co';

String _sessionJson({String uid = 'uid-1', String email = 'a@clinic.ly'}) =>
    jsonEncode({
      'access_token': 'access-$uid',
      'refresh_token': 'refresh-$uid',
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {'id': uid, 'email': email},
    });

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m68s_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  GotrueClient clientFor(String uid, String email) => GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient(
            (_) async => http.Response(_sessionJson(uid: uid, email: email), 200)),
      );

  File sessionFile() => File('${tmp.path}/session.json');

  test('REPRO: دخول بلا تذكّر بعد دخولٍ بتذكّر لا يترك جلسة الحساب السابق',
      () async {
    // 1) حساب أول يدخل «بالتذكّر» ⇒ يُكتب session.json
    final s1 = SupabaseAuthService(
        client: clientFor('uid-A', 'a@clinic.ly'), dbDir: tmp.path);
    addTearDown(s1.dispose);
    await s1.login('a@clinic.ly', 'كلمةقوية123', remember: true);
    expect(sessionFile().existsSync(), isTrue);
    expect(sessionFile().readAsStringSync(), contains('uid-A'));

    // 2) حساب ثانٍ يدخل «بلا تذكّر» على الجهاز نفسه
    final s2 = SupabaseAuthService(
        client: clientFor('uid-B', 'b@clinic.ly'), dbDir: tmp.path);
    addTearDown(s2.dispose);
    await s2.login('b@clinic.ly', 'كلمةقوية123', remember: false);

    // م68: لا يبقى ملف جلسة إطلاقاً — لا رموز الحساب الأول ولا الثاني.
    expect(sessionFile().existsSync(), isFalse,
        reason: 'العيب كان يُبقي رموز الحساب الأول على القرص');

    // 3) إقلاع تالٍ: لا هوية مستعادة
    final s3 = SupabaseAuthService(
        client: clientFor('uid-C', 'c@clinic.ly'), dbDir: tmp.path);
    addTearDown(s3.dispose);
    expect(s3.restoreSession(), isNull,
        reason: 'لا تُستعاد هوية حساب سابق بعد دخول بلا تذكّر');
  });

  test('CONTROL: الدخول بالتذكّر يكتب الجلسة ويستعيدها', () async {
    final s1 = SupabaseAuthService(
        client: clientFor('uid-A', 'a@clinic.ly'), dbDir: tmp.path);
    addTearDown(s1.dispose);
    await s1.login('a@clinic.ly', 'كلمةقوية123', remember: true);
    expect(sessionFile().existsSync(), isTrue);

    final s2 = SupabaseAuthService(
        client: clientFor('uid-A', 'a@clinic.ly'), dbDir: tmp.path);
    addTearDown(s2.dispose);
    expect(s2.restoreSession()?.uid, 'uid-A');
  });

  test('دخول بلا تذكّر على جهاز نظيف لا ينشئ ملفاً', () async {
    final s = SupabaseAuthService(
        client: clientFor('uid-B', 'b@clinic.ly'), dbDir: tmp.path);
    addTearDown(s.dispose);
    await s.login('b@clinic.ly', 'كلمةقوية123', remember: false);
    expect(sessionFile().existsSync(), isFalse);
  });
}
