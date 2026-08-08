/// ============================================================================
///  Shared DB Schema — literal Dart port of src/platform/db/schema.js
/// ============================================================================
///
///  Single source of truth for the relational schema and the additive
///  migration definitions. The [schemaSql] string below is byte-identical to
///  `SCHEMA_SQL` in the Vue project (same tables, same indexes, same order),
///  so a database created by this Flutter app is indistinguishable from one
///  created by the existing desktop/mobile app — the key requirement for the
///  side-by-side parallel-run rollout strategy.
library;

import '../../core/utils/ar_normalize.dart';

const String dbName = 'dental_clinic_offline';
const int dbVersion = 4;

/// Relational schema (CREATE TABLE / INDEX) — verbatim from schema.js.
const String schemaSql = '''
CREATE TABLE IF NOT EXISTS patients (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  notes TEXT,
  last_visit TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _deleted INTEGER DEFAULT 0,
  data TEXT
);

CREATE INDEX IF NOT EXISTS idx_patients_name ON patients(name);
CREATE INDEX IF NOT EXISTS idx_patients_last_visit ON patients(last_visit);

CREATE TABLE IF NOT EXISTS appointments (
  id TEXT PRIMARY KEY,
  patient_name TEXT,
  date TEXT,
  time TEXT,
  service TEXT,
  clinic TEXT,
  notes TEXT,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _deleted INTEGER DEFAULT 0,
  data TEXT
);

CREATE INDEX IF NOT EXISTS idx_appts_date ON appointments(date);
CREATE INDEX IF NOT EXISTS idx_appts_patient ON appointments(patient_name);

CREATE TABLE IF NOT EXISTS xrays (
  id TEXT PRIMARY KEY,
  patient_name TEXT,
  file_key TEXT,
  thumbnail_data TEXT,
  upload_status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _deleted INTEGER DEFAULT 0,
  data TEXT
);

CREATE INDEX IF NOT EXISTS idx_xrays_patient ON xrays(patient_name);

CREATE TABLE IF NOT EXISTS records (
  id TEXT PRIMARY KEY,
  patient_name TEXT,
  date TEXT,
  service TEXT,
  amount REAL DEFAULT 0,
  clinic TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _deleted INTEGER DEFAULT 0,
  data TEXT
);

CREATE INDEX IF NOT EXISTS idx_records_date ON records(date);
CREATE INDEX IF NOT EXISTS idx_records_patient ON records(patient_name);

CREATE TABLE IF NOT EXISTS debts (
  id TEXT PRIMARY KEY,
  patient_name TEXT,
  total_amount REAL DEFAULT 0,
  paid_amount REAL DEFAULT 0,
  remaining REAL DEFAULT 0,
  status TEXT DEFAULT 'unpaid',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _deleted INTEGER DEFAULT 0,
  data TEXT
);

CREATE INDEX IF NOT EXISTS idx_debts_patient ON debts(patient_name);
CREATE INDEX IF NOT EXISTS idx_debts_status ON debts(status);

CREATE TABLE IF NOT EXISTS sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT,
  user_id TEXT,
  data TEXT,
  status TEXT DEFAULT 'pending',
  retries INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 5,
  created_at TEXT DEFAULT (datetime('now')),
  last_attempt TEXT,
  error_msg TEXT
);

CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_queue(status);
CREATE INDEX IF NOT EXISTS idx_sync_user ON sync_queue(user_id);

CREATE TABLE IF NOT EXISTS pending_uploads (
  id TEXT PRIMARY KEY,
  file_key TEXT NOT NULL,
  patient_name TEXT,
  file_path TEXT,
  file_size INTEGER DEFAULT 0,
  mime_type TEXT,
  status TEXT DEFAULT 'pending',
  retries INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 5,
  created_at TEXT DEFAULT (datetime('now')),
  last_attempt TEXT,
  error_msg TEXT
);

CREATE INDEX IF NOT EXISTS idx_uploads_status ON pending_uploads(status);

CREATE TABLE IF NOT EXISTS sync_meta (
  key TEXT PRIMARY KEY,
  value TEXT,
  user_id TEXT,
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_meta_user ON sync_meta(user_id);

CREATE TABLE IF NOT EXISTS metadata (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Phase 2: prosthetics as a first-class relational table (was missing).
CREATE TABLE IF NOT EXISTS prosthetics (
  id TEXT PRIMARY KEY,
  clinic_id TEXT,
  patient_name TEXT,
  date TEXT,
  type TEXT,
  amount REAL DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _hlc TEXT,
  _deleted INTEGER DEFAULT 0,
  _dirty INTEGER DEFAULT 0,
  _origin TEXT,
  server_seq INTEGER,
  data TEXT
);
CREATE INDEX IF NOT EXISTS idx_pros_clinic_date ON prosthetics(clinic_id, date);
CREATE INDEX IF NOT EXISTS idx_pros_patient ON prosthetics(patient_name);
CREATE INDEX IF NOT EXISTS idx_pros_dirty ON prosthetics(_dirty);

-- Phase 2: settings as one row per key (field-level, never a single blob).
CREATE TABLE IF NOT EXISTS settings (
  id TEXT PRIMARY KEY,
  clinic_id TEXT,
  value TEXT,
  data TEXT,
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _hlc TEXT,
  _deleted INTEGER DEFAULT 0,
  _dirty INTEGER DEFAULT 0,
  _origin TEXT,
  server_seq INTEGER
);
CREATE INDEX IF NOT EXISTS idx_settings_clinic ON settings(clinic_id);

-- Phase 2: conflict log keeps the discarded side of every resolved conflict.
CREATE TABLE IF NOT EXISTS conflict_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_json TEXT,
  remote_json TEXT,
  resolved_to TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  -- م81 — هل عُرض هذا التعارض على المستخدم؟ بلا هذا العمود كان الجدول
  -- يكتب بلا قارئ: كل تعارض يُحسم صامتاً ويُدفن هنا إلى الأبد.
  seen INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_conflict_entity ON conflict_log(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_conflict_seen ON conflict_log(seen, id DESC);

-- ── م79 — سجلّ التدقيق: من فعل ماذا بأي سجلّ ومتى ──────────────────────
--
--  لماذا جدول منفصل ولم يكفِ `_audit` على الصف
--  ───────────────────────────────────────────
--  المصفوفة القائمة على الصف تسجّل **تغيّر الحقول فقط**، وتفتقر إلى ثلاثة
--  أمور يسأل عنها أي تدقيق تنظيمي:
--    • **من** — لا هوية فاعل إطلاقاً، فلا يُعرف من غيّر المبلغ.
--    • **الاطّلاع** — فتحُ ملف مريض لا يُسجَّل، وهو أكثر ما يُسأل عنه في
--      تحقيق تسريب: «من اطّلع على ملف فلان؟».
--    • **الثبات** — تعيش على الصف المتزامن، فمن يكتب الصف يعيد كتابة
--      تاريخه، وسقفها خمسون قيداً تُسقط الأقدم صامتةً.
--
--  هذا الجدول **يُضاف إليه ولا يُعدَّل ولا يُحذف منه** محلياً، ويُدفع إلى
--  جدول خادمي بسياسة إدراج فقط — فحتى المالك لا يُعيد كتابة التاريخ.
--
--  ⚠ لا أسماء مرضى هنا. `entity_id` معرّفٌ يكفي للربط، والاسم يتغيّر
--  فيصير السجلّ كاذباً. و`detail` مقصور على بنية غير شخصية (أسماء حقول،
--  أعداد) — لا نصوص حرّة.
CREATE TABLE IF NOT EXISTS audit_events (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  actor_uid TEXT,
  device_id TEXT,
  action TEXT NOT NULL,
  entity TEXT,
  entity_id TEXT,
  detail TEXT,
  pushed INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_audit_pushed ON audit_events(pushed, at);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_events(entity, entity_id, at);

-- Queue System (نظام الدور): fully isolated from the rest of the app.
-- One row per queued/archived patient, scoped by clinic + date + period.
CREATE TABLE IF NOT EXISTS queue_patients (
  id TEXT PRIMARY KEY,
  clinic TEXT,
  clinic_id TEXT,
  date TEXT,
  period TEXT DEFAULT 'morning',
  seq INTEGER DEFAULT 0,
  patient_name TEXT,
  phone TEXT,
  status TEXT DEFAULT 'new',
  est_time TEXT,
  est_manual INTEGER DEFAULT 0,
  notes TEXT,
  state TEXT DEFAULT 'waiting',
  archive_seq INTEGER,
  entered_at TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _hlc TEXT,
  _deleted INTEGER DEFAULT 0,
  _dirty INTEGER DEFAULT 0,
  _origin TEXT,
  server_seq INTEGER,
  owner_uid TEXT,
  data TEXT
);
CREATE INDEX IF NOT EXISTS idx_queue_scope ON queue_patients(clinic, date, period, state);
CREATE INDEX IF NOT EXISTS idx_queue_date ON queue_patients(date);
CREATE INDEX IF NOT EXISTS idx_queue_dirty ON queue_patients(_dirty);
CREATE INDEX IF NOT EXISTS idx_queue_owner ON queue_patients(owner_uid);

-- ── المصروفات (م — دفعة المصروفات): موظفون + بنود مصروفات ────────────────
--  كيانان جديدان يتزامنان عبر sync_rows العام (لا جدول خادم جديد: تحقّقنا أن
--  apply_changes بلا قائمة كيانات، والمفتاح (user_id, entity, id) نصّي حر).
--  يُنشآن هنا بكل أعمدة المزامنة أصلاً (كنمط prosthetics/queue_patients)،
--  فلا يحتاجان صفَّ [migrationTables]. وبفضل CREATE ... IF NOT EXISTS يجريان
--  على القواعد القائمة أيضاً عند أول إقلاع (bootstrapSchema يُنفَّذ كل مرة).
CREATE TABLE IF NOT EXISTS employees (
  id TEXT PRIMARY KEY,
  clinic_id TEXT,
  name TEXT,
  role TEXT,
  base_salary REAL DEFAULT 0,
  active INTEGER DEFAULT 1,
  sort INTEGER DEFAULT 0,
  note TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _hlc TEXT,
  _deleted INTEGER DEFAULT 0,
  _dirty INTEGER DEFAULT 0,
  _origin TEXT,
  server_seq INTEGER,
  owner_uid TEXT,
  data TEXT
);
CREATE INDEX IF NOT EXISTS idx_employees_dirty ON employees(_dirty);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON employees(owner_uid);

-- بند مصروف واحد. category ∈ (salary_withdrawal | cleaning | dental | other).
-- سحب الراتب = صفٌّ category='salary_withdrawal' مع employee_id وdate السحب،
-- فيدخل الإجمالي وطباعة اليوم مع بقية المصروفات باستعلام واحد.
CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  clinic_id TEXT,
  category TEXT,
  title TEXT,
  amount REAL DEFAULT 0,
  date TEXT,
  employee_id TEXT,
  payment TEXT,
  note TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  _mod INTEGER DEFAULT 0,
  _hlc TEXT,
  _deleted INTEGER DEFAULT 0,
  _dirty INTEGER DEFAULT 0,
  _origin TEXT,
  server_seq INTEGER,
  owner_uid TEXT,
  data TEXT
);
CREATE INDEX IF NOT EXISTS idx_expenses_clinic_date ON expenses(clinic_id, date);
CREATE INDEX IF NOT EXISTS idx_expenses_cat_date ON expenses(category, date);
CREATE INDEX IF NOT EXISTS idx_expenses_employee ON expenses(employee_id);
CREATE INDEX IF NOT EXISTS idx_expenses_dirty ON expenses(_dirty);
CREATE INDEX IF NOT EXISTS idx_expenses_owner ON expenses(owner_uid);
''';

