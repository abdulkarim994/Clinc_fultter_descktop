/// ============================================================================
///  م88 — جسر تسجيل الدخول بمزوّد خارجي (Google) عبر Supabase Auth
/// ============================================================================
///
///  لماذا مزوّدٌ مستقل لا توسيعٌ لـ`AuthService`
///  ────────────────────────────────────────────
///  `AuthService` عقدُ بريدٍ/كلمة مرور له منفّذان (محلّي وSupabase). ودخول
///  Google مختلفٌ جوهرياً: لا كلمةَ مرور، بل دورةُ OAuth بـPKCE عبر
///  المتصفّح. فوضعُه في عقدٍ مستقل يُبقي المنفّذَين القائمَين بلا تغيير،
///  ويعزل الجزءَ الذي يحتاج عتاداً/متصفّحاً حقيقياً (فلا يُختبَر في الصندوق)
///  خلف واجهةٍ تُزيَّف بالكامل — فيُختبَر كلُّ المنطق حولها.
///
///  حالة اليوم
///  ──────────
///  التنفيذ الحقيقي (فوق `supabase_flutter` الرسمي بـPKCE) يُوصَل حين تجهز
///  اعتمادات Google Cloud ويُضبَط مزوّد Google في Supabase — وهي خطوةٌ
///  تحتاج حساب المالك وجهازاً حقيقياً للتحقّق. حتى ذلك الحين الافتراض
///  [OAuthNotConfigured]: الزرُّ موجودٌ ويشرح بوضوح أنه بانتظار الإعداد،
///  فلا وعدٌ كاذبٌ ولا انهيار.
library;

/// نتيجةُ دخولٍ ناجح بمزوّد خارجي — ما يحتاجه التطبيق لبناء الجلسة.
class OAuthResult {
  const OAuthResult({
    required this.uid,
    required this.email,
    this.displayName,
    this.avatarUrl,
  });

  final String uid;
  final String email;

  /// الاسم المعروض من المزوّد (Google: `full_name`) — لرسالة الترحيب.
  final String? displayName;
  final String? avatarUrl;
}

/// تُرمى حين يُطلَب دخول Google قبل اكتمال إعداده — رسالةٌ عربية صريحة.
class OAuthUnavailable implements Exception {
  const OAuthUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class OAuthSignIn {
  /// يفتح دورة Google (PKCE) ويعيد الهوية عند النجاح. يرمي
  /// [OAuthUnavailable] إن لم يكن الإعداد جاهزاً، وأي استثناءٍ آخر عند
  /// إلغاء المستخدم أو فشل الشبكة — والمتّصِلُ يترجمها لرسالةٍ لطيفة.
  Future<OAuthResult> signInWithGoogle();
}

/// الافتراض قبل وصول الاعتمادات: يشرح بدل أن يَعِد أو ينهار.
class OAuthNotConfigured implements OAuthSignIn {
  const OAuthNotConfigured();
  @override
  Future<OAuthResult> signInWithGoogle() async => throw const OAuthUnavailable(
        'الدخول بحساب Google لم يُفعَّل بعد على هذا الإصدار. '
        'يحتاج ضبطَ مزوّد Google في الخادم — سيتوفّر في التحديث القادم.',
      );
}
