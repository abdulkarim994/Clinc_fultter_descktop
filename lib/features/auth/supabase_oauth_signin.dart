/// ============================================================================
///  م88 — التنفيذ الحقيقي لدخول Google: الحزمة الرسمية بتدفّق PKCE
/// ============================================================================
///
///  لا OAuth مخصّصاً هنا — كلُّ التشفير والتبادل من `supabase_flutter`:
///  الحزمة تولّد مُتحقِّق PKCE وتخزّنه، تبني رابط `/authorize`، وتبدّل
///  الرمزَ بجلسة. هذا الملف **توصيلُ منصّاتٍ** فقط: كيف يُفتح المتصفح وكيف
///  تعود النتيجة.
///
///  مساران بحسب المنصّة
///  ───────────────────
///  • **أندرويد** — deep-link: المتصفح الخارجي (Google ترفض WebView) يعود
///    إلى `dentaldk://login-callback`؛ الحزمة تلتقط الرابط عبر مراقبها
///    وتبدّل الرمز بنفسها ثم تبثّ `signedIn` — فننتظر البثّ لا الرابط.
///  • **ويندوز/لينكس** — loopback: لا مخطط URI مسجّلاً لدى النظام، فيُفتح
///    خادمُ استماعٍ محلي على المنفذ **43823** (المثبَّت حرفياً في
///    `uri_allow_list` على الخادم — تغييره هنا يكسر العودة)، ويستقبل
///    `?code=` ثم تُستدعى `exchangeCodeForSession`.
///
///  حدود ما يُختبر في الصندوق
///  ─────────────────────────
///  دورةُ المتصفح الحقيقية تحتاج جهازاً. المُختبَر آلياً: مستقبِل الـloopback
///  كاملاً (بطلبات HTTP حقيقية)، وبناء النتيجة من بيانات المستخدم، وكلُّ
///  المنطق حول الواجهة عبر المزيّف. والتحقّق على جهازٍ حقيقي بندٌ صريح في
///  التقرير — كما البصمة وKeystore.
library;

import 'dart:async';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignIn, GoogleSignInException, GoogleSignInExceptionCode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

import '../../core/error_log.dart' show recordError;
import 'oauth_signin.dart';

/// رابط عودة أندرويد — مطابقٌ حرفياً لما أُضيف في `uri_allow_list`
/// ولمرشّح النية في `AndroidManifest.xml`.
const kAndroidRedirect = 'dentaldk://login-callback';

/// منفذ عودة المكتب — مثبَّت في `uri_allow_list` (`http://localhost:43823`).
const kDesktopLoopbackPort = 43823;

/// مهلة انتظار المستخدم في المتصفح: تكفي لاختيار حساب وموافقة على مهل،
/// ولا تُبقي التطبيق معلّقاً للأبد لو أغلق المتصفحَ ونسي.
const kOAuthWaitTimeout = Duration(minutes: 3);

/// مستقبِل رمز العودة على المنفذ المحلي — معزولٌ ليُختبر بطلبات حقيقية.
class LoopbackCodeReceiver {
  LoopbackCodeReceiver({this.port = kDesktopLoopbackPort});

  final int port;
  HttpServer? _server;
  final _code = Completer<String>();

