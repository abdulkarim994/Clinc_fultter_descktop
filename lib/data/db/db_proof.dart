/// ============================================================================
///  Milestone-0 proof harness
/// ============================================================================
///
///  One callable that exercises every Go/No-Go check of the milestone against
///  a real SQLite file, and reports the outcome. Used by BOTH the proof screen
///  (visible evidence inside the app) and the automated test-suite.
///
///  Checks:
///    1. database file created + opened via the verbatim bootstrap pipeline
///    2. all 13 relational tables exist
///    3. FTS5 virtual table + triggers exist (Arabic patient-name search)
///    4. Arabic CRUD round-trip
///    5. FTS prefix search finds a patient via the normalised query
///    6. SQL-vs-Dart normalisation parity (names) — the cross-codebase pledge
///    7. SQL-vs-Dart phone canonicalisation parity
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/ar_normalize.dart';
import 'bootstrap.dart';
import 'db_encrypt.dart' show classifyDb, DbFileState;
import 'schema_sql.dart';

class DbProofReport {
  const DbProofReport({
    required this.tables,
    required this.ftsOk,
    required this.crudOk,
    required this.ftsSearchOk,
    required this.arParityOk,
    required this.phoneParityOk,
    required this.sqliteVersion,
    required this.userVersion,
    required this.migrationFlags,
    required this.warnings,
  });

  final List<String> tables;
  final bool ftsOk;
  final bool crudOk;
  final bool ftsSearchOk;
  final bool arParityOk;
  final bool phoneParityOk;
  final String sqliteVersion;
  final int userVersion;
  final List<String> migrationFlags;
  final List<String> warnings;

  int get relationalTableCount => expectedTables.where(tables.contains).length;

  // م133 — المقام المتوقَّع للعرض: طول قائمة الجداول المتوقَّعة نفسها.
  // كان مكتوباً «13» نصاً في شاشة الإثبات، فلمّا نما المخطط (employees
  // وexpenses ⇒ 15) صار يعرض «15/13» مع أن schemaOk صحيح — رقمٌ يناقض
  // نفسه. ربطُه بالمصدر يمنع تكرار ذلك عند أي جدولٍ لاحق.
  int get expectedTableCount => expectedTables.length;

  bool get schemaOk => relationalTableCount == expectedTables.length;

  bool get allOk =>
      schemaOk && ftsOk && crudOk && ftsSearchOk && arParityOk && phoneParityOk;
}

/// Name-normalisation parity samples (hamza forms, tashkeel, taa marbuta,
/// alef maqsura — the exact traps the normaliser exists for).
const List<String> nameParitySamples = [
  'أَحْمَد إِبْراهيم',
  'فاطمة الزّهراء',
  'مصطفى',
  'مُؤمِن آل هُدى',
  'إسْراء عبد الرّحمن',
];

/// Phone parity samples — realistic inputs per the documented contract
/// (digits + common separators, Arabic-Indic digits, 00/218/trunk-0 prefixes).
const List<String> phoneParitySamples = [
  '+218 91-234 5678',
  '00218912345678',
  '٠٩١٢٣٤٥٦٧٨',
  '(091) 234.567/8',
  '218912345678',
];

/// Run the full Milestone-0 proof against `<dirPath>/<dbName>.db`.
DbProofReport runDbProof(String dirPath) {
  Directory(dirPath).createSync(recursive: true);

  // م83 — حارس: هذه الأداة تفتح القاعدة **بلا مفتاح** وتكتب فيها. وهي
  // اليوم غير موصولة بشاشة (مسار ProofScreen غير مسجَّل) وتعمل على مجلد
  // مؤقّت، لكن توجيهها يوماً إلى مجلد البيانات الحقيقي يعني — على قاعدة
  // مشفَّرة — انهياراً غامضاً، أو أسوأ: إنشاء قاعدة سادة ثانية بجوارها.
  // الرفض الصريح أرخص من اكتشاف ذلك في الميدان.
  final target = p.join(dirPath, '$dbName.db');
  if (classifyDb(target) == DbFileState.encrypted) {
    throw StateError(
      'أداة الإثبات تفتح القاعدة بلا مفتاح، والقاعدة في «$dirPath» مشفَّرة. '
      'شغّلها على مجلد فارغ أو مؤقّت لا على مجلد بيانات العيادة.',
    );
  }

  final warnings = <String>[];
  final db = openBootstrappedDb(
    p.join(dirPath, '$dbName.db'),
    warn: warnings.add,
  );
  try {
    // 2. tables
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map((r) => r['name'] as String)
        .toList();

    // 3. FTS artefacts
    final ftsOk =
        tables.contains('patients_fts') &&
        db
                .select(
                  "SELECT name FROM sqlite_master WHERE type='trigger' "
                  "AND name IN ('patients_fts_ai','patients_fts_au','patients_fts_ad')",
                )
                .length ==
            3;

    // 4. Arabic CRUD round-trip
    db.execute(
      'INSERT OR REPLACE INTO patients(id, name, phone) VALUES (?, ?, ?)',
      ['m0-proof', 'أحمد الطيّب', '+218 91-234 5678'],
    );
    final row = db.select('SELECT name FROM patients WHERE id = ?', [
      'm0-proof',
    ]);
    final crudOk = row.isNotEmpty && row.first['name'] == 'أحمد الطيّب';

    // 5. FTS prefix search via the Dart-side normalised query
    var ftsSearchOk = false;
    if (ftsOk) {
      final q = arNorm('أحمد'); // → احمد
      final hits = db.select(
        'SELECT pid FROM patients_fts WHERE norm MATCH ?',
        ['$q*'],
      );
      ftsSearchOk = hits.any((r) => r['pid'] == 'm0-proof');
    }

    // 6. SQL-vs-Dart name normalisation parity
    var arParityOk = true;
    for (final s in nameParitySamples) {
      final sqlV =
          db.select("SELECT ${arNormSql("'$s'")} AS v").first['v'] as String;
      if (sqlV != arNorm(s)) {
        arParityOk = false;
        warnings.add(
          'name parity mismatch: "$s" sql="$sqlV" dart="${arNorm(s)}"',
        );
      }
    }

    // 7. SQL-vs-Dart phone canonicalisation parity
    var phoneParityOk = true;
    for (final s in phoneParitySamples) {
      final sqlV =
          db.select("SELECT ${arNormPhoneSql("'$s'")} AS v").first['v']
              as String;
      if (sqlV != normPhone(s)) {
        phoneParityOk = false;
        warnings.add(
          'phone parity mismatch: "$s" sql="$sqlV" dart="${normPhone(s)}"',
        );
      }
    }

    final sqliteVersion =
        db.select('SELECT sqlite_version() AS v').first['v'] as String;
    final userVersion =
        db.select('PRAGMA user_version').first.values.first as int;
    final flags = db
        .select('SELECT key FROM metadata ORDER BY key')
        .map((r) => r['key'] as String)
        .toList();

    return DbProofReport(
      tables: tables,
      ftsOk: ftsOk,
      crudOk: crudOk,
      ftsSearchOk: ftsSearchOk,
      arParityOk: arParityOk,
      phoneParityOk: phoneParityOk,
      sqliteVersion: sqliteVersion,
      userVersion: userVersion,
      migrationFlags: flags,
      warnings: warnings,
    );
  } finally {
    db.close();
  }
}
