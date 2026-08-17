/// مصادقة Supabase الحقيقية فوق واجهة AuthService نفسها التي تعمل بها
/// المصادقة المحلية — نقل دلالات auth.service.js:
///   • استرجاع الجلسة قراءة محلية صرفة بلا شبكة (الملف {dbDir}/session.json)
///     — نفس ملاحظة الأصل عن getSession المتصل بالشبكة داخل SDK.
///   • تحديث استباقي قبل الانتهاء بخمس دقائق، بقفل ضد التزامن، وحد أدنى
///     10 ثوانٍ بين المحاولات، وثلاث محاولات قصوى، وفحص اتصال حقيقي قبل
///     المحاولة (لا يُحسب الفشل أوفلاين)، وعلم «خروج صريح» يمنع اعتبار فشل
///     التحديث خروجاً.
///   • أخطاء عربية مترجمة حرفياً.
library;

import 'dart:async';
import 'dart:convert';

// م82 — من `core` لا من `features`: كسر الدورة.
import '../../core/auth/auth_contracts.dart';
import 'gotrue_client.dart';
import 'session_store.dart';

const _refreshMarginMs = 5 * 60 * 1000;
const _maxRefreshRetries = 3;
const _minRefreshIntervalMs = 10 * 1000;

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({
    required this.client,
    required this.dbDir,
    DateTime Function()? now,
    // م88 — مقبسان اختياريان، وغيابهما = السلوك التاريخي حرفياً:
    //   • [store]: مخزن الجلسة. الافتراض ملف `session.json` نفسه، والإقلاع
    //     السحابي الحقيقي يمرّر المخزن الآمن (لا رموز بنصٍّ واضح).
    //   • [sdk]: جسر جلسة الحزمة الرسمية (دخول Google). حين تحمل الحزمة
    //     جلسةً، تُقدَّم هي — والحزمة وحدها تجدّدها (محرّك جلسة واحد).
    SessionStore? store,
    this.sdk,
  })  : _now = now ?? DateTime.now,
        _store = store ?? FileSessionStore(dbDir) {
    _session = _readStoredSession();
  }

  final GotrueClient client;
  final String dbDir;
  final DateTime Function() _now;
  final SessionStore _store;
  final SdkSessionBridge? sdk;

  GotrueSession? _session;
  bool _persist = true;

  // حالة التحديث (نقل حراس auth.service.js).
  Future<GotrueSession?>? _refreshInProgress;
  int _consecutiveRefreshFailures = 0;
  int _lastRefreshAttemptMs = 0;
  Timer? _refreshTimer;
  bool _explicitLogoutPending = false;

  GotrueSession? _readStoredSession() {
    try {
      final raw = _store.read();
      if (raw == null) return null;
      return GotrueSession.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void _writeStoredSession() {
    if (!_persist) return;
    final s = _session;
    if (s == null) {
      _store.delete();
    } else {
      _store.write(jsonEncode(s.toJson()));
    }
  }

  int get _nowMs => _now().millisecondsSinceEpoch;

  bool _nearExpiry(GotrueSession s) =>
      s.expiresAt * 1000 - _nowMs <= _refreshMarginMs;

  /// جدولة التحديث الاستباقي — scheduleTokenRefresh.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _consecutiveRefreshFailures = 0;
    final s = _session;
    if (s == null || s.expiresAt == 0) return;
    final refreshInMs = s.expiresAt * 1000 - _refreshMarginMs - _nowMs;
    if (refreshInMs <= 0) {
      unawaited(_refreshSession());
      return;
    }
    _refreshTimer =
        Timer(Duration(milliseconds: refreshInMs), () => _refreshSession());
  }

  /// refreshSession — بنفس الحراس الأربعة.
  Future<GotrueSession?> _refreshSession() {
    final inProgress = _refreshInProgress;
    if (inProgress != null) return inProgress;

    if (_nowMs - _lastRefreshAttemptMs < _minRefreshIntervalMs) {
      return Future.value(null);
    }
    _lastRefreshAttemptMs = _nowMs;

    if (_consecutiveRefreshFailures >= _maxRefreshRetries) {
      _consecutiveRefreshFailures = 0;
      return Future.value(null);
    }

    final future = () async {
      final s = _session;
      if (s == null || s.refreshToken.isEmpty) return null;
      // فحص اتصال حقيقي — الفشل أوفلاين لا يُحسب ويُعاد بعد 30 ثانية.
      if (!await client.ping()) {
        _refreshTimer?.cancel();
        _refreshTimer =
            Timer(const Duration(seconds: 30), () => _refreshSession());
        return null;
      }
      try {
        final next = await client.refresh(s.refreshToken);
        _session = next;
        _writeStoredSession();
        _scheduleRefresh();
        _consecutiveRefreshFailures = 0;
        return next;
      } catch (_) {
        _consecutiveRefreshFailures++;
        return null;
      }
    }();
    _refreshInProgress = future.whenComplete(() => _refreshInProgress = null);
    return _refreshInProgress!;
  }

  /// رمز وصول صالح للنقل — يحدّث عند قرب الانتهاء، ويعيد الحالي عند الفشل
  /// (الخادم سيرد 401 فيعاد الدخول في مسار النقل).
  ///
  /// م88 — جلسةُ Google (الحزمة الرسمية) لها الأسبقية حين توجد: الجسر
  /// يجدّدها بنفس العقد، فالمزامنة وR2 تعملان لمستخدم Google بلا تغيير
  /// سطرٍ فيهما.
  Future<String?> validAccessToken() async {
    final bridge = sdk;
    if (bridge != null && bridge.current() != null) {
      return bridge.freshAccessToken();
    }
    final s = _session;
    if (s == null) return null;
    if (_nearExpiry(s)) {
      final refreshed = await _refreshSession();
      return (refreshed ?? _session)?.accessToken;
    }
    return s.accessToken;
  }

  /// إجبار تحديث الجلسة (مسار 401): يتجاوز حارس الحد الأدنى بين المحاولات.
  Future<String?> forceRefresh() async {
    final bridge = sdk;
    if (bridge != null && bridge.current() != null) {
      return bridge.forceRefresh();
    }
    _lastRefreshAttemptMs = 0;
    final refreshed = await _refreshSession();
    return refreshed?.accessToken;
  }

  String? get currentAccessToken => _session?.accessToken;

  void markExplicitLogout() => _explicitLogoutPending = true;
  bool get isExplicitLogout => _explicitLogoutPending;

  // ── واجهة AuthService ──────────────────────────────────────────────────

  @override
  AuthUser? restoreSession() {
    // م88 — جلسة Google أولاً: الحزمة استعادتها من مخزنها الآمن أثناء
    // التهيئة (قبل `runApp`، دون شبكة، ولو كان الرمز منتهياً) وهي التي
    // تجدّدها — فلا يُشغَّل محرّكُ التحديث القائم عليها إطلاقاً.
    final sdkUser = sdk?.current();
    if (sdkUser != null && sdkUser.uid.isNotEmpty) {
      return AuthUser(
        uid: sdkUser.uid,
        email: sdkUser.email,
        displayName: sdkUser.displayName,
      );
    }
    final s = _session;
    if (s == null || s.userId.isEmpty) return null;
    // قراءة محلية صرفة: تُعاد الجلسة ولو كان الرمز منتهياً — التحديث يجري
    // في الخلفية ولا يُطرد المستخدم أوفلاين أبداً (سلوك الأصل).
    _scheduleRefresh();
    return AuthUser(uid: s.userId, email: s.email);
  }

  @override
  Future<AuthUser> login(String email, String password,
      {bool remember = true}) async {
    final err = validateCredentials(email, password);
    if (err != null) throw AuthException(err);
    final session = await client.signInWithPassword(email.trim(), password);
    // م88 — محرّك جلسة واحد: دخولُ كلمة المرور يُسقط أي جلسة Google قائمة
    // في الحزمة، وإلا بقي محرّكان يجدّدان رمزين لهويتين مختلفتين معاً.
    // (خروج الجسر لا يرمي — التنظيف المحلي مضمون ولو أوفلاين.)
    final bridge = sdk;
    if (bridge != null && bridge.current() != null) {
      await bridge.signOut();
    }
    // م68/دفعة ثانٍ-أ — «تذكّرني = لا» يجب أن **يمحو** أي جلسة محفوظة سابقاً.
    //
    // كان `_persist = false` يجعل كتابة الجلسة تعود فوراً دون لمس المخزن،
    // فتبقى جلسةٌ من دخولٍ سابق «بالتذكّر» حاملةً رموز حسابٍ آخر — ويقرؤها
    // المنشئ عند الإقلاع التالي فتُستعاد هوية سابقة. على جهاز عيادة مشترك
    // هذا تسريب رموز بين حسابين، وعكسُ ما طلبه المستخدم صراحةً.
    if (!remember) _store.delete();
    _persist = remember;
    _session = session;
    _explicitLogoutPending = false;
    _writeStoredSession();
    _scheduleRefresh();
    return AuthUser(uid: session.userId, email: session.email);
  }

  @override
  Future<void> register(String email, String password) async {
    final err = validateCredentials(email, password);
    if (err != null) throw AuthException(err);
    await client.signUp(email.trim(), password);
  }

  /// م180/د — إرسال بريد إعادة تعيين كلمة المرور عبر GoTrue.
  @override
  Future<void> sendPasswordReset(String email) async {
    final em = email.trim();
    if (em.isEmpty || !em.contains('@')) {
      throw AuthException('أدخل بريداً إلكترونياً صحيحاً');
    }
    await client.recoverPassword(em);
  }

  /// م186 — إتمام الاستعادة بالرمز: تحقّقٌ يعيد جلسة استرداد ثم تعيين
  /// الكلمة الجديدة بها مباشرة. أخطاء الرمز تصل مترجمةً من العميل.
  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final em = email.trim();
    if (em.isEmpty || !em.contains('@')) {
      throw AuthException('أدخل بريداً إلكترونياً صحيحاً');
    }
    final c = code.trim();
    if (c.length < 6) {
      throw AuthException('أدخل رمز التحقق المكوَّن من 6 أرقام');
    }
    if (newPassword.trim().length < 6) {
      throw AuthException('كلمة المرور الجديدة 6 أحرف على الأقل');
    }
    final recovery = await client.verifyRecoveryCode(em, c);
    await client.updatePassword(recovery.accessToken, newPassword.trim());
  }

  @override
  Future<void> logout() async {
    markExplicitLogout();
    _refreshTimer?.cancel();
    _consecutiveRefreshFailures = 0;
    _refreshInProgress = null;
    final token = _session?.accessToken;
    _session = null;
    _persist = true;
    _writeStoredSession();
    // م88 — خروج جلسة Google عبر الجسر: الحزمة تنظّف مخزنها الآمن محلياً
    // **قبل** نداء إبطال الخادم، وفشلُ الشبكة مُبتلَع — فالخروج يعمل أوفلاين.
    final bridge = sdk;
    if (bridge != null && bridge.current() != null) {
      await bridge.signOut();
    }
    if (token != null && token.isNotEmpty) {
      await client.signOut(token); // فشله غير حرج
    }
  }

  void dispose() => _refreshTimer?.cancel();
}
