/// ============================================================================
///  م93 — إدارة الحساب: كلمة المرور وحذف الحساب الحقيقي
/// ============================================================================
///
///  يعزل منطقَ الحساب السحابي خلف عقدٍ صغير قابلٍ للحقن، فتُختبَر كلُّ
///  القرارات (تعيين مقابل إعادة تعيين، التحقق من القديمة، ترتيب الحذف)
///  بمزيّفاتٍ بلا شبكة — تماماً كعزل OAuth (م88) وBiometric (م87).
///
///  الحدّ المعماري (صريحٌ في التوثيق)
///  ─────────────────────────────────
///  كلمة المرور خدمةٌ ذاتية عبر GoTrue بمفتاح anon + رمز الجلسة. أما حذف
///  صفّ auth.users فيحتاج دالة `delete_my_account` (SECURITY DEFINER،
///  مهاجرة 0031). قبل تطبيقها يرمي الخادم [AccountRpcMissing] فيُجهض
///  الحذف **بنظافة** بلا مسٍّ محليّ أو R2 — لا حالة نصف محذوفة.
library;

import '../../data/cloud/gotrue_client.dart';

/// نوع المُصادقة على الحساب الحالي — يقود واجهة كلمة المرور.
enum AccountPasswordState {
  /// للحساب كلمةُ مرورٍ قائمة (هوية email): التغيير «إعادة تعيين» تشترط
  /// القديمة.
  hasPassword,

  /// لا كلمةَ مرور (Google وحده): «تعيين» أول مرة بلا قديمة.
  noPassword,

  /// تعذّر تحديد الحالة (أوفلاين مثلاً) — الواجهة تعرض إعادةَ المحاولة.
  unknown,
}

/// مقابس الحساب — تُمرَّر من طبقة المزوّدات، وتُزيَّف في الاختبار.
///
///   • [client]     عميل GoTrue (نداءات الخادم).
///   • [accessToken] رمزُ وصولٍ صالح (يجدّده مزوّد المصادقة عند اللزوم؛
///                   يعمل لمستخدمي البريد وGoogle معاً عبر الجسر).
///   • [email]      بريد الحساب الحالي (لإعادة المصادقة عند تغيير الكلمة).
///   • [purgeImages] تطهير كائنات R2 المحلية المعروفة (أفضل جهد) — يُمرَّر
///                   من طبقة الأشعة، ويُترك فارغاً حين لا صور.
///   • [wipeLocal]  مسحُ كل بيانات الحساب محلياً + إنهاء الجلسة (يُعاد
///                   استخدام مسار مسح تبديل الحساب القائم).
class AccountAdmin {
  AccountAdmin({
    required this.client,
    required this.accessToken,
    required this.email,
    required this.purgeImages,
    required this.wipeLocal,
  });

  final GotrueClient client;
  final Future<String?> Function() accessToken;
  final String email;
  final Future<void> Function() purgeImages;
  final Future<void> Function() wipeLocal;

  Future<String> _requireToken() async {
    final t = await accessToken();
    if (t == null || t.isEmpty) {
      throw AuthException('انتهت الجلسة — سجّل الدخول من جديد');
    }
    return t;
  }

  /// هل للحساب كلمةُ مرورٍ قائمة؟ (يحدّد «تعيين» مقابل «إعادة تعيين»).
  Future<AccountPasswordState> passwordState() async {
    try {
      final providers = await client.userProviders(await _requireToken());
      return providers.contains('email')
          ? AccountPasswordState.hasPassword
          : AccountPasswordState.noPassword;
    } catch (_) {
      return AccountPasswordState.unknown;
    }
  }

  /// تعيينٌ أول مرة (Google بلا كلمة مرور): لا قديمةَ تُشترط — الجلسة
  /// نفسها إثباتُ الهوية.
  Future<void> setPassword(String newPassword) async {
    final err = _validateNew(newPassword);
    if (err != null) throw AuthException(err);
    await client.updatePassword(await _requireToken(), newPassword);
  }

  /// إعادة تعيينٍ لحسابٍ له كلمة مرور: تُشترط **القديمة** — نتحقق منها
  /// بإعادة مصادقةٍ حقيقية (signInWithPassword) قبل التحديث، فلا تُغيَّر
  /// كلمةُ مرورِ جلسةٍ مسروقةٍ بلا معرفة الحالية.
  Future<void> resetPassword(
      {required String oldPassword, required String newPassword}) async {
    final err = _validateNew(newPassword);
    if (err != null) throw AuthException(err);
    try {
      await client.signInWithPassword(email.trim(), oldPassword);
    } catch (_) {
      // لا نُفشي تفاصيل: أي فشلٍ هنا = القديمة غير صحيحة.
      throw AuthException('كلمة المرور القديمة غير صحيحة');
    }
    await client.updatePassword(await _requireToken(), newPassword);
  }

  String? _validateNew(String pw) {
    if (pw.trim().length < 8) return 'كلمة المرور الجديدة 8 أحرف على الأقل';
    return null;
  }

  /// حذف الحساب الحقيقي — الترتيب مقصود:
  ///   ١) الخادم أولاً (RPC): إن لم يُنجح فلا شيء يُمسّ محلياً ولا في R2.
  ///      غيابُ الدالة (0031 غير مطبَّقة) يرمي [AccountRpcMissing] فوق.
  ///   ٢) تطهير R2 (أفضل جهد): الرمز يبقى صالح التوقيع بعد حذف المستخدم
  ///      حتى انتهائه، فيقبله عامل R2. فشلُه لا يُفشل الحذف — الحساب زال.
  ///   ٣) مسحٌ محليّ كامل + خروج.
  Future<void> deleteAccount() async {
    await client.deleteMyAccount(await _requireToken());
    try {
      await purgeImages();
    } catch (_) {/* أفضل جهد — الحساب زال من المصدر */}
    await wipeLocal();
  }
}
