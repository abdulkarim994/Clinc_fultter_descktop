/// إعداد الاتصال السحابي — بديل ملف .env في تطبيق Vue:
/// (VITE_SUPABASE_URL / VITE_SUPABASE_KEY / VITE_R2_WORKER).
///
/// مصدران بترتيب أولوية:
///   1) dart-define وقت البناء: SUPABASE_URL / SUPABASE_ANON_KEY / R2_WORKER
///   2) ملف {dbDir}/cloud_config.json وقت التشغيل (يحرَّر من شاشة الإعدادات
///      — يبقى محلياً على الجهاز ولا يدخل إعدادات app.config المتزامنة أبداً)
///
/// غياب url أو anonKey ⇒ الوضع المحلي (خادم مزيف + مصادقة محلية) — وهو وضع
/// الاختبارات كلها. **قرار أمني قائم: لا نلمس مشروع الإنتاج الأصلي؛ الدليل
/// SETUP_SUPABASE_AR.md يشرح إنشاء مشروع جديد وتدوير المفاتيح.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../sync/feature_flags.dart' show syncFlags;

class CloudConfig {
  const CloudConfig({
    required this.supabaseUrl,
    required this.anonKey,
    this.r2WorkerUrl = '',
    this.googleWebClientId = '',
  });

  final String supabaseUrl;
  final String anonKey;
  final String r2WorkerUrl;

  /// م88/ج — معرّف عميل **الويب** من Google Cloud (عامٌّ بطبعه، يُشحن مع
  /// التطبيق كمفتاح anon سواء). وجودُه يفعّل الدخول الأصلي داخل التطبيق
  /// (نافذة حسابات الجهاز، بلا متصفح): يُمرَّر `serverClientId` لحزمة
  /// google_sign_in فيأتي idToken بجمهور (aud) يطابق عميلَ Google المضبوط
  /// في Supabase — فيقبله `signInWithIdToken` بلا أي تغيير في الخادم.
  /// غيابه = مسار المتصفح (PKCE) وحده، كما قبل هذه الإضافة حرفياً.
  final String googleWebClientId;

  bool get hasSync => supabaseUrl.isNotEmpty && anonKey.isNotEmpty;
  bool get hasImages => r2WorkerUrl.isNotEmpty;

  Map<String, Object?> toJson() => {
        'supabaseUrl': supabaseUrl,
        'anonKey': anonKey,
        'r2WorkerUrl': r2WorkerUrl,
        'googleWebClientId': googleWebClientId,
      };

  static CloudConfig fromJson(Map<String, Object?> j) => CloudConfig(
        supabaseUrl: '${j['supabaseUrl'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), ''),
        anonKey: '${j['anonKey'] ?? ''}'.trim(),
        r2WorkerUrl:
            '${j['r2WorkerUrl'] ?? ''}'.trim().replaceAll(RegExp(r'/+$'), ''),
        googleWebClientId: '${j['googleWebClientId'] ?? ''}'.trim(),
      );
}

const _defineUrl = String.fromEnvironment('SUPABASE_URL');
const _defineKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _defineWorker = String.fromEnvironment('R2_WORKER');
const _defineGoogleWebClientId =
    String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
const _definePhoneIdentity = String.fromEnvironment('PHONE_IDENTITY');
const _defineColdFetch = String.fromEnvironment('COLD_FETCH');

/// توأم أعلام بيئة البناء في الأصل (VITE_PHONE_IDENTITY/VITE_COLD_FETCH
/// في .env.production): تُطبَّق مرة عند الإقلاع قبل بناء التطبيق —
/// **مطابقة إلزامية مع الخلفية الإنتاجية**: بياناتها كُتبت بهذه الأعلام
/// (مفاتيح هوية المرضى p:هاتف:اسم)، فتشغيل العميل بغيرها يفصم الهوية.
/// الاختبارات لا تمرر تعريفات ⇒ تبقى الافتراضات المحلية (خادم مزيف).
void applyBuildTimeFlags({
  String phoneIdentity = _definePhoneIdentity,
  String coldFetch = _defineColdFetch,
}) {
  bool truthy(String v) =>
      v == '1' || v.toLowerCase() == 'true' || v.toLowerCase() == 'on';
  if (truthy(phoneIdentity)) syncFlags.phoneIdentity = true;
  if (truthy(coldFetch)) syncFlags.coldFetch = true;
}

File cloudConfigFile(String dbDir) => File(p.join(dbDir, 'cloud_config.json'));

/// يقرأ الإعداد: dart-define أولاً ثم الملف؛ null = وضع محلي.
CloudConfig? loadCloudConfig(String dbDir) {
  if (_defineUrl.isNotEmpty && _defineKey.isNotEmpty) {
    return CloudConfig(
      supabaseUrl: _defineUrl.replaceAll(RegExp(r'/+$'), ''),
      anonKey: _defineKey,
      r2WorkerUrl: _defineWorker.replaceAll(RegExp(r'/+$'), ''),
      googleWebClientId: _defineGoogleWebClientId.trim(),
    );
  }
  final f = cloudConfigFile(dbDir);
  if (!f.existsSync()) return null;
  try {
    final cfg = CloudConfig.fromJson(
        Map<String, Object?>.from(jsonDecode(f.readAsStringSync()) as Map));
    return cfg.hasSync ? cfg : null;
  } catch (_) {
    return null;
  }
}

void saveCloudConfig(String dbDir, CloudConfig? cfg) {
  final f = cloudConfigFile(dbDir);
  if (cfg == null || !cfg.hasSync) {
    if (f.existsSync()) f.deleteSync();
    return;
  }
  f.writeAsStringSync(jsonEncode(cfg.toJson()));
}