/// The 15 relational tables created by [schemaSql] (used by parity tests).
const List<String> expectedTables = [
  'patients', 'appointments', 'xrays', 'records', 'debts',
  'sync_queue', 'pending_uploads', 'sync_meta', 'metadata',
  'prosthetics', 'settings', 'conflict_log', 'queue_patients',
  'employees', 'expenses',
];

// ── Additive, idempotent migration definitions (verbatim port) ─────────────

/// Sync/isolation columns ALTER-added to pre-Phase-2 tables.
const List<String> syncColumns = [
  'clinic_id TEXT',
  '_hlc TEXT',
  '_dirty INTEGER DEFAULT 0',
  '_origin TEXT',
  'server_seq INTEGER',
  'owner_uid TEXT',
];

/// Tables that receive the [syncColumns].
const List<String> migrationTables = [
  'patients', 'appointments', 'records', 'debts',
  'xrays', 'prosthetics', 'settings', 'queue_patients',
];

/// Indexes for the dirty/owner/clinic columns (idempotent).
const List<String> migrationIndexes = [
  'CREATE INDEX IF NOT EXISTS idx_patients_dirty ON patients(_dirty)',
  'CREATE INDEX IF NOT EXISTS idx_records_dirty ON records(_dirty)',
  'CREATE INDEX IF NOT EXISTS idx_appts_dirty ON appointments(_dirty)',
  'CREATE INDEX IF NOT EXISTS idx_debts_dirty ON debts(_dirty)',
  'CREATE INDEX IF NOT EXISTS idx_patients_owner ON patients(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_records_owner ON records(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_pros_owner ON prosthetics(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_appts_owner ON appointments(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_debts_owner ON debts(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_xrays_owner ON xrays(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_settings_owner ON settings(owner_uid)',
  'CREATE INDEX IF NOT EXISTS idx_appts_clinic_date ON appointments(clinic_id, date)',
  'CREATE INDEX IF NOT EXISTS idx_xrays_clinic ON xrays(clinic_id)',
];

