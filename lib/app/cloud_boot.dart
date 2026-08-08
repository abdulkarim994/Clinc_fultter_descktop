/// ============================================================================
///  م88 — غراء الإقلاع السحابي: يجمع المخزن الآمن + الحزمة الرسمية + Google
/// ============================================================================
///
///  لماذا في `app/` — هذا الملف يصل طبقتين لا يجوز أن تستورد إحداهما الأخرى
///  (تنفيذ OAuth في `features/` وجسر الحزمة في `data/`)، ووصلُ الطبقات هو
///  عملُ طبقة التطبيق حصراً (نفس دور `providers.dart`).
///
///  عقد الإخفاق: **التدهور الرشيق لا الانهيار** — التطبيق Offline-First
///  وقيمتُه الأولى فتحُ بيانات العيادة. فشلُ أي خطوة سحابية (مخزن أسرارٍ
///  معطوب، تهيئة حزمة متعذّرة) يُسجَّل ويُتجاوز: يبقى الدخول بكلمة المرور
///  على المحرّك القائم، ويبقى زرّ Google شارحاً أنه غير متاح — ولا شاشة
///  سوداء أبداً.
library;

// ريفربود 3 يصدّر نوع `Override` من `misc.dart` لا من الواجهة الرئيسة.
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/error_log.dart' show recordError;
import '../data/cloud/cloud_config.dart';
import '../data/cloud/session_store.dart';
import '../data/cloud/supabase_boot.dart';
import '../features/auth/supabase_oauth_signin.dart';
import 'providers.dart';

/// يبني تجاوزات المزوّدات السحابية — يُستدعى مرة واحدة قبل `runApp`.
/// وضعٌ محلي (لا إعداد سحابياً) ⇒ قائمة فارغة والسلوك القائم حرفياً.
Future<List<Override>> buildCloudAuthOverrides(String dataDir) async {
  final cfg = loadCloudConfig(dataDir);
  if (cfg == null) return const [];

  final overrides = <Override>[];
  const kv = SecureStorageKv();

  // ١) جلسة كلمة المرور: من النص الواضح إلى مخزن الأسرار (+ ترحيل المرة
  //    الواحدة من session.json). فشله ⇒ يبقى الافتراض الملفّي عاملاً.
  try {
    final store = await SecureSessionStore.load(kv: kv, dbDir: dataDir);
    overrides.add(sessionStoreProvider.overrideWithValue(store));
  } catch (e, st) {
    recordError(e, st, context: 'cloud-boot:session-store');
  }

  // ٢) الحزمة الرسمية: PKCE + تخزين آمن + استعادة جلسة Google (دون شبكة).
  //    نجاحها يفعّل جسر الجلسة وزرّ Google الحقيقي معاً — وفشلها يترك
  //    الافتراضين (لا جسر + «غير مُفعَّل») فلا وعد كاذب.
  try {
    await initSupabaseSdk(cfg: cfg, kv: kv);
    overrides
      ..add(sdkSessionBridgeProvider.overrideWithValue(SupabaseSdkBridge()))
      // م88/ج — تمرير معرّف عميل الويب يفعّل نافذة حسابات الجهاز الأصلية
      // على أندرويد (بلا متصفح)، ويبقى المتصفح سقوطاً رشيقاً.
      ..add(oauthSignInProvider.overrideWithValue(
          SupabaseSdkOAuthSignIn(serverClientId: cfg.googleWebClientId)));
  } catch (e, st) {
    recordError(e, st, context: 'cloud-boot:supabase-sdk');
  }

  return overrides;
}
