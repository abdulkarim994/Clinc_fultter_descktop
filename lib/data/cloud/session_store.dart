/// ============================================================================
///  م88 — مخزن جلسة كلمة المرور: من ملفٍ نصّي إلى مخزن أسرار النظام
/// ============================================================================
///
///  العلة
///  ─────
///  جلسة الدخول بالبريد/كلمة المرور كانت تُكتب نصّاً واضحاً في
///  `{dbDir}/session.json` — ورمزُ التحديث فيها **اعتمادٌ دائم**: من ينسخ
///  الملف يملك الحساب (وثّقت م68 ذلك حرفياً وسدّت مساره الأسهل بتعطيل
///  النسخ الاحتياطي). م88 تشترط: «لا تخزن أي Access/Refresh Token في نص
///  واضح» — فتنتقل الجلسة إلى مخزن أسرار النظام نفسه الذي يحمي مفتاح
///  القاعدة منذ م83 (أندرويد Keystore / ويندوز DPAPI).
///
///  لماذا القراءة **متزامنة** والكتابة «أفضل جهد»
///  ──────────────────────────────────────────────
///  `SupabaseAuthService` يقرأ الجلسة في مُنشئه و`AuthController.build()`
///  يستعيدها متزامناً عند الإقلاع — وسلسلة الإقلاع هذه هي جوهرُ
///  Offline-First: لا انتظارَ شبكةٍ ولا قفلَ واجهة. مخزنُ النظام غير
///  متزامن بطبعه، فيُحمَّل **مرة واحدة قبل `runApp`** (في جسر الإقلاع
///  السحابي) وتُقدَّم قيمتُه من ذاكرةٍ محلية، بينما تجري الكتابات خلفيةً
///  بأفضل جهد — وهي نفس دلالة الكتابة الملفّية السابقة (تُبتلع أخطاؤها).
///
///  الترحيل — ولماذا لا يُحذف الملف إلا بعد نجاح النقل
///  ────────────────────────────────────────────────────
///  عند أول إقلاعٍ بعد التحديث: إن خلا المخزن الآمن ووُجد `session.json`
///  صالح، تُنقل محتوياته ثم يُحذف الملف — فيبقى المستخدم داخلاً **دون
///  إنترنت ودون إعادة دخول**. وإن فشلت الكتابة الآمنة يُترك الملف مكانه:
///  جلسةٌ نصّية عاملة خيرٌ من طرد طبيبٍ أوفلاين من بيانات عيادته. وإن
///  وُجدت نسخةٌ آمنة **و**ملفٌّ قديم معاً، تفوز الآمنة (الأحدث عهداً
///  بالكتابة) ويُمحى النصّي فلا تبقى نسخةُ اعتمادٍ مكشوفة.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../../core/error_log.dart' show recordError;
import 'gotrue_client.dart' show GotrueSession;

/// عقد التخزين الذي تتعامل معه خدمة المصادقة: قراءةٌ متزامنة (من ذاكرة
/// محمَّلة مسبقاً عند الحاجة)، وكتابة/حذف بأفضل جهد — نفس دلالات الملف.
abstract interface class SessionStore {
  String? read();
  void write(String sessionJson);
  void delete();
}

/// السلوك التاريخي حرفياً: `{dbDir}/session.json`. يبقى **افتراضَ**
/// الخدمة كي لا يتغيّر سطرٌ واحد في سلوك الاختبارات القائمة، ويُستبدل في
/// الإقلاع السحابي الحقيقي بالمخزن الآمن أدناه.
class FileSessionStore implements SessionStore {
  FileSessionStore(this.dbDir);

  final String dbDir;

  File get _file => File(p.join(dbDir, 'session.json'));

