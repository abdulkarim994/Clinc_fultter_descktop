/// ============================================================================
///  Drift application database — typed access over the verbatim schema
/// ============================================================================
///
///  Division of responsibility (mirrors the Vue architecture):
///    • bootstrap.dart owns ALL DDL — verbatim schema + shared migrations,
///      exactly like sqlite-core.js on desktop.
///    • drift owns typed, reactive queries for the app layer (this file).
///
///  Drift is deliberately prevented from generating or migrating schema:
///  `user_version` is set to [dbVersion] by the bootstrap, matching
///  [schemaVersion], so `onCreate`/`onUpgrade` never fire.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'bootstrap.dart';
import 'schema_sql.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Patients])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Open the clinic database inside [dirPath]: run the verbatim
  /// bootstrap/migration pipeline first (synchronous, better-sqlite3 style),
  /// then hand the same file to drift for typed access.
  factory AppDatabase.openAt(
    String dirPath, {
    bool phoneIdentityEnabled = false,
  }) {
    final file = File(p.join(dirPath, '$dbName.db'));
    file.parent.createSync(recursive: true);
    final raw = openBootstrappedDb(
      file.path,
      phoneIdentityEnabled: phoneIdentityEnabled,
    );
    raw.close();
    return AppDatabase(NativeDatabase(file));
  }

  @override
  int get schemaVersion => dbVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // DDL is owned by bootstrap.dart (verbatim schema + migrations); a
        // bootstrapped file always reports user_version == schemaVersion, so
        // these hooks intentionally never run DDL.
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );
}
