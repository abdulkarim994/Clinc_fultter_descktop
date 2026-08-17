/// اختبارات م185 — حذف الحساب: رسائل الخادم وتطهير الصور.
///
/// البلاغ: زرّ «حذف الحساب نهائياً» يفشل على الهاتف والكمبيوتر معاً،
/// ويعرض للطبيب نصَّ Postgres الإنجليزي الخام:
///     violates foreign key constraint "activation_codes_bound_user_id_fkey"
///
/// الجذر كان على الخادم (مفتاح أجنبي مانع + دالة حذف بقائمة جداول ناقصة)
/// وأُصلح بالمهاجرة 0066 — واختباره في `supabase/tests/delete_account_test.sql`
/// لأنه سلوك قاعدة بيانات لا يُحاكى بمزيّف صادقٍ.
///
/// ما يحرسه هذا الملف في التطبيق:
///   • أي رفضٍ من الخادم يُترجَم عربياً — لا نصَّ إنجليزيّ خام للطبيب.
///   • ترتيب الحذف يبقى «الخادم أولاً»: فشلُه لا يمسّ الجهاز ولا R2
///     (لا حالة نصف محذوفة).
///   • تطهير R2 يشمل **مفاتيح طابور الرفع** أيضاً لا صور المعرض وحدها
///     (كائنات يتيمة كانت تبقى في السحابة بعد زوال الحساب).
library;

import 'dart:convert';

import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/features/auth/account_admin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

const _base = 'https://proj.supabase.co';

GotrueClient _client(MockClientHandler handler) => GotrueClient(
      baseUrl: _base,
      anonKey: 'anon',
      httpClient: MockClient(handler),
    );

/// نصّ الخطأ الحقيقي كما ردّه الخادم في لقطة المالك (PostgREST يلفّه).
String _fkErrorBody() => jsonEncode({
      'code': '23503',
      'details': null,
      'hint': null,
      'message': 'update or delete on table "users" violates foreign key '
          'constraint "activation_codes_bound_user_id_fkey" on table '
          '"activation_codes"',
    });

