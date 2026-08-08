/// ============================================================================
///  خدمة المصادقة — واجهة قابلة للاستبدال (م5 يوصل SupabaseAuth)
/// ============================================================================
///
///  مسار Vue الأصلي: auth.store.doLogin/doRegister فوق Supabase. في م3 نبني
///  نفس عقد الواجهة فوق مخزن محلي (جدول metadata) حتى تُختبر الشاشات والتدفق
///  كاملاً دون سحابة — مع نفس رسائل التحقق العربية.
library;

export '../../core/auth/auth_contracts.dart'
    show AuthService, AuthUser, validateCredentials;

import 'dart:convert';

import '../../core/auth/auth_contracts.dart';
import '../../data/db/local_db.dart';
import 'password_hash.dart';

// م82 — `AuthUser` و`AuthService` و`validateCredentials` انتقلت إلى
// `core/auth/auth_contracts.dart` لكسر دورة الاعتماد: طبقة البيانات كانت
// تستورد من طبقة الميزات لتنفّذ الواجهة. تُعاد تصديرها هنا فيبقى كل
// مستورد قائم يعمل بلا تغيير.

/// مصادقة محلية (وضع بلا سحابة): الحسابات والجلسة في جدول metadata.
class LocalAuthService implements AuthService {
  LocalAuthService(this.db);

  final LocalDb db;

  static const _accountsKey = 'local_auth_accounts';
  static const _sessionKey = 'local_auth_session';

  // م68/دفعة ثانٍ-أ — خنق المحاولات الفاشلة في الذاكرة.
  //
  // لا يمنع مهاجماً يقرأ القاعدة مباشرة (الحماية هناك هي PBKDF2 نفسها)، لكنه
  // يوقف التخمين المتتالي عبر الواجهة على جهاز مفتوح. في الذاكرة عمداً: لا
  // نكتب عدّادات فاشلة إلى القاعدة فتُزامَن أو تُستغل لقفل حساب عن بُعد.
  static const _maxAttempts = 5;
  static const _lockoutMs = 30 * 1000;
  final Map<String, ({int fails, int until})> _throttle = {};

  Map<String, Object?> _accounts() {
    final row = db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?', const [_accountsKey]);
    final v = row?['value'];
    if (v is String && v.isNotEmpty) {
      try {
        final m = jsonDecode(v);
        if (m is Map) return Map<String, Object?>.from(m);
      } catch (_) {/* fresh */}
    }
    return {};
  }

  void _saveMeta(String key, String value) => db.execute(
        'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
        "VALUES (?, ?, datetime('now'))",
        [key, value],
      );

  @override
  AuthUser? restoreSession() {
    final row = db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?', const [_sessionKey]);
    final v = row?['value'];
    if (v is! String || v.isEmpty) return null;
    try {
      final m = jsonDecode(v) as Map;
      return AuthUser(uid: m['uid'] as String, email: m['email'] as String);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser> login(String email, String password,
      {bool remember = true}) async {
    final err = validateCredentials(email, password);
    if (err != null) throw Exception(err);
    final em = email.trim().toLowerCase();

    // خنق المحاولات: قفل قصير بعد تتابع فاشل.
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = _throttle[em];
    if (t != null && t.until > now) {
      final secs = ((t.until - now) / 1000).ceil();
      throw Exception('محاولات كثيرة — انتظر $secs ثانية ثم أعد المحاولة');
    }

    final accounts = _accounts();
    final stored = accounts[em];
    if (stored == null) {
      throw Exception('لا يوجد حساب بهذا البريد — أنشئ حساباً أولاً');
    }
    if (!verifyPassword(password, '$stored')) {
      final fails = (t?.fails ?? 0) + 1;
      _throttle[em] = (
        fails: fails,
        until: fails >= _maxAttempts ? now + _lockoutMs : 0,
      );
      throw Exception('كلمة المرور غير صحيحة');
    }
    _throttle.remove(em); // نجاح ⇒ صفّر العدّاد

    // ترحيل شفاف: الحساب المخزَّن بالصيغة القديمة (أو بتكرارات أقل) يُعاد
    // تجزئته بالمعاملات الحالية عند أول دخول ناجح — بلا مطالبة المستخدم.
    if (needsRehash('$stored')) {
      accounts[em] = hashPassword(password);
      _saveMeta(_accountsKey, jsonEncode(accounts));
    }

    final user = AuthUser(uid: 'local:$em', email: em);
    if (remember) {
      _saveMeta(_sessionKey, jsonEncode({'uid': user.uid, 'email': em}));
    }
    return user;
  }

  @override
  Future<void> register(String email, String password) async {
    final err = validateCredentials(email, password);
    if (err != null) throw Exception(err);
    final em = email.trim().toLowerCase();
    final accounts = _accounts();
    if (accounts.containsKey(em)) {
      throw Exception('يوجد حساب بهذا البريد مسبقاً');
    }
    accounts[em] = hashPassword(password);
    _saveMeta(_accountsKey, jsonEncode(accounts));
  }

  @override
  Future<void> logout() async => _saveMeta(_sessionKey, '');
}
