/// ============================================================================
///  تجزئة كلمات المرور المحلية — م68/دفعة ثانٍ-أ
/// ============================================================================
///
///  العلة المُصلَحة
///  ──────────────
///  كانت الكلمة تُجزَّأ بـ `sha256.convert(utf8.encode(s))` العارية: **بلا
///  ملح** — فجدولٌ واحد مسبق الحساب يكسر كل النسخ دفعةً واحدة، والحسابات
///  المتطابقة الكلمة تظهر متطابقة الهاش — و**بلا تمديد**، وSHA-256 مصمَّمة
///  لتكون سريعة، فمساحة ستة محارف تُستنفد في ثوانٍ على كرت رسوميات.
///
///  الحل هنا
///  ────────
///  PBKDF2-HMAC-SHA256 مبنيّة نقيّةً على حزمة `crypto` القائمة — **بلا أي
///  اعتماد جديد** (Argon2id أقوى نظرياً لكنه يستلزم حزمة خارجية غير مُدقّقة
///  في هذا المشروع؛ PBKDF2 معيار راسخ وكافٍ هنا، والمغلّف يسمح بالترقية
///  إليه لاحقاً بلا كسر الحسابات القائمة).
///
///  المغلّف المخزَّن نصّي وقابل للترقية:
///      `pbkdf2$sha256$<iterations>$<saltB64>$<hashB64>`
///  فتغيير الخوارزمية أو رفع التكرارات مستقبلاً لا يكسر ما سبق: [verify]
///  تقرأ المعاملات من المغلّف نفسه.
///
///  التوافق الخلفي
///  ──────────────
///  [verify] تقبل أيضاً الهاش القديم (SHA-256 عارية، ستّ وستون محرفاً hex)،
///  و[needsRehash] تُعلم المستدعي أنه يجب إعادة التجزئة — فيُرحَّل الحساب
///  **شفافياً عند أول دخول ناجح** بلا مطالبة المستخدم بتغيير كلمته.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// عدد تكرارات PBKDF2. رفعه لاحقاً آمن: المغلّف يحمل قيمته لكل حساب،
/// فالحسابات القديمة تُتحقَّق بقيمتها ثم تُرحَّل عند أول دخول.
const int kPbkdf2Iterations = 120000;

/// طول الملح والمفتاح بالبايت.
const int _saltBytes = 16;
const int _keyBytes = 32;

const String _algoTag = 'pbkdf2';
const String _prfTag = 'sha256';

final Random _rng = Random.secure();

Uint8List _randomSalt() =>
    Uint8List.fromList([for (var i = 0; i < _saltBytes; i++) _rng.nextInt(256)]);

/// PBKDF2-HMAC-SHA256 (RFC 8018) — تنفيذ نقي فوق Hmac من حزمة crypto.
Uint8List pbkdf2({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int keyLength = _keyBytes,
}) {
  final hmac = Hmac(sha256, password);
  const hLen = 32; // مخرج SHA-256
  final blocks = (keyLength + hLen - 1) ~/ hLen;
  final out = BytesBuilder();

  for (var block = 1; block <= blocks; block++) {
    // U1 = PRF(password, salt || INT_32_BE(block))
    final blockIndex = Uint8List(4)
      ..[0] = (block >> 24) & 0xff
      ..[1] = (block >> 16) & 0xff
      ..[2] = (block >> 8) & 0xff
      ..[3] = block & 0xff;
    var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
    final acc = Uint8List.fromList(u);
    // Ui = PRF(password, Ui-1) ثم XOR تراكمي
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < hLen; j++) {
        acc[j] ^= u[j];
      }
    }
    out.add(acc);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, keyLength));
}