  @override
  String? read() {
    try {
      return _file.existsSync() ? _file.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String sessionJson) {
    try {
      _file.writeAsStringSync(sessionJson);
    } catch (_) {/* أفضل جهد — كما كان */}
  }

  @override
  void delete() {
    try {
      if (_file.existsSync()) _file.deleteSync();
    } catch (_) {/* أفضل جهد */}
  }
}

/// مفتاح/قيمة غير متزامن — يعزل `flutter_secure_storage` خلف عقدٍ صغير
/// فيُختبَر كلُّ منطق المخزن والترحيل بذاكرةٍ بديلة، ويبقى ملفُ المنصة رقيقاً
/// (نفس فلسفة `DbKeyStore` في م83).
abstract interface class AsyncKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// خيارات المنصة — مطابقة لقرارات م83 (`secure_key_store.dart`):
///   • `resetOnError: false` — خطأ فكٍّ صريح يُبلَّغ خيرٌ من مسحٍ صامت.
///     (الجلسة قابلة لإعادة الجلب بدخولٍ جديد، لكن المسح الصامت = خروجٌ
///     بلا تفسير، ونحن نفضّل الخطأ المرئي في سجل الأعطال.)
///   • `migrateOnAlgorithmChange: true` — تصمد عبر ترقيات الحزمة.
const AndroidOptions _kAndroid = AndroidOptions(
  resetOnError: false,
  migrateOnAlgorithmChange: true,
);
const WindowsOptions _kWindows = WindowsOptions(useBackwardCompatibility: false);
const FlutterSecureStorage _kStorage =
    FlutterSecureStorage(aOptions: _kAndroid, wOptions: _kWindows);

/// التنفيذ الأصيل فوق مخزن أسرار النظام.
class SecureStorageKv implements AsyncKv {
  const SecureStorageKv([this._storage = _kStorage]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// مخزن الجلسة الآمن: قيمةٌ مؤقتة في الذاكرة تُحمَّل قبل `runApp` وتُقدَّم
/// متزامنةً، والكتابات تمضي للمخزن الآمن خلفيةً بأفضل جهد.
class SecureSessionStore implements SessionStore {
  SecureSessionStore._(this._kv, this._cache);

  /// مفتاح النسخة الأولى — أي تغييرٍ مستقبلي في الصيغة يرافقه مفتاحٌ جديد
  /// وترحيلٌ صريح، لا تخمينُ صيغةٍ من قيمة.
  static const storageKey = 'dental.auth.session.v1';

  final AsyncKv _kv;
  String? _cache;

  /// التحميل + الترحيل من `session.json` القديم — مرة واحدة عند الإقلاع.
  static Future<SecureSessionStore> load({
    required AsyncKv kv,
    required String dbDir,
  }) async {
    String? value;
    try {
      value = await kv.read(storageKey);
    } catch (e, st) {
      // فكٌّ متعذّر (عطل Keystore عابر مثلاً): تُسجَّل، ويُتابَع بلا جلسة —
      // أسوأ الاحتمالات إعادةُ دخولٍ واحدة، لا رجوعٌ للتخزين النصّي.
      recordError(e, st, context: 'session-store:read');
      value = null;
    }

    final legacy = File(p.join(dbDir, 'session.json'));
    final legacyExists = legacy.existsSync();

    if (value == null && legacyExists) {
      try {
        final raw = legacy.readAsStringSync();
        // لا يُرحَّل إلا ملفٌ يفكّه محلّل الجلسة فعلاً — القمامة تُتجاهل.
        if (GotrueSession.fromJson(jsonDecode(raw)) != null) {
          await kv.write(storageKey, raw);
          value = raw;
        }
      } catch (e, st) {
        recordError(e, st, context: 'session-store:migrate');
        // فشل النقل ⇒ يبقى الملف كما هو (استمرارية الدخول قبل النظافة).
      }
    }

    // لا تُترك نسخةُ اعتمادٍ نصّية إلا إذا كانت هي المصدر الوحيد العامل.
    if (value != null && legacyExists) {
      try {
        legacy.deleteSync();
      } catch (_) {/* أفضل جهد */}
    }

    return SecureSessionStore._(kv, value);
  }

  @override
  String? read() => _cache;

  @override
  void write(String sessionJson) {
    _cache = sessionJson;
    unawaited(_kv
        .write(storageKey, sessionJson)
        .catchError((Object e, StackTrace st) =>
            recordError(e, st, context: 'session-store:write')));
  }

  @override
  void delete() {
    _cache = null;
    unawaited(_kv.delete(storageKey).catchError((Object e, StackTrace st) =>
        recordError(e, st, context: 'session-store:delete')));
  }
}
