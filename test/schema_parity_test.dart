/// اختبار تكافؤ المخطط — القاعدة الناتجة عن نسخة Flutter مطابقة بنيوياً
/// للقاعدة التي ينتجها المشروع الأصلي (نفس الجداول والأعمدة والفهارس
/// والمحفزات وأعلام الهجرة و user_version).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/bootstrap.dart';
import 'package:dental_clinic_flutter/data/db/schema_sql.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';


void main() {

  late Directory tmp;
  late Database db;
  late List<String> warnings;

  List<String> tableNames() => db
      .select("SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'")
      .map((r) => r['name'] as String)
      .toList();

  List<String> columnsOf(String table) => db
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'] as String)
      .toList();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m0_schema_');
    warnings = <String>[];
    db = openBootstrappedDb(
      p.join(tmp.path, '$dbName.db'),
      warn: warnings.add,
    );
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('creates all 15 relational tables', () {
    final tables = tableNames();
    for (final t in expectedTables) {
      expect(tables, contains(t), reason: 'missing table $t');
    }
  });

  test('bootstrap completes without warnings', () {
    expect(warnings, isEmpty, reason: warnings.join('\n'));
  });

  test('patients carries base + sync + identity columns', () {
    final cols = columnsOf('patients');
    for (final c in [
      'id', 'name', 'phone', 'notes', 'last_visit', 'created_at', 'updated_at',
      '_mod', '_deleted', 'data',
      // migration-added:
      'clinic_id', '_hlc', '_dirty', '_origin', 'server_seq', 'owner_uid',
      'patient_id',
    ]) {
      expect(cols, contains(c), reason: 'patients missing column $c');
    }
  });

  test('records carries the promoted hot financial columns', () {
    final cols = columnsOf('records');
    for (final c in [
      'payment', 'isDebt', 'isPros', 'isDebtPayment', 'debtId', 'patient_id',
    ]) {
      expect(cols, contains(c), reason: 'records missing column $c');
    }
  });

  test('queue_patients matches the queue-system shape', () {
    final cols = columnsOf('queue_patients');
    for (final c in [
      'clinic', 'clinic_id', 'date', 'period', 'seq', 'status', 'est_time',
      'est_manual', 'state', 'archive_seq', 'entered_at', 'owner_uid',
    ]) {
      expect(cols, contains(c), reason: 'queue_patients missing column $c');
    }
  });

  test('representative indexes exist', () {
    final idx = db
        .select("SELECT name FROM sqlite_master WHERE type='index'")
        .map((r) => r['name'] as String)
        .toList();
    for (final i in [
      'idx_patients_dirty',
      'idx_queue_scope',
      'idx_appts_clinic_date',
      'idx_patients_patient_id',
      'idx_conflict_entity',
      'idx_uploads_status',
    ]) {
      expect(idx, contains(i), reason: 'missing index $i');
    }
  });

  test('FTS5 table + all three triggers exist', () {
    expect(tableNames(), contains('patients_fts'));
    final triggers = db
        .select("SELECT name FROM sqlite_master WHERE type='trigger'")
        .map((r) => r['name'] as String)
        .toList();
    expect(triggers,
        containsAll(['patients_fts_ai', 'patients_fts_au', 'patients_fts_ad']));
  });

  test('one-time migration flags are set (phaseA stays off by default)', () {
    final flags = db
        .select('SELECT key FROM metadata')
        .map((r) => r['key'] as String)
        .toList();
    expect(
      flags,
      containsAll([
        MigrationFlags.phase1b,
        MigrationFlags.phase2a,
        MigrationFlags.phase41,
        MigrationFlags.phaseH,
        MigrationFlags.phase42,
      ]),
    );
    expect(flags, isNot(contains(MigrationFlags.phaseA)));
  });

  test('user_version mirrors DB_VERSION', () {
    final v = db.select('PRAGMA user_version').first.values.first as int;
    expect(v, dbVersion);
  });

  test('bootstrap is idempotent on an existing database', () {
    final w2 = <String>[];
    bootstrapSchema(db, warn: w2.add);
    expect(w2, isEmpty, reason: w2.join('\n'));
    final tables = tableNames();
    for (final t in expectedTables) {
      expect(tables, contains(t));
    }
  });
}
