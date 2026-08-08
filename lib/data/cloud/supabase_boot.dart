/// ============================================================================
///  م88 — تهيئة الحزمة الرسمية: PKCE + تخزينٌ آمن + جسر الجلسة
/// ============================================================================
///
///  ثلاثة قرارات مثبَّتة هنا
///  ───────────────────────
///  ١) **PKCE صراحةً لا اتكالاً على الافتراض** — نصُّ م88 يحظر Implicit،
///     والاعتماد على افتراضٍ قد يتغيّر بين إصدارات الحزمة ليس التزاماً.
///  ٢) **مخزنا الحزمة كلاهما آمنان**: جلسةُ `sb-…-auth-token` **و**مُتحقِّق
///     PKCE — افتراضُ الحزمة `SharedPreferences` (نصٌّ واضح على القرص)،
///     ونصُّ م88 يحظره للرموز. `LocalStorage` و`GotrueAsyncStorage` هما
///     نقطتا التمديد الرسميتان لذلك بالضبط.
///  ٣) **جسرٌ رقيق فوق `Supabase.instance`** — طبقةُ النقل (المزامنة/R2)
///     تكلّم عقدَ `core` لا الحزمة، والاختبارات تزيّفه بلا منصّة.
///
///  الأوفلاين — لماذا هذا آمن (مُتحقَّقٌ من مصدر الحزمة نفسه، v2.16.0)
///  ─────────────────────────────────────────────────────────────────
///  • `setInitialSession` يعيد الجلسة من المخزن **دون فحص انتهاءٍ ولا
///    شبكة** أثناء `initialize` — فالإقلاع أوفلاين يُبقي المستخدم داخلاً.
///  • فشلُ التجديد الشبكي (`AuthRetryableFetchException`) **لا يمسح
///    الجلسة** — يُبلَّغ ويُعاد لاحقاً. الجلسة تُمحى فقط برفضٍ قاطع من
///    الخادم (رمز تحديث باطل) — نفس فلسفة محرّكنا القائم حرفياً.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_contracts.dart';
import 'cloud_config.dart';
import 'session_store.dart' show AsyncKv;

/// نفس اشتقاق الحزمة الافتراضي لمفتاح الجلسة — يُثبَّت هنا كي يبقى ثابتاً
/// لو غيّرت الحزمة افتراضها (تغييره = خروجُ كل المستخدمين بصمت).
String sdkSessionKeyFor(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

/// تخزين جلسة الحزمة في مخزن أسرار النظام (Keystore/DPAPI) — بديل
/// `SharedPreferencesLocalStorage` النصّي، عبر نقطة التمديد الرسمية.
class SecureSdkLocalStorage extends LocalStorage {
  const SecureSdkLocalStorage({required this.kv, required this.key});

  final AsyncKv kv;
  final String key;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await kv.read(key)) != null;

  @override
  Future<String?> accessToken() => kv.read(key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      kv.write(key, persistSessionString);

  @override
  Future<void> removePersistedSession() => kv.delete(key);
}

/// مخزن مُتحقِّق PKCE — قصير العمر لكنه سرُّ التدفّق: من يقرؤه أثناء دورةٍ
/// معلّقة يستطيع تبديل الرمز بجلسة. يسكن مخزن الأسرار كالجلسة سواء.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  const SecureGotrueAsyncStorage({required this.kv});

  final AsyncKv kv;

  // تمييز مفاتيح الحزمة عن مفاتيحنا داخل مخزن النظام المشترك.
  String _k(String key) => 'dental.sdk.$key';

  @override
  Future<String?> getItem({required String key}) => kv.read(_k(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      kv.write(_k(key), value);

  @override
  Future<void> removeItem({required String key}) => kv.delete(_k(key));
}

/// تهيئة الحزمة — تُستدعى مرةً واحدة قبل `runApp` وفي الوضع السحابي فقط.
/// بعد اكتمالها تكون الجلسة المخزَّنة مُستعادةً و`currentSession` جاهزاً
/// للقراءة المتزامنة (وهذا ما يعتمده `restoreSession` عند الإقلاع).
Future<void> initSupabaseSdk({
  required CloudConfig cfg,
  required AsyncKv kv,
}) async {
  await Supabase.initialize(
    url: cfg.supabaseUrl,
    // مشروعنا على مفتاح anon الموروث (JWT) — معلمة `publishableKey` تخص
    // صيغة المفاتيح الجديدة `sb_publishable_…` ولم نُصدرها بعد. الانتقال
    // قرارُ خادمٍ منفصل، لا يُهرَّب عبر معلمةٍ باسمٍ مضلِّل.
    // ignore: deprecated_member_use
    anonKey: cfg.anonKey,
    authOptions: FlutterAuthClientOptions(
      // PKCE نصّاً — شرط م88 الحرفي، لا اتكالاً على افتراض الحزمة.
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      localStorage:
          SecureSdkLocalStorage(kv: kv, key: sdkSessionKeyFor(cfg.supabaseUrl)),
      pkceAsyncStorage: SecureGotrueAsyncStorage(kv: kv),
      // مراقب deep-link — به يلتقط أندرويد عودة `dentaldk://login-callback`.
      detectSessionInUri: true,
    ),
  );
}

/// الجسر الحقيقي فوق عميل الحزمة — تنفيذ عقد `core` الرقيق.
class SupabaseSdkBridge implements SdkSessionBridge {
  SupabaseSdkBridge({GoTrueClient Function()? auth, DateTime Function()? now})
      : _auth = auth ?? (() => Supabase.instance.client.auth),
        _now = now ?? DateTime.now;

  final GoTrueClient Function() _auth;
  final DateTime Function() _now;

  static const _marginSeconds = 5 * 60; // نفس هامش المحرّك القائم.

  @override
  SdkSessionInfo? current() {
    final s = _auth().currentSession;
    if (s == null) return null;
    final meta = s.user.userMetadata ?? const <String, dynamic>{};
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    return SdkSessionInfo(
      uid: s.user.id,
      email: s.user.email ?? '',
      displayName: str(meta['full_name']) ?? str(meta['name']),
      avatarUrl: str(meta['avatar_url']) ?? str(meta['picture']),
    );
  }

  bool _nearExpiry(Session s) {
    final at = s.expiresAt;
    if (at == null) return false;
    return at - _now().millisecondsSinceEpoch ~/ 1000 <= _marginSeconds;
  }

  @override
  Future<String?> freshAccessToken() async {
    final auth = _auth();
    final s = auth.currentSession;
    if (s == null) return null;
    if (_nearExpiry(s)) {
      try {
        await auth.refreshSession();
      } catch (_) {
        // فشل الشبكة لا يمسح الجلسة (سلوك الحزمة الموثَّق أعلاه) — يُعاد
        // الرمز الحالي، والخادم يردّ 401 فيمرّ النقل بمسار forceRefresh.
      }
    }
    return auth.currentSession?.accessToken;
  }

  @override
  Future<String?> forceRefresh() async {
    final auth = _auth();
    if (auth.currentSession == null) return null;
    try {
      final res = await auth.refreshSession();
      return res.session?.accessToken;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // الحزمة تنظّف الجلسة والمخزن المحليين **قبل** نداء الإبطال — ففشل
      // الشبكة بعده لا يهم، والابتلاع هنا يحقق عقد «لا يرمي أبداً».
      await _auth().signOut();
    } catch (_) {/* التنظيف المحلي تم — إبطال الخادم أفضل جهد */}
  }
}
