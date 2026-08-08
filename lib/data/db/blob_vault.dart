/// ============================================================================
///  م83 — خزنة الملفّات الثنائية: صور الأشعة لا تبقى خارج التشفير
/// ============================================================================
///
///  الثغرة التي يسدّها هذا الملف
///  ────────────────────────────
///  تشفيرُ القاعدة يحمي `dental_clinic_offline.db` وحده. وصورُ الأشعة كانت
///  تُكتب ملفات `.jpg` **سادة** في `{dbDir}/xray_images/`، واسمُ الملف نفسه
///  مشتقٌّ من مفتاح فيه اسم المريض. فالنتيجة أن قرصاً مسروقاً يعطي:
///  الأشعة كاملةً، مربوطةً بأسماء أصحابها، بلا فتح شيء.
///
///  وأشعّةُ مريض بيانٌ صحي بكل معنى — أخطر من صفٍّ في جدول. فادّعاء
///  «التشفير عند السكون» مع تركها كذلك ادّعاءٌ ناقص، وهذا النقص يسقط في
///  أول تدقيق جدّي.
///
///  لماذا SQLCipher لا تشفيرٌ بأيدينا
///  ─────────────────────────────────
///  البديل الظاهر: تشفير بايتات كل ملف بـAES-GCM. ويعني ذلك حزمةَ تعمية
///  جديدة، وإدارةَ متجهات تهيئة، وترتيبَ وسوم مصادقة — أي **تعمية مكتوبة
///  يدوياً** في منتج طبي. والمسار المُثبَت موجود أصلاً: تُحفظ البايتات
///  صفوفاً في قاعدة SQLCipher ثانية بالمفتاح نفسه. لا سطر تعمية جديد،
///  ونفسُ الضمانات التي تحرس القاعدة الرئيسة.
///
///  ولماذا ملفُ قاعدة **منفصل** لا جدولٌ في الرئيسة
///  ───────────────────────────────────────────────
///  الرئيسة تمرّ بالمزامنة والأرشفة والضغط والترحيل، وكلها تكبر بحجمها.
///  إقحامُ ميغابايتات من الصور فيها يُبطئ كل ذلك بلا مقابل — والصور لا
///  تتزامن عبر هذا المسار أصلاً (لها R2). فالفصل يُبقي الرئيسة رشيقة.
///
///  التوافق أولاً
///  ─────────────
///  بلا مفتاح ⇒ [PlainFileVault]: **السلوك القديم حرفياً**، ملفات في
///  المجلد نفسه بالأسماء نفسها. الاختبارات القائمة كلها تمرّ بلا تعديل،
///  ووضعُ التطوير `DB_PLAINTEXT` يعمل كما كان.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'db_key.dart';

/// عقدٌ بالبايتات لا بالمسارات — وهذا ما جعل التبديل ممكناً بلا لمس
/// مستهلك واحد: `XrayStore` لم يكن يُسرّب `File` خارج حدوده أصلاً.
abstract interface class BlobVault {
  Uint8List? read(String name);
  void write(String name, Uint8List bytes);
  void delete(String name);
  bool exists(String name);
  void close();
}

/// السلوك السابق: ملفٌّ لكل صورة. يبقى للاختبارات ولوضع النص الصريح.
class PlainFileVault implements BlobVault {
  PlainFileVault(this.dir);

  final String dir;

  File _f(String name) => File(p.join(dir, name));

  @override
  bool exists(String name) => _f(name).existsSync();

