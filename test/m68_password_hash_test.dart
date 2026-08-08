/// اختبارات م68/دفعة ثانٍ-أ — تجزئة كلمة المرور والخنق والترحيل.
///
/// العيب الأصلي (H3): SHA-256 عارية بلا ملح ولا تمديد ولا تحديد محاولات.
/// جدولٌ واحد مسبق الحساب يكسر كل النسخ، ومساحة ستة محارف تُستنفد في ثوانٍ.
/// وهاشات المرور لم تكن تُمسح عند تبديل الحساب فتتراكم على الجهاز المشترك.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/auth_service.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/auth/password_hash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م68 — PBKDF2', () {
    test('ملح مختلف لكل تجزئة ⇒ هاشان مختلفان لنفس الكلمة', () {
      final a = hashPassword('كلمةسرية123');
      final b = hashPassword('كلمةسرية123');
      expect(a, isNot(equals(b)),
          reason: 'الملح العشوائي يمنع الجداول المسبقة والتطابق المرئي');
      expect(verifyPassword('كلمةسرية123', a), isTrue);
      expect(verifyPassword('كلمةسرية123', b), isTrue);
    });

    test('الكلمة الصحيحة تُقبل والخاطئة تُرفض', () {
      final h = hashPassword('صحيحة12345');
      expect(verifyPassword('صحيحة12345', h), isTrue);
      expect(verifyPassword('خاطئة12345', h), isFalse);
      expect(verifyPassword('', h), isFalse);
    });

    test('المغلّف يحمل معاملاته فيبقى قابلاً للترقية', () {
      final h = hashPassword('اختبار12345', iterations: 1000);
      final parts = h.split(r'$');
      expect(parts.length, 5);
      expect(parts[0], 'pbkdf2');
      expect(parts[1], 'sha256');
      expect(parts[2], '1000');
      // يُتحقق بتكراراته هو لا بالافتراضي الحالي
      expect(verifyPassword('اختبار12345', h), isTrue);
      // وتكرارات أقل من الحالي ⇒ يستحق الترقية
      expect(needsRehash(h), isTrue);
    });

    test('PBKDF2 مطابقة لمتجه RFC 6070 (سلامة التنفيذ)', () {
      // RFC 6070 مُعرَّف لـ SHA-1؛ نستعمل متجهاً محسوباً لـ SHA-256:
      // P="password", S="salt", c=1, dkLen=32
      final out = pbkdf2(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
        keyLength: 32,
      );
      // القيمة المرجعية المعروفة لـ PBKDF2-HMAC-SHA256(password,salt,1,32)
      const expected =
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b';
      final hex =
          out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, expected, reason: 'التنفيذ مطابق للمعيار');
    });

    test('التوافق الخلفي: الهاش القديم يُقبل ويُوسم للترحيل', () {
      final legacy = sha256.convert(utf8.encode('قديمة12345')).toString();
      expect(isLegacyHash(legacy), isTrue);
      expect(verifyPassword('قديمة12345', legacy), isTrue,
          reason: 'لا نقفل الحسابات القائمة');
      expect(verifyPassword('غلط12345', legacy), isFalse);
      expect(needsRehash(legacy), isTrue);
    });
  });

  group('م68 — LocalAuthService', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m68_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ({ProviderContainer c, dynamic db, LocalAuthService auth}) boot() {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      final db = c.read(localDbProvider);
      return (c: c, db: db, auth: LocalAuthService(db));
    }

    String? storedHash(dynamic db, String email) => db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?',
        const ['local_auth_accounts'])?['value'] as String?;

    test('التسجيل يخزّن مغلّف PBKDF2 لا هاشاً عارياً', () async {
      final b = boot();
      addTearDown(b.c.dispose);
      await b.auth.register('a@b.com', 'كلمةقوية123');
      final raw = storedHash(b.db, 'a@b.com')!;
      expect(raw, contains('pbkdf2\$sha256\$'));
      expect(raw, isNot(matches(RegExp(r'"[0-9a-f]{64}"'))),
          reason: 'لا هاش SHA-256 عارٍ مخزَّن');
    });

    test('الدخول الصحيح ينجح والخاطئ يفشل', () async {
      final b = boot();
      addTearDown(b.c.dispose);
      await b.auth.register('a@b.com', 'كلمةقوية123');
      final u = await b.auth.login('a@b.com', 'كلمةقوية123');
      expect(u.email, 'a@b.com');
      expect(() => b.auth.login('a@b.com', 'خطأ12345'), throwsException);
    });

    test('ترحيل شفاف: حساب قديم يُعاد تجزئته عند أول دخول ناجح', () async {
      final b = boot();
      addTearDown(b.c.dispose);
      // نزرع حساباً بالصيغة القديمة يدوياً (كما كان يكتبه الإصدار السابق)
      final legacy = sha256.convert(utf8.encode('قديمة12345')).toString();
      b.db.execute(
          'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
          "VALUES ('local_auth_accounts', ?, datetime('now'))",
          [jsonEncode({'old@b.com': legacy})]);

      expect(storedHash(b.db, 'old@b.com'), contains(legacy));
      await b.auth.login('old@b.com', 'قديمة12345'); // ينجح رغم قِدَمه
      final after = storedHash(b.db, 'old@b.com')!;
      expect(after, contains('pbkdf2\$sha256\$'),
          reason: 'م68: رُحِّل تلقائياً بلا مطالبة المستخدم');
      expect(after, isNot(contains(legacy)));
      // ويبقى الدخول عاملاً بعد الترحيل
      await b.auth.login('old@b.com', 'قديمة12345');
    });

    test('الخنق: قفل مؤقت بعد تتابع محاولات فاشلة', () async {
      final b = boot();
      addTearDown(b.c.dispose);
      await b.auth.register('a@b.com', 'كلمةقوية123');
      for (var i = 0; i < 5; i++) {
        try {
          await b.auth.login('a@b.com', 'غلط12345');
        } catch (_) {/* متوقَّع */}
      }
      // المحاولة التالية تُرفض بالقفل حتى لو كانت الكلمة صحيحة
      await expectLater(
        b.auth.login('a@b.com', 'كلمةقوية123'),
        throwsA(predicate((e) => '$e'.contains('محاولات كثيرة'))),
      );
    });

    test('الحد الأدنى للطول ثمانية', () {
      expect(validateCredentials('a@b.com', '1234567'), isNotNull);
      expect(validateCredentials('a@b.com', '12345678'), isNull);
    });

    test('مسح الحساب يزيل هاشات المرور المتراكمة', () async {
      final b = boot();
      addTearDown(b.c.dispose);
      await b.auth.register('a@b.com', 'كلمةقوية123');
      expect(storedHash(b.db, 'a@b.com'), isNotNull);
      wipeAllAccountData(b.db);
      expect(storedHash(b.db, 'a@b.com'), isNull,
          reason: 'م68: لا أرشيف اعتمادات على الجهاز المشترك');
    });
  });
}
