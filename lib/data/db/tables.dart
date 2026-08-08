/// ============================================================================
///  Typed drift table declarations over the EXISTING schema
/// ============================================================================
///
///  Pattern proof (Milestone 0): the DDL source of truth stays the verbatim
///  [schemaSql] + migration pipeline — drift NEVER generates DDL here. These
///  table classes only describe the already-created columns so the app layer
///  gets type-safe queries. Remaining entities follow in Milestone 1.
library;

import 'package:drift/drift.dart';

/// `patients` — base DDL columns + migration-added sync/identity columns.
class Patients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get lastVisit => text().named('last_visit').nullable()();
  TextColumn get createdAt => text().named('created_at').nullable()();
  TextColumn get updatedAt => text().named('updated_at').nullable()();
  IntColumn get mod => integer().named('_mod').nullable()();
  IntColumn get deleted => integer().named('_deleted').nullable()();
  TextColumn get data => text().nullable()();

  // ── Added by shared migrations (sync/isolation + stable identity) ──
  TextColumn get clinicId => text().named('clinic_id').nullable()();
  TextColumn get hlc => text().named('_hlc').nullable()();
  IntColumn get dirty => integer().named('_dirty').nullable()();
  TextColumn get origin => text().named('_origin').nullable()();
  IntColumn get serverSeq => integer().named('server_seq').nullable()();
  TextColumn get ownerUid => text().named('owner_uid').nullable()();
  TextColumn get patientId => text().named('patient_id').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