  /// عنوان العودة الذي يُمرَّر لـ`redirectTo` — دون شرطة مائلة أخيرة
  /// (كلا الشكلين في قائمة السماح، وهذا المعتمد).
  String get redirectUrl => 'http://localhost:${_server?.port ?? port}';

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      throw const OAuthUnavailable(
          'تعذّر فتح منفذ استقبال الدخول (43823) — أغلق أي تشغيلٍ آخر '
          'للتطبيق ثم أعد المحاولة.');
    }
    _server!.listen(_handle, onError: (Object _) {/* طلبات مشوهة تُتجاهل */});
  }

  void _handle(HttpRequest req) {
    final params = req.uri.queryParameters;
    final code = params['code'];
    final error = params['error'];

    // المتصفحات تطلب /favicon.ico وغيره — ما ليس نتيجةَ OAuth لا يستهلك
    // الانتظار ولا يُجيب بصفحة النجاح.
    if (code == null && error == null) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final ok = error == null;
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
      ..write(_page(ok))
      ..close();

    if (_code.isCompleted) return;
    if (ok) {
      _code.complete(code!);
    } else {
      _code.completeError(OAuthUnavailable(error == 'access_denied'
          ? 'أُلغي الدخول من صفحة Google.'
          : 'رفض مزوّد الدخول العملية: '
              '${params['error_description'] ?? error}'));
    }
  }

  /// ينتظر رمز العودة أو يرمي [OAuthUnavailable] عند الإلغاء/المهلة.
  Future<String> waitForCode({Duration timeout = kOAuthWaitTimeout}) =>
      _code.future.timeout(timeout, onTimeout: () {
        throw const OAuthUnavailable(
            'لم تكتمل عملية الدخول في الوقت المحدد — أُغلق المتصفح أو '
            'أُلغيت العملية. أعد المحاولة.');
      });

  Future<void> close() async => _server?.close(force: true);

  static String _page(bool ok) => '''
<!DOCTYPE html><html dir="rtl" lang="ar"><head><meta charset="utf-8">
<title>طب الأسنان الرقمي</title></head>
<body style="font-family:sans-serif;background:#0A3024;color:#fff;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<div style="text-align:center">
<div style="font-size:48px">${ok ? '✅' : '❌'}</div>
<h2>${ok ? 'اكتمل تسجيل الدخول' : 'لم يكتمل تسجيل الدخول'}</h2>
<p>${ok ? 'يمكنك إغلاق هذه الصفحة والعودة إلى التطبيق.' : 'أغلق هذه الصفحة وأعد المحاولة من التطبيق.'}</p>
</div></body></html>''';
}

