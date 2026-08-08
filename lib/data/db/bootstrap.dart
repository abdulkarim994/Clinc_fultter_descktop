/// ============================================================================
///  Database bootstrap — mirrors the desktop sqlite-core.js init flow
/// ============================================================================
///
///  The Vue desktop core initialises better-sqlite3 synchronously:
///  create-if-missing → base DDL → shared migrations → ready. `package:sqlite3`
///  is also synchronous, so this file is a faithful structural mirror:
///
///    openBootstrappedDb(path) →  sqlite3.open → [schemaSql] → runMigrations()
///
///  The resulting file is byte-compatible with a database produced by the
///  existing app (same DDL strings, same migration pipeline, same
///  `PRAGMA user_version`), which is what enables:
///    • direct adoption of an existing clinic database file, and
///    • the Vue and Flutter apps running side-by-side during rollout.
library;

import 'package:sqlite3/sqlite3.dart';

import 'migrations.dart';
import 'db_key.dart' show pragmaKeyLiteral;
import 'schema_sql.dart';

/// [MigrationDb] shim over a raw `package:sqlite3` handle — the Dart twin of
/// the better-sqlite3 shim the desktop adapter injects into migrations.js.
class SqliteMigrationShim implements MigrationDb {
  SqliteMigrationShim(this.db);

  final Database db;

  @override
  void exec(String sql) => db.execute(sql);

  @override
  bool flagExists(String key) {
    final rows = db.select('SELECT 1 FROM metadata WHERE key = ?', [key]);
    return rows.isNotEmpty;
  }

  @override
  void setFlag(String key) => db.execute(
      "INSERT OR REPLACE INTO metadata(key, value) VALUES (?, '1')", [key]);
}

/// Apply base schema + all shared migrations to an open handle. Idempotent —
/// safe to run on a brand-new file AND on an existing clinic database.
({bool syncColsPromoted}) bootstrapSchema(
  Database db, {
  bool phoneIdentityEnabled = false,
  void Function(String message)? warn,
}) {
  db.execute(schemaSql);
  final result = runMigrations(
    SqliteMigrationShim(db),
    phoneIdentityEnabled: phoneIdentityEnabled,
    warn: warn,
  );
  db.execute('PRAGMA user_version = $dbVersion');
  return result;
}

/// Open (creating if missing) and fully bootstrap the database at [path].
Database openBootstrappedDb(
  String path, {
  bool phoneIdentityEnabled = false,
  void Function(String message)? warn,
  /// م83 — مفتاح التشفير بصيغة hex. تمريره يفتح القاعدة عبر SQLCipher؛
  /// وغيابه يُبقي السلوك السادّ **حرفياً** كما كان.
  ///
  /// الترتيب هنا غير قابل للتبديل: `PRAGMA key` **أول أمر بعد الفتح**،
  /// قبل `journal_mode` وقبل أي قراءة. أي أمر يسبقه يُنفَّذ على قاعدة
  /// لم تُفكّ بعد فيفشل — وهي أشهر زلّة في دمج SQLCipher.
  String? encryptionKey,
}) {
  final db = sqlite3.open(path);
  if (encryptionKey != null && encryptionKey.isNotEmpty) {
    // ⚠ الحارس قبل المفتاح لا بعده — وهذا أهم سطر في ملف التشفير كله.
    //
    //  SQLite العادية **تتجاهل البراغما المجهولة صامتةً**: لا خطأ ولا
    //  تحذير. فلو شُحنت مكتبة بلا SQLCipher — إعدادُ بناء خاطئ، أو
    //  `source: system` يلتقط sqlite3.dll الخاصة بويندوز — لمضى التطبيق
    //  يكتب أسماء المرضى وهواتفهم **نصّاً مقروءاً** وهو موقنٌ أنه يشفّر،
    //  وكل اختباراتنا تمرّ لأنها تُشغَّل على بيئة صحيحة. عطلٌ صامت في
    //  إعداد البناء يتحوّل إلى تسريب بيانات صحية.
    //
    //  `PRAGMA cipher_version` هو الفارق القاطع: SQLCipher يعيد نصّ
    //  إصداره، والعادية تعيد **صفر صفوف**. فالفحص هنا يحوّل خطأً صامتاً
    //  إلى إخفاق إقلاع صريح — والإخفاق أرحم من التسريب بما لا يقاس.
    final cipher = db.select('PRAGMA cipher_version');
    if (cipher.isEmpty) {
      try {
        db.close();
      } catch (_) {}
      throw StateError(
        'طُلب تشفير القاعدة لكن مكتبة SQLite المحمَّلة لا تدعم SQLCipher '
        '(PRAGMA cipher_version بلا نتيجة). التطبيق يتوقف عمداً بدل كتابة '
        'بيانات المرضى نصّاً مقروءاً. تحقّق من hooks.user_defines.sqlite3 '
        'في pubspec.yaml — يجب أن يكون source: sqlcipher.',
      );
    }
    db.execute('PRAGMA key = ${pragmaKeyLiteral(encryptionKey)};');
  }
  // ما بعد الفتح داخل حماية: مفتاحٌ خاطئ يُفشل أول أمر يقرأ الصفحات،
  // وبلا هذا يبقى مقبضٌ أصيل مفتوحاً عند كل محاولة — وعلى ويندوز يُبقي
  // ملف القاعدة مقفولاً فتفشل حتى محاولة الإصلاح التالية.
  try {
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    bootstrapSchema(
      db,
      phoneIdentityEnabled: phoneIdentityEnabled,
      warn: warn,
    );
  } catch (_) {
    try {
      db.close();
    } catch (_) {}
    rethrow;
  }
  return db;
}