/// Phase 1b: entities whose sync flags are promoted from the `data` blob.
const List<String> phase1bTables = ['patients', 'appointments', 'debts'];
const List<String> phase1bTextCols = ['_hlc', '_origin', 'server_seq', 'clinic_id'];

/// دفعة صفر/د (م66) — الجداول التي فاتها ردم علم التعديل.
///
/// `records` و`xrays` أُضيف لهما `_dirty` بـ ALTER بقيمة افتراضية صفر، لكن
/// ردم المرحلة 1ب غطّى patients/appointments/debts فقط. فصفٌّ قديم (من تطبيق
/// Vue أو ما قبل الهجرة) يحمل `_dirty:1` داخل كتلته يحصل على عمودٍ = 0،
/// فيستبعده مسار الدفع السريع `WHERE _dirty = 1` ولا يُرفع **أبداً** بينما
/// الواجهة تعرضه «بانتظار المزامنة» — زيارات وأشعة تُفقد بصمت.
///
/// يُردَم بعلمٍ منفصل كي يسري على النسخ القائمة التي ثبّتت علم 1ب سابقاً.
/// (prosthetics/queue_patients/settings عمودها في المخطط الأساس فلا فجوة
/// لديها، لكن إدراجها آمن — حرّاس WHERE تجعلها بلا أثر.)
const List<String> phase1bRestTables = [
  'records', 'xrays', 'prosthetics', 'queue_patients',
];

