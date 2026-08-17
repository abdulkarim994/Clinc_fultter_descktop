/// عميل GoTrue بالحد الأدنى — نفس نداءات supabase-js على السلك مباشرة:
/// دخول (grant_type=password)، تسجيل (/signup)، تحديث جلسة
/// (grant_type=refresh_token)، خروج (/logout) — مع ترجمة أخطاء المصادقة
/// العربية حرفياً من translateAuthError. عميل HTTP قابل للحقن للاختبارات.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

typedef JsonMap = Map<String, Object?>;

/// translateAuthError — حرفياً.
String translateAuthError(String msg) {
  final m = msg.toLowerCase();
  if (m.contains('invalid login')) return 'البريد أو كلمة المرور غير صحيحة';
  if (m.contains('email not confirmed')) return 'البريد لم يتم تأكيده بعد';
  if (m.contains('user not found')) return 'البريد غير مسجّل';
  if (m.contains('invalid email')) return 'صيغة البريد غير صحيحة';
  if (m.contains('rate limit') || m.contains('too many')) {
    return 'محاولات كثيرة، حاول لاحقاً';
  }
  if (m.contains('already registered') ||
      m.contains('already been registered')) {
    return 'البريد مسجّل مسبقاً';
  }
  if (m.contains('password')) return 'كلمة المرور ضعيفة (6 أحرف+)';
  // م186 — أخطاء رمز الاستعادة (نقطة verify): رسالة واحدة للخطأ
  // والانتهاء معاً — الخادم نفسه لا يفرّق فلا نوهم المستخدم بتفريق.
  if (m.contains('otp') ||
      (m.contains('token') &&
          (m.contains('expired') || m.contains('invalid')))) {
    return 'الرمز غير صحيح أو انتهت صلاحيته — اطلب رمزاً جديداً';
  }
  // م185 — أخطاء قاعدة البيانات كانت تظهر للمستخدم بنصّها الإنجليزي الخام
  // (لقطة المالك: رسالة foreign key constraint كاملة في شريط الإشعار).
  // هذه الحالات تعني «الخادم رفض» لا «المستخدم أخطأ»، فتُترجم بوضوح مع
  // إبقاء التفصيل التقني بعيداً عن الطبيب.
  if (m.contains('foreign key constraint') ||
      m.contains('violates foreign key')) {
    return 'تعذّر الحذف: بيانات مرتبطة على الخادم تمنعه — '
        'حدّث التطبيق وأعد المحاولة، وإن تكرر فأبلغ الدعم';
  }
  if (m.contains('not authenticated') || m.contains('28000')) {
    return 'انتهت الجلسة — سجّل الدخول من جديد ثم أعد المحاولة';
  }
  if (m.contains('permission denied') || m.contains('42501')) {
    return 'الخادم رفض العملية لعدم كفاية الصلاحية — لم يُحذف أي شيء';
  }
  return msg;
}

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// م93 — دالة حذف الحساب غير موجودة على الخادم (مهاجرة 0031 لم تُطبَّق
/// بعد). نوعٌ مميّز كي يعرض المستدعي الرسالة الإرشادية الصحيحة ويُجهض
/// بلا أي مسٍّ محلي.
class AccountRpcMissing implements Exception {
  @override
  String toString() =>
      'خدمة حذف الحساب لم تُفعَّل على الخادم بعد (المهاجرة 0031) — '
      'لم يُحذف أي شيء';
}

class GotrueSession {
  const GotrueSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;

  /// ثوانٍ منذ الحقبة (كما يرسلها GoTrue في expires_at).
  final int expiresAt;
  final String userId;
  final String email;

  JsonMap toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'user': {'id': userId, 'email': email},
      };

  static GotrueSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final user = j['user'];
    final access = '${j['access_token'] ?? ''}';
    final refresh = '${j['refresh_token'] ?? ''}';
    if (access.isEmpty || user is! Map) return null;
    var expiresAt = (j['expires_at'] as num?)?.toInt() ?? 0;
    if (expiresAt == 0) {
      final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 3600;
      expiresAt =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    }
    return GotrueSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      userId: '${user['id'] ?? ''}',
      email: '${user['email'] ?? ''}',
    );
  }
}