/// يُنشئ مغلّفاً جديداً بملح عشوائي لكل حساب.
String hashPassword(String password, {int iterations = kPbkdf2Iterations}) {
  final salt = _randomSalt();
  final key = pbkdf2(
    password: utf8.encode(password),
    salt: salt,
    iterations: iterations,
  );
  return '$_algoTag\$$_prfTag\$$iterations\$'
      '${base64.encode(salt)}\$${base64.encode(key)}';
}

/// مقارنة بزمن ثابت — لا تُفشي طول التطابق عبر توقيت الردّ.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final RegExp _legacyHex = RegExp(r'^[0-9a-f]{64}$');

/// هل المخزَّن بالصيغة القديمة (SHA-256 عارية)؟
bool isLegacyHash(String stored) => _legacyHex.hasMatch(stored);

/// يتحقق من الكلمة مقابل المخزَّن — يقبل المغلّف الجديد **والهاش القديم**.
bool verifyPassword(String password, String stored) {
  if (stored.isEmpty) return false;

  // المسار القديم: SHA-256 عارية (يُرحَّل بعد النجاح — انظر needsRehash).
  if (isLegacyHash(stored)) {
    final legacy = sha256.convert(utf8.encode(password)).toString();
    return _constantTimeEquals(utf8.encode(legacy), utf8.encode(stored));
  }

  final parts = stored.split(r'$');
  if (parts.length != 5) return false;
  if (parts[0] != _algoTag || parts[1] != _prfTag) return false;
  final iterations = int.tryParse(parts[2]);
  if (iterations == null || iterations <= 0) return false;
  Uint8List salt;
  Uint8List expected;
  try {
    salt = base64.decode(parts[3]);
    expected = base64.decode(parts[4]);
  } catch (_) {
    return false;
  }

  // م78 — الحارس الذي كان ناقصاً: **مغلّف بهاش فارغ كان يقبل أي كلمة مرور**.
  //
  //  الآلية: الاشتقاق أدناه يستعمل `keyLength: expected.length`. فمغلّف مثل
  //  `pbkdf2$sha256$1$c2FsdA==$` (حقله الأخير فارغ) يجتاز كل فحوص الصيغة
  //  أعلاه، ثم يُنتج `blocks = (0 + 32 - 1) ~/ 32 = 0` فلا تدور حلقة
  //  الاشتقاق أصلاً وتُرجع مفتاحاً بطول صفر. وتُقارَن قائمتان فارغتان في
  //  [_constantTimeEquals] فتتساوى الأطوال ويبقى مُراكم XOR صفراً ⇒ **صحيح**.
  //
  //  ولأن القاعدة غير مشفّرة، من يستطيع كتابة صفٍّ في `local_auth_accounts`
  //  يزرع هذا المغلّف ثم يدخل بأي كلمة. والأخطر أنه **يترك مغلّفاً يبدو
  //  سليم الشكل**، فيجتاز أي فحص سلامة يتحقق من الصيغة وحدها.
  //
  //  الحدّ 16 بايتاً لا 32: مغلّفات مستقبلية قد تستعمل طولاً مختلفاً،
  //  والغرض رفض المنحطّ لا تثبيت الطول الحالي.
  if (expected.length < 16 || salt.isEmpty) return false;

  final actual = pbkdf2(
    password: utf8.encode(password),
    salt: salt,
    iterations: iterations,
    keyLength: expected.length,
  );
  return _constantTimeEquals(actual, expected);
}

/// هل يجب إعادة تجزئة المخزَّن بالمعاملات الحالية؟ (ترحيل شفاف)
bool needsRehash(String stored, {int iterations = kPbkdf2Iterations}) {
  if (stored.isEmpty) return true;
  if (isLegacyHash(stored)) return true; // الصيغة القديمة تُرحَّل دائماً
  final parts = stored.split(r'$');
  if (parts.length != 5) return true;
  if (parts[0] != _algoTag || parts[1] != _prfTag) return true;
  final it = int.tryParse(parts[2]);
  return it == null || it < iterations; // رفع التكرارات يستدعي الترقية
}