void main() {
  group('م185/أ — ترجمة رفض الخادم', () {
    test('خطأ المفتاح الأجنبي يُترجَم عربياً بلا نصٍّ إنجليزي', () {
      final out = translateAuthError(
          'update or delete on table "users" violates foreign key constraint '
          '"activation_codes_bound_user_id_fkey" on table "activation_codes"');
      expect(out, contains('تعذّر الحذف'));
      expect(out.contains('foreign key'), isFalse,
          reason: 'م185: لا نصَّ تقنيّاً إنجليزيّاً في وجه الطبيب');
      expect(out.contains('constraint'), isFalse);
    });

    test('انتهاء الجلسة وعدم الصلاحية لهما رسالتان مميّزتان', () {
      expect(translateAuthError('not authenticated'), contains('الجلسة'));
      expect(translateAuthError('permission denied for function'),
          contains('الصلاحية'));
      expect(translateAuthError('permission denied for function'),
          contains('لم يُحذف'),
          reason: 'تطمين صريح: الرفض لا يعني حذفاً جزئياً');
    });

    test('الرسائل القائمة لم تتغيّر (لا انحدار في م84 وسابقاتها)', () {
      expect(translateAuthError('Invalid login credentials'),
          'البريد أو كلمة المرور غير صحيحة');
      expect(translateAuthError('User not found'), 'البريد غير مسجّل');
      expect(translateAuthError('رسالة عربية كما هي'), 'رسالة عربية كما هي');
    });

    test('deleteMyAccount يرفع الرفض مترجَماً عبر AuthException', () async {
      final c = _client((req) async {
        expect(req.url.path, endsWith('/rest/v1/rpc/delete_my_account'));
        return http.Response(_fkErrorBody(), 409,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await expectLater(
        c.deleteMyAccount('tok'),
        throwsA(isA<AuthException>().having(
            (e) => e.message, 'message', contains('تعذّر الحذف'))),
      );
    });
  });

  group('م185/ب — ترتيب الحذف: الخادم أولاً', () {
    test('فشل الخادم ⇒ لا تطهيرَ صور ولا مسحَ محليّ', () async {
      var purged = false, wiped = false;
      final admin = AccountAdmin(
        client: _client((req) async => http.Response(_fkErrorBody(), 409,
            headers: {'content-type': 'application/json; charset=utf-8'})),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => purged = true,
        wipeLocal: () async => wiped = true,
      );
      await expectLater(admin.deleteAccount(), throwsA(isA<AuthException>()));
      expect(purged, isFalse, reason: 'لا لمسَ لـR2 قبل نجاح الخادم');
      expect(wiped, isFalse,
          reason: 'الجهاز لا يُمسح — لا حالة نصف محذوفة');
    });

    test('نجاح الخادم ⇒ تطهيرٌ ثم مسحٌ محليّ بالترتيب', () async {
      final order = <String>[];
      final admin = AccountAdmin(
        client: _client((req) async => http.Response('', 204)),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => order.add('purge'),
        wipeLocal: () async => order.add('wipe'),
      );
      await admin.deleteAccount();
      expect(order, ['purge', 'wipe']);
    });

    test('فشل تطهير R2 لا يُفشل الحذف (الحساب زال من المصدر)', () async {
      var wiped = false;
      final admin = AccountAdmin(
        client: _client((req) async => http.Response('', 204)),
        accessToken: () async => 'tok',
        email: 'doc@clinic.ly',
        purgeImages: () async => throw Exception('R2 غير متاح'),
        wipeLocal: () async => wiped = true,
      );
      await admin.deleteAccount();
      expect(wiped, isTrue, reason: 'المسح المحلي يمضي رغم فشل التطهير');
    });
  });

  group('م185/ج — تطهير R2 يشمل طابور الرفع', () {
    test('يجمع مفاتيح المعرض وطابور الرفع بلا تكرار', () {
      // نفس استعلامَي مزوّد purgeImages حرفياً، على قاعدةٍ في الذاكرة.
      final db = sqlite3.open(':memory:');
      addTearDown(db.close);
      db.execute('CREATE TABLE xrays (id TEXT PRIMARY KEY, file_key TEXT)');
      db.execute(
          'CREATE TABLE pending_uploads (id TEXT PRIMARY KEY, file_key TEXT)');
      db.execute("INSERT INTO xrays VALUES ('a','k/gallery-1'),"
          "('b','k/shared'),('c','')");
      db.execute("INSERT INTO pending_uploads VALUES ('p1','k/queued-1'),"
          "('p2','k/shared')");

      final keys = <String>{};
      for (final q in const [
        "SELECT DISTINCT file_key AS k FROM xrays "
            "WHERE file_key IS NOT NULL AND file_key != ''",
        "SELECT DISTINCT file_key AS k FROM pending_uploads "
            "WHERE file_key IS NOT NULL AND file_key != ''",
      ]) {
        for (final r in db.select(q)) {
          final key = '${r['k'] ?? ''}';
          if (key.isNotEmpty) keys.add(key);
        }
      }
      expect(keys, {'k/gallery-1', 'k/shared', 'k/queued-1'},
          reason: 'م185: صورة في الطابور كانت تبقى يتيمة في السحابة');
      expect(keys.contains(''), isFalse);
    });

    test('جدولٌ غائب لا يُفشل التطهير (نسخة أقدم بلا طابور رفع)', () {
      final db = sqlite3.open(':memory:');
      addTearDown(db.close);
      db.execute('CREATE TABLE xrays (id TEXT PRIMARY KEY, file_key TEXT)');
      db.execute("INSERT INTO xrays VALUES ('a','k/only')");
      final keys = <String>{};
      for (final q in const [
        "SELECT DISTINCT file_key AS k FROM xrays "
            "WHERE file_key IS NOT NULL AND file_key != ''",
        'SELECT DISTINCT file_key AS k FROM pending_uploads',
      ]) {
        try {
          for (final r in db.select(q)) {
            final key = '${r['k'] ?? ''}';
            if (key.isNotEmpty) keys.add(key);
          }
        } catch (_) {/* الجدول غائب — يُتخطّى كما في المزوّد */}
      }
      expect(keys, {'k/only'});
    });
  });
}