  @override
  Uint8List? read(String name) {
    final f = _f(name);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  @override
  void write(String name, Uint8List bytes) {
    Directory(dir).createSync(recursive: true);
    _f(name).writeAsBytesSync(bytes);
  }

  @override
  void delete(String name) {
    final f = _f(name);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  void close() {}
}

/// سجلُّ الخزنات المفتوحة — لإغلاقها من خارج شجرة المزوّدات.
///
/// ولماذا سجلٌّ لا إبطالُ مزوّد: `xrayStoreProvider` يراقب `authProvider`،
/// فإبطالُه من داخل `AuthController` دورةُ اعتماد يرفضها Riverpod صراحةً
/// (رُصد: خمسة اختبارات سقطت بـ`CircularDependencyError`). ومسحُ الصور
/// عند تبديل الحساب يحتاج إغلاق المقبض أولاً — على ويندوز لا يُحذف ملف
/// مفتوح — فالسجلّ يفصل الحاجتين: إغلاقٌ بالمسار، بلا لمس المزوّدات.
final Set<EncryptedBlobVault> _openVaults = <EncryptedBlobVault>{};

/// يُغلق كل خزنة مفتوحة على [dir]. عمليةٌ آمنة التكرار: الخزنة تعيد الفتح
/// كسولاً عند أول استعمال تالٍ.
void closeVaultsIn(String dir) {
  for (final v in _openVaults.where((v) => v.dir == dir).toList()) {
    v.close();
  }
}

/// خزنة مشفَّرة: قاعدة SQLCipher ثانية بمفتاح القاعدة الرئيسة نفسه.
///
/// المقبض يُفتح كسولاً عند أول استعمال ويبقى مفتوحاً — فتحُ القاعدة لكل
/// مصغّرة في معرض من خمسين صورة يضاعف زمن العرض بلا داعٍ.
class EncryptedBlobVault implements BlobVault {
  EncryptedBlobVault({required this.dir, required this.hexKey});

  static const String fileName = 'xray_vault.db';

  final String dir;
  final String hexKey;

  Database? _db;

  Database get _handle {
    final open = _db;
    if (open != null) return open;

    Directory(dir).createSync(recursive: true);
    final db = sqlite3.open(p.join(dir, fileName));
    // كل ما بعد الفتح داخل حماية تُغلق المقبض قبل إعادة الرمي.
    //
    // كان الإسناد إلى `_db` آخر سطر، فأيّ إخفاق قبله — مفتاح خاطئ أشهرها —
    // يترك مقبضاً أصيلاً بلا مرجع لا يُغلقه حتى `close()`. ومعرضُ صور
    // يعيد المحاولة عند كل بناء يسرّب واحداً في كل مرة بلا سقف، وعلى
    // ويندوز يُبقي كلٌّ منها الملفَّ مقفولاً. (قِيس: 10 من 10 تسرّبت.)
    try {
      // الترتيب نفسه المفروض في القاعدة الرئيسة: التحقق ثم المفتاح.
      if (db.select('PRAGMA cipher_version').isEmpty) {
        throw StateError(
          'خزنة الأشعة تتطلّب SQLCipher والمكتبة المحمَّلة لا تدعمه — '
          'أُوقفت الكتابة بدل حفظ صور المرضى بلا تشفير.',
        );
      }
      db.execute('PRAGMA key = ${pragmaKeyLiteral(hexKey)};');
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute(
        'CREATE TABLE IF NOT EXISTS blobs('
        'name TEXT PRIMARY KEY, bytes BLOB NOT NULL, saved_at INTEGER)',
      );
    } catch (_) {
      try {
        db.close();
      } catch (_) {}
      rethrow;
    }
    _openVaults.add(this);
    return _db = db;
  }

  @override
  bool exists(String name) =>
      _handle.select('SELECT 1 FROM blobs WHERE name = ?', [name]).isNotEmpty;

  @override
  Uint8List? read(String name) {
    final r = _handle.select('SELECT bytes FROM blobs WHERE name = ?', [name]);
    if (r.isEmpty) return null;
    final v = r.first['bytes'];
    return v is Uint8List ? v : Uint8List.fromList(v as List<int>);
  }

  @override
  void write(String name, Uint8List bytes) => _handle.execute(
        'INSERT OR REPLACE INTO blobs(name, bytes, saved_at) VALUES (?,?,?)',
        [name, bytes, DateTime.now().millisecondsSinceEpoch],
      );

  @override
  void delete(String name) =>
      _handle.execute('DELETE FROM blobs WHERE name = ?', [name]);

  @override
  void close() {
    _db?.close();
    _db = null;
    _openVaults.remove(this);
  }
}

class VaultMigrationResult {
  const VaultMigrationResult({
    required this.moved,
    required this.failed,
    required this.reason,
  });

  final int moved;
  final int failed;
  final String reason;
}

/// ينقل صور الأشعة السادة القائمة إلى الخزنة المشفَّرة مرّة واحدة.
///
/// الترتيب لكل ملف: **اكتب، ثم تحقّق بالقراءة، ثم احذف السادّ.** وحذفٌ قبل
/// التحقق يفقد الصورة عند أي إخفاق. وما يُخفق يبقى ملفاً سادّاً ويُحصى في
/// [VaultMigrationResult.failed] — ولا يُحذف شيء لم يصل.
VaultMigrationResult migratePlainImagesIntoVault({
  required String imagesDir,
  required BlobVault vault,
}) {
  final dir = Directory(imagesDir);
  if (!dir.existsSync()) {
    return const VaultMigrationResult(
        moved: 0, failed: 0, reason: 'لا صور سابقة');
  }

  var moved = 0;
  var failed = 0;
  for (final e in dir.listSync().whereType<File>()) {
    final name = p.basename(e.path);
    if (!name.endsWith('.jpg')) continue;
    try {
      final bytes = e.readAsBytesSync();
      vault.write(name, bytes);
      // مقارنةُ بايتاتٍ لا أطوال: تلفٌ يحفظ الطول (بتّة مقلوبة، كتابة
      // جزئية بحجم مطابق) كان يمرّ ثم يُحذف الأصل السليم.
      final back = vault.read(name);
      if (back == null || !_sameBytes(back, bytes)) {
        failed++;
        continue; // السادّ يبقى — أفضل من صورة ضائعة
      }
      e.deleteSync();
      moved++;
    } catch (_) {
      failed++;
    }
  }
  return VaultMigrationResult(
    moved: moved,
    failed: failed,
    reason: 'نُقلت $moved صورة، وأخفقت $failed',
  );
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