/// Phase 2a: hot financial columns promoted on `records`.
const List<(String, String)> hotRecordColumns = [
  ('payment', 'TEXT'),
  ('isDebt', 'INTEGER'),
  ('isPros', 'INTEGER'),
  ('isDebtPayment', 'INTEGER'),
  ('debtId', 'TEXT'),
];

/// Phase 4.1: stable patient_id link column tables.
const List<String> pidTables = [
  'patients', 'appointments', 'records', 'debts', 'prosthetics', 'xrays',
];
const List<String> pidChildTables = [
  'appointments', 'records', 'debts', 'prosthetics', 'xrays',
];

/// One-time migration guard flags (metadata table).
abstract final class MigrationFlags {
  static const phase1b = 'phase1b_sync_cols_backfilled';
  static const phase1bRest = 'phase1b_rest_dirty_backfilled'; // م66/دفعة صفر-د
  static const phase2a = 'phase2a_record_cols_backfilled';
  static const phase41 = 'phase41_patient_id_backfilled';
  static const phaseA = 'phoneA_identity_backfilled';
  static const phaseH = 'phaseH_clinic_scope_backfilled';
  static const phase42 = 'phase42_fts_built';
}

/// Build the FTS5 DDL (virtual table + triggers) using the shared arNorm SQL.
/// Verbatim port of `ftsStatements()` in schema.js.
List<String> ftsStatements() {
  final norm = arNormSql('new.name');
  return [
    '''CREATE VIRTUAL TABLE IF NOT EXISTS patients_fts USING fts5(
         pid UNINDEXED, norm, tokenize = 'unicode61 remove_diacritics 2'
       );''',
    '''CREATE TRIGGER IF NOT EXISTS patients_fts_ai AFTER INSERT ON patients BEGIN
         INSERT INTO patients_fts(rowid, pid, norm) VALUES (new.rowid, new.id, $norm);
       END;''',
    '''CREATE TRIGGER IF NOT EXISTS patients_fts_au AFTER UPDATE OF name, id ON patients BEGIN
         DELETE FROM patients_fts WHERE rowid = old.rowid;
         INSERT INTO patients_fts(rowid, pid, norm) VALUES (new.rowid, new.id, $norm);
       END;''',
    '''CREATE TRIGGER IF NOT EXISTS patients_fts_ad AFTER DELETE ON patients BEGIN
         DELETE FROM patients_fts WHERE rowid = old.rowid;
       END;''',
  ];
}