class GotrueClient {
  GotrueClient({
    required this.baseUrl,
    required this.anonKey,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final http.Client _http;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      };

  String _utf8Body(http.Response res) =>
      utf8.decode(res.bodyBytes, allowMalformed: true);

  Never _throwFrom(http.Response res) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final body = jsonDecode(_utf8Body(res));
      if (body is Map) {
        msg = '${body['error_description'] ?? body['msg'] ?? body['message'] ?? body['error'] ?? msg}';
      }
    } catch (_) {}
    throw AuthException(translateAuthError(msg));
  }

  /// supabase.auth.signInWithPassword.
  Future<GotrueSession> signInWithPassword(
      String email, String password) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/auth/v1/token?grant_type=password'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode >= 400) _throwFrom(res);
    final session = GotrueSession.fromJson(jsonDecode(_utf8Body(res)));
    if (session == null) throw AuthException('استجابة جلسة غير صالحة');
    return session;
  }

  /// supabase.auth.signUp — قد يعيد جلسة أو مستخدماً بانتظار تأكيد البريد.
  Future<GotrueSession?> signUp(String email, String password) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/auth/v1/signup'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode >= 400) _throwFrom(res);
    return GotrueSession.fromJson(jsonDecode(_utf8Body(res)));
  }

  /// م180/د — supabase.auth.resetPasswordForEmail: يرسل بريد إعادة تعيين
  /// كلمة المرور. الخادم **لا يفصح** عن وجود البريد من عدمه (سلوك أمني
  /// مقصود)، فالنجاح هنا يعني «أُرسل إن كان الحساب موجوداً».
  Future<void> recoverPassword(String email) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/auth/v1/recover'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode >= 400) _throwFrom(res);
  }

  /// م186 — التحقق برمز الاسترداد (الأرقام الستة من بريد «نسيت كلمة
  /// المرور»): يعيد **جلسة استرداد** تُستعمل فوراً لتعيين الكلمة الجديدة
  /// عبر [updatePassword] — فلا رابط يُفتح ولا صفحة وسيطة.
  Future<GotrueSession> verifyRecoveryCode(String email, String code) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/auth/v1/verify'),
      headers: _headers,
      body: jsonEncode({
        'type': 'recovery',
        'email': email.trim(),
        'token': code.trim(),
      }),
    );
    if (res.statusCode >= 400) _throwFrom(res);
    final session = GotrueSession.fromJson(jsonDecode(_utf8Body(res)));
    if (session == null) throw AuthException('استجابة جلسة غير صالحة');
    return session;
  }

  /// supabase.auth.refreshSession.
  Future<GotrueSession> refresh(String refreshToken) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/auth/v1/token?grant_type=refresh_token'),
      headers: _headers,
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    if (res.statusCode >= 400) _throwFrom(res);
    final session = GotrueSession.fromJson(jsonDecode(_utf8Body(res)));
    if (session == null) throw AuthException('استجابة جلسة غير صالحة');
    return session;
  }

  /// supabase.auth.signOut — فشله غير حرج (الحالة المحلية مُسحت أصلاً).
  Future<void> signOut(String accessToken) async {
    try {
      await _http.post(
        Uri.parse('$baseUrl/auth/v1/logout'),
        headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      );
    } catch (_) {/* غير حرج */}
  }

  // ── م93 — إدارة الحساب الذاتية ─────────────────────────────────────────

  /// supabase.auth.getUser — هويات الحساب. يهمّنا: هل بين الهويات موفّرُ
  /// `email`؟ وجودُه يعني أن للحساب كلمةَ مرورٍ قائمة (فالتغيير «إعادة
  /// تعيين» تشترط القديمة)، وغيابُه (Google وحده) يعني «تعيين» أول مرة.
  Future<Set<String>> userProviders(String accessToken) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/auth/v1/user'),
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
    );
    if (res.statusCode >= 400) _throwFrom(res);
    final body = jsonDecode(_utf8Body(res));
    final out = <String>{};
    if (body is Map) {
      final ids = body['identities'];
      if (ids is List) {
        for (final e in ids) {
          if (e is Map) {
            final p = '${e['provider'] ?? ''}';
            if (p.isNotEmpty) out.add(p);
          }
        }
      }
      // app_metadata.providers احتياطٌ حين تُحجب identities.
      final meta = body['app_metadata'];
      if (meta is Map && meta['providers'] is List) {
        for (final p in meta['providers'] as List) {
          out.add('$p');
        }
      }
    }
    return out;
  }

  /// supabase.auth.updateUser({password}) — تعيين/تغيير كلمة المرور
  /// للجلسة الحالية. GoTrue يقبلها بمفتاح anon + رمز المستخدم (خدمة
  /// ذاتية)؛ التحققُ من القديمة مسؤولية المستدعي (إعادة مصادقة) — انظر
  /// features/auth/account_admin.dart.
  Future<void> updatePassword(String accessToken, String newPassword) async {
    final res = await _http.put(
      Uri.parse('$baseUrl/auth/v1/user'),
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'password': newPassword}),
    );
    if (res.statusCode >= 400) _throwFrom(res);
  }

  /// م93 — نداء دالة الحذف الذاتي `delete_my_account` (مهاجرة 0031).
  ///
  /// يعيد بصدق ثلاث حالات: نجاح، أو [AccountRpcMissing] حين لم تُطبَّق
  /// المهاجرة بعد (PGRST202/404 — فيُجهض المستدعي بنظافة)، أو
  /// [AuthException] لأي رفضٍ آخر.
  Future<void> deleteMyAccount(String accessToken) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/rest/v1/rpc/delete_my_account'),
      headers: {..._headers, 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode(const <String, Object?>{}),
    );
    if (res.statusCode == 404) throw AccountRpcMissing();
    if (res.statusCode >= 400) {
      try {
        final body = jsonDecode(_utf8Body(res));
        if (body is Map && '${body['code'] ?? ''}' == 'PGRST202') {
          throw AccountRpcMissing();
        }
      } on AccountRpcMissing {
        rethrow;
      } catch (_) {/* ليس PGRST202 ⇒ خطأ عام أدناه */}
      _throwFrom(res);
    }
  }

  /// isActuallyOnline — نداء HEAD حقيقي لنقطة المصادقة.
  Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      await _http
          .head(Uri.parse('$baseUrl/auth/v1/'), headers: {'apikey': anonKey})
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