/// التنفيذ الحقيقي فوق الحزمة الرسمية — يُركَّب في الإقلاع السحابي فقط
/// (بعد اكتمال `Supabase.initialize`)، والاختبارات تبقى على المزيّف.
class SupabaseSdkOAuthSignIn implements OAuthSignIn {
  SupabaseSdkOAuthSignIn({
    GoTrueClient Function()? auth,
    bool? useLoopback,
    this.serverClientId = '',
    Future<String> Function()? nativeAuth,
    Future<Session> Function()? browserFlow,
  })  : _auth = auth ?? (() => Supabase.instance.client.auth),
        _useLoopback = useLoopback ??
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS),
        _nativeAuthOverride = nativeAuth,
        _browserFlowOverride = browserFlow;

  final GoTrueClient Function() _auth;
  final bool _useLoopback;

  /// م88/ج — معرّف عميل الويب: وجوده يفعّل المسار الأصلي على أندرويد.
  final String serverClientId;

  /// مقبسا اختبار: المصادقة الأصلية (تعيد idToken) ومسار المتصفح — دورة
  /// google_sign_in الحقيقية تحتاج خدمات Google Play على جهاز.
  final Future<String> Function()? _nativeAuthOverride;
  final Future<Session> Function()? _browserFlowOverride;

  bool get _nativeConfigured =>
      _nativeAuthOverride != null || serverClientId.isNotEmpty;

  @override
  Future<OAuthResult> signInWithGoogle() async {
    try {
      return _toResult(await _pickFlow());
    } on OAuthUnavailable {
      rethrow;
    } on AuthException catch (e) {
      // أخطاء GoTrue (رمز مرفوض، مُتحقِّق مفقود...) — رسالة عربية واحدة
      // صادقة مع التفصيل التقني ذيلاً للتشخيص.
      throw OAuthUnavailable('تعذّر إتمام الدخول بحساب Google: ${e.message}');
    } on SocketException {
      throw const OAuthUnavailable(
          'لا يوجد اتصال بالإنترنت — الدخول بحساب Google يحتاج اتصالاً '
          'في المرة الأولى.');
    }
  }

  Future<Session> _pickFlow() async {
    if (_useLoopback) return _browserFlowOverride?.call() ?? _loopbackFlow();

    // م88/ج — أندرويد: المسار الأصلي أولاً (نافذة حسابات الجهاز داخل
    // التطبيق، تحمل **اسم التطبيق** لا رابط الخادم — ملاحظتا المالك معاً).
    // إلغاء المستخدم قرارٌ يُحترم فلا يُفتح متصفح بعده؛ أما تعذّر المسار
    // نفسه (عميل أندرويد لم يُنشأ بعد في Google، جهاز بلا خدمات Google)
    // فيسقط **بصمت مسجَّل** إلى مسار المتصفح — دخولٌ يعمل دائماً خيرٌ من
    // زرٍّ معطوب في عيادة.
    if (_nativeConfigured) {
      try {
        return await _nativeFlow();
      } on OAuthUnavailable {
        rethrow; // إلغاءٌ صريح من المستخدم — لا مسار ثانٍ.
      } catch (e, st) {
        recordError(e, st, context: 'google-native:fallback');
      }
    }
    return _browserFlowOverride?.call() ?? _deepLinkFlow();
  }

  /// المسار الأصلي: google_sign_in (نافذة الحسابات) ⇒ idToken بجمهور
  /// عميل الويب نفسه المضبوط في Supabase ⇒ `signInWithIdToken` الرسمي.
  Future<Session> _nativeFlow() async {
    final idToken = await (_nativeAuthOverride ?? _defaultNativeAuth)();
    final res = await _auth().signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    final session = res.session;
    if (session == null) {
      throw const AuthException('استجابة دخول بلا جلسة');
    }
    return session;
  }

  Future<String> _defaultNativeAuth() async {
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: serverClientId);
    try {
      final account =
          await signIn.authenticate(scopeHint: const ['email', 'profile']);
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw StateError('idToken فارغ من google_sign_in');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const OAuthUnavailable('أُلغي الدخول.');
      }
      rethrow; // يعالجه السقوط الرشيق في _pickFlow.
    }
  }

  /// أندرويد: الحزمة تلتقط deep-link العودة وتُتمّ التبادل — فالنجاح يصل
  /// بثّاً (`signedIn`)، والانتظار عليه لا على الرابط.
  Future<Session> _deepLinkFlow() async {
    final auth = _auth();
    final done = Completer<Session>();
    late final StreamSubscription<AuthState> sub;
    sub = auth.onAuthStateChange.listen((change) {
      final s = change.session;
      if (change.event == AuthChangeEvent.signedIn &&
          s != null &&
          !done.isCompleted) {
        done.complete(s);
      }
    }, onError: (Object e) {
      if (!done.isCompleted && e is AuthException) {
        done.completeError(
            OAuthUnavailable('تعذّر إتمام الدخول: ${e.message}'));
      }
    });

    try {
      final launched = await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kAndroidRedirect,
        // متصفحٌ خارجي إلزاماً: Google ترفض WebView المدمج
        // (disallowed_useragent) — والحزمة تفرضه لأندرويد أصلاً.
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const OAuthUnavailable(
            'تعذّر فتح المتصفح لإتمام الدخول — تأكد من وجود متصفح على '
            'الجهاز ثم أعد المحاولة.');
      }
      return await done.future.timeout(kOAuthWaitTimeout, onTimeout: () {
        throw const OAuthUnavailable(
            'لم تكتمل عملية الدخول في الوقت المحدد — أُغلق المتصفح أو '
            'أُلغيت العملية. أعد المحاولة.');
      });
    } finally {
      await sub.cancel();
    }
  }

  /// المكتب: loopback محلي + تبادلٌ يدوي للرمز (PKCE عبر الحزمة نفسها).
  Future<Session> _loopbackFlow() async {
    final auth = _auth();
    final receiver = LoopbackCodeReceiver();
    await receiver.start();
    try {
      final res = await auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: receiver.redirectUrl,
      );
      final opened = await launchUrl(Uri.parse(res.url),
          mode: LaunchMode.externalApplication);
      if (!opened) {
        throw const OAuthUnavailable(
            'تعذّر فتح المتصفح لإتمام الدخول — افتح متصفحاً ثم أعد '
            'المحاولة.');
      }
      final code = await receiver.waitForCode();
      final exchanged = await auth.exchangeCodeForSession(code);
      return exchanged.session;
    } finally {
      await receiver.close();
    }
  }

  OAuthResult _toResult(Session session) {
    final user = session.user;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    return OAuthResult(
      uid: user.id,
      email: user.email ?? '',
      // نفس مفاتيح تريغر `profiles` على الخادم (هجرة 0030) — مصدر واحد.
      displayName: str(meta['full_name']) ?? str(meta['name']),
      avatarUrl: str(meta['avatar_url']) ?? str(meta['picture']),
    );
  }
}
