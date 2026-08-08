/// ============================================================================
///  م87 — الدخول بالبصمة: بديلٌ أسرع للرمز، لا استبدالٌ له
/// ============================================================================
///
///  المبدأ
///  ──────
///  البصمة **بوّابةُ جهازٍ سريعة**، والرمز يبقى المصدر والبديل. فنجاحُ
///  البصمة يرفع القفل مباشرةً، وأيُّ إخفاقٍ أو غيابٍ لها يُبقي إدخال الرمز
///  متاحاً — فلا يُحبَس المستخدم خارج تطبيقه أبداً. هذا الترتيب هو الفرق
///  بين ميزةٍ مريحة وبابِ إحباط.
///
///  لماذا واجهةٌ لا نداءٌ مباشر
///  ───────────────────────────
///  `local_auth` يتطلّب عتاداً وبصمةً مُسجّلة، فلا يُختبَر في بيئة بلا جهاز.
///  فيُعزَل خلف [BiometricAuth]: المنطق حوله (متى تُعرَض، ماذا يحدث عند
///  النجاح/الفشل) يُختبَر بمزيّفٍ في الذاكرة، ويبقى النداءُ الأصيل قشرةً
///  رقيقة في [PlatformBiometricAuth] وحدها — أصغرَ ما يمكن من شيفرةٍ غير
///  مُختبَرة.
library;

import 'package:local_auth/local_auth.dart';

/// عقدُ المصادقة الحيوية — تنفيذٌ للإنتاج ومزيّفٌ للاختبار.
abstract interface class BiometricAuth {
  /// هل يملك الجهاز بصمةً/وجهاً مُسجّلاً وجاهزاً؟
  Future<bool> isAvailable();

  /// يطلب المصادقة ويعيد نجاحها. لا يرمي — أي خطأٍ يعود `false` فيسقط
  /// المستخدمُ إلى الرمز بسلاسة.
  Future<bool> authenticate(String reason);
}

/// تنفيذ الإنتاج فوق `local_auth`. قشرةٌ رقيقة عمداً.
class PlatformBiometricAuth implements BiometricAuth {
  PlatformBiometricAuth([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final can = await _auth.canCheckBiometrics;
      if (!can) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false; // منصّةٌ لا تدعمها ⇒ لا بصمة، والرمز يكفي
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true, // بصمةٌ فقط لا رمز الجهاز — الرمز عندنا داخليّ
        persistAcrossBackgrounding: true, // يصمد عبر انقطاع التطبيق أثناء الطلب
      );
    } catch (_) {
      return false; // إلغاء/إخفاق ⇒ يبقى الرمز متاحاً
    }
  }
}
