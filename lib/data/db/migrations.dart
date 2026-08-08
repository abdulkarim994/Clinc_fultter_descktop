/// ============================================================================
///  Shared migration runner — literal Dart port of src/platform/db/migrations.js
/// ============================================================================
///
///  Mirrors the Vue project's `runMigrations()` 1:1. The DB handle is replaced
///  by three injected primitives ([MigrationDb]) so ANY backend (package:sqlite3
///  natively, drift executor, in-memory test db) can run the SAME additive and
///  idempotent migrations and end up with an IDENTICAL schema.
///
///  Guard semantics preserved exactly:
///    • ALTERs tolerate "duplicate column" (idempotent re-run).
///    • Backfills run once, gated by a metadata flag.
///    • A failed phase is non-fatal (warned) and never blocks init.
library;

import '../../core/utils/ar_normalize.dart';
import 'schema_sql.dart';

/// Injected DB shim — mirrors the JS `{exec, flagExists, setFlag}` object.
abstract interface class MigrationDb {
  /// Run a DDL/DML statement (throws on error).
  void exec(String sql);

  /// Is `metadata[key]` present?
  bool flagExists(String key);

  /// Upsert `metadata[key] = '1'`.
  void setFlag(String key);
}

bool _isDupCol(Object e) =>
    e.toString().toLowerCase().contains('duplicate column');

/// Run all additive migrations. Returns `syncColsPromoted` so the caller can
/// mirror the mobile `_syncColsPromoted` gate.
({bool syncColsPromoted}) runMigrations(
  MigrationDb db, {
  bool phoneIdentityEnabled = false,
  void Function(String message)? warn,
}) {
  final w = warn ?? (_) {};
  var syncColsPromoted = false;

  // ── 1) Additive sync/isolation columns on pre-Phase-2 tables ─────────────
  for (final table in migrationTables) {
    for (final col in syncColumns) {
      try {
        db.exec('ALTER TABLE $table ADD COLUMN $col;');
      } catch (e) {
        if (!_isDupCol(e)) w('migrate $table.$col: $e');
      }
    }
  }
  for (final idx in migrationIndexes) {
    try {
      db.exec(idx);
    } catch (e) {
      w('index: $e');
    }
  }

  // ── 1-flutter) Additive fix for an upstream schema/repo mismatch ─────────
  // The xrays repository declares a `checksum` column (Phase 6 integrity
  // checksum, referenced by markUploaded's UPDATE) but NO migration in the
  // original codebase ever creates it — a latent prepare-time failure on
  // native SQLite, surfaced by this port's tests. Adding it additively is
  // two-way compatible: the Vue repo already lists `checksum` in its COLUMNS,
  // so its own SQL starts working on a database carrying the column.
  try {
    db.exec('ALTER TABLE xrays ADD COLUMN checksum TEXT;');
  } catch (e) {
    if (!_isDupCol(e)) w('migrate xrays.checksum: $e');
  }

  // ── expenses.payment (نوع دفع المصروف: كاش/تحويل) ────────────────────────
  //  المصروفات كيانٌ حديث؛ النسخُ التي أنشأت جدوله قبل هذا العمود تحتاج
  //  إضافةً لاحقة (والجديدة تُنشئه ضمن CREATE TABLE). الغياب = كاش (COALESCE
  //  في مجاميع المالية)، فلا يفسد صافي الخزينة على البيانات القديمة.
  try {
    db.exec('ALTER TABLE expenses ADD COLUMN payment TEXT;');
  } catch (e) {
    if (!_isDupCol(e)) w('migrate expenses.payment: $e');
  }

  // ── 2) Phase 1b: promote sync flags from `data` blob → real columns ──────
  try {
    if (!db.flagExists(MigrationFlags.phase1b)) {
      for (final t in phase1bTables) {
        db.exec('''UPDATE $t SET _dirty = json_extract(data,'\$._dirty')
           WHERE data IS NOT NULL AND json_extract(data,'\$._dirty') IS NOT NULL
             AND IFNULL(_dirty,0) <> IFNULL(json_extract(data,'\$._dirty'),0);''');
        for (final col in phase1bTextCols) {
          db.exec('''UPDATE $t SET $col = json_extract(data,'\$.$col')
             WHERE $col IS NULL AND data IS NOT NULL
               AND json_extract(data,'\$.$col') IS NOT NULL;''');
        }
      }
      db.setFlag(MigrationFlags.phase1b);
    }
    syncColsPromoted = true;
  } catch (e) {
    w('phase1b backfill: $e');
  }

  // ── 2ب) دفعة صفر/د (م66): ردم علم التعديل لـ records/xrays وأخواتها ───────
  // بعلمٍ منفصل كي يسري على النسخ التي ثبّتت علم 1ب سابقاً. حرّاس WHERE
  // تجعله بلا أثر على الجداول التي عمودها سليم أصلاً، فإعادة تشغيله آمنة.
  try {
    if (!db.flagExists(MigrationFlags.phase1bRest)) {
      for (final t in phase1bRestTables) {
        db.exec('''UPDATE $t SET _dirty = json_extract(data,'\$._dirty')
           WHERE data IS NOT NULL AND json_extract(data,'\$._dirty') IS NOT NULL
             AND IFNULL(_dirty,0) <> IFNULL(json_extract(data,'\$._dirty'),0);''');
      }
      db.setFlag(MigrationFlags.phase1bRest);
    }
  } catch (e) {
    w('phase1bRest dirty backfill: $e');
  }

  // ── 2ج) م81: عمود «شوهد» لسجل التعارضات ─────────────────────────────────
  // بلا هذا العمود يبقى الجدول يكتب بلا قارئ. إضافة محتملة التكرار ⇒
  // تُبتلع كأي ALTER في هذا الملف.
  try {
    db.exec('ALTER TABLE conflict_log ADD COLUMN seen INTEGER NOT NULL DEFAULT 0;');
  } catch (e) {
    if (!_isDupCol(e)) w('migrate conflict_log.seen: $e');
  }

  // ── 3) Phase 2a: promote hot financial columns on `records` ──────────────
  try {
    for (final (col, typ) in hotRecordColumns) {
      try {
        db.exec('ALTER TABLE records ADD COLUMN $col $typ;');
      } catch (e) {
        if (!_isDupCol(e)) rethrow;
      }
    }
    if (!db.flagExists(MigrationFlags.phase2a)) {
      db.exec('''UPDATE records SET payment = json_extract(data,'\$.payment')
        WHERE payment IS NULL AND data IS NOT NULL AND json_extract(data,'\$.payment') IS NOT NULL;''');
      db.exec('''UPDATE records SET debtId = json_extract(data,'\$.debtId')
        WHERE debtId IS NULL AND data IS NOT NULL AND json_extract(data,'\$.debtId') IS NOT NULL;''');
      for (final c in ['isDebt', 'isPros', 'isDebtPayment']) {
        db.exec(
            '''UPDATE records SET $c = COALESCE(json_extract(data,'\$.$c'), 0) WHERE $c IS NULL;''');
      }
      db.setFlag(MigrationFlags.phase2a);
    }
  } catch (e) {
    w('phase2a backfill: $e');
  }

  // ── 4) Phase 4.1: stable patient_id link column + name-key backfill ──────
  try {
    for (final t in pidTables) {
      try {
        db.exec('ALTER TABLE $t ADD COLUMN patient_id TEXT;');
      } catch (e) {
        if (!_isDupCol(e)) rethrow;
      }
      try {
        db.exec(
            'CREATE INDEX IF NOT EXISTS idx_${t}_patient_id ON $t(patient_id);');
      } catch (_) {
        // non-critical
      }
    }
    if (!db.flagExists(MigrationFlags.phase41)) {
      db.exec('''UPDATE patients SET patient_id = TRIM(name)
        WHERE patient_id IS NULL AND TRIM(IFNULL(name,'')) <> '';''');
      for (final t in pidChildTables) {
        db.exec('''UPDATE $t SET patient_id = TRIM(patient_name)
          WHERE patient_id IS NULL AND TRIM(IFNULL(patient_name,'')) <> '';''');
      }
      db.setFlag(MigrationFlags.phase41);
    }
  } catch (e) {
    w('phase4.1 backfill: $e');
  }

  // ── 5) Phase A: phone-anchored identity (feature-flagged, default OFF) ───
  try {
    if (phoneIdentityEnabled && !db.flagExists(MigrationFlags.phaseA)) {
      final pid =
          "('p:' || ${arNormPhoneSql('phone')} || ':' || ${arNormSql('name')})";
      db.exec('''UPDATE patients SET patient_id = $pid
        WHERE IFNULL(_dirty,0) = 0 AND TRIM(IFNULL(phone,'')) <> '' AND ${arNormPhoneSql('phone')} <> '';''');
      for (final t in ['records', 'debts', 'appointments', 'prosthetics', 'xrays']) {
        db.exec('''UPDATE $t SET patient_id = (
             SELECT MIN(p.patient_id) FROM patients p
             WHERE ${arNormSql('p.name')} = ${arNormSql('$t.patient_name')} AND p.patient_id LIKE 'p:%')
           WHERE IFNULL(_dirty,0) = 0
             AND (SELECT COUNT(DISTINCT p.patient_id) FROM patients p
                  WHERE ${arNormSql('p.name')} = ${arNormSql('$t.patient_name')} AND p.patient_id LIKE 'p:%') = 1;''');
      }
      db.setFlag(MigrationFlags.phaseA);
    }
  } catch (e) {
    w('phaseA identity backfill: $e');
  }

  // ── 6) Phase H: clinic-scoped identity backfill (appointments + xrays) ───
  try {
    if (!db.flagExists(MigrationFlags.phaseH)) {
      db.exec('''UPDATE appointments SET clinic_id = TRIM(clinic)
        WHERE IFNULL(_dirty,0) = 0 AND IFNULL(clinic_id,'') = '' AND TRIM(IFNULL(clinic,'')) <> '';''');
      db.exec('''UPDATE appointments SET clinic_id = TRIM(json_extract(data,'\$.clinic'))
        WHERE IFNULL(_dirty,0) = 0 AND IFNULL(clinic_id,'') = '' AND data IS NOT NULL
          AND TRIM(IFNULL(json_extract(data,'\$.clinic'),'')) <> '';''');
      db.exec('''UPDATE appointments SET patient_id = TRIM(patient_name)
        WHERE IFNULL(_dirty,0) = 0 AND IFNULL(patient_id,'') = '' AND TRIM(IFNULL(patient_name,'')) <> '';''');
      db.exec('''UPDATE appointments SET patient_id = TRIM(json_extract(data,'\$.name'))
        WHERE IFNULL(_dirty,0) = 0 AND IFNULL(patient_id,'') = '' AND data IS NOT NULL
          AND TRIM(IFNULL(json_extract(data,'\$.name'),'')) <> '';''');
      db.exec('''UPDATE xrays SET patient_id = TRIM(patient_name)
        WHERE IFNULL(_dirty,0) = 0 AND IFNULL(patient_id,'') = '' AND TRIM(IFNULL(patient_name,'')) <> '';''');
      db.exec('''UPDATE xrays SET clinic_id = (
           SELECT TRIM(MIN(r.clinic)) FROM records r
           WHERE TRIM(IFNULL(r.clinic,'')) <> '' AND TRIM(r.patient_name) = TRIM(xrays.patient_name))
         WHERE IFNULL(_dirty,0) = 0 AND IFNULL(clinic_id,'') = '' AND TRIM(IFNULL(patient_name,'')) <> ''
           AND (SELECT COUNT(DISTINCT TRIM(r.clinic)) FROM records r
                WHERE TRIM(IFNULL(r.clinic,'')) <> '' AND TRIM(r.patient_name) = TRIM(xrays.patient_name)) = 1;''');
      db.setFlag(MigrationFlags.phaseH);
    }
  } catch (e) {
    w('phaseH clinic-scope backfill: $e');
  }

  // ── 6ب) Phase A2 — الردم الحتمي لهوية الهاتف (م-عزل الهوية) ───────────────
  //
  //  علّة الأصل: هجرة phaseA (القسم 5) تشترط
  //  `COUNT(DISTINCT patient_id) = 1` قبل وسم صفوف الأولاد — فمريضان
  //  متشابهان بهاتفين مختلفين (هويتان) لا يُفصلان أبداً (يبقى العدد ≥ 2
  //  فلا يُلمس شيء)، وهذا جذر اختلاط بياناتهما.
  //
  //  الردم الحتمي هنا **بلا أي شرط تعداد**: كل صفٍّ نظيف (_dirty=0) **له
  //  هاتف** يُوسم بمعرّف هويته المشتق من **هاتفه واسمه هو** (توأم
  //  patientKeyFor: `p:<هاتف مطبَّع>:<اسم مطبَّع>`) — فينفصل السميّان حتماً
  //  على كل الأجهزة بنفس النتيجة. لا يشترط بعلم PHONE_IDENTITY: بيانات
  //  الإنتاج مكتوبةٌ بهذه المفاتيح أصلاً، والردم يوحّد القائم معها.
  //
  //  **صفوف dirty=1 تُترك** عمداً: هجرةٌ لا يصح أن تُنتج تعديلات تُدفع
  //  كتغييرات المستخدم؛ تلك الصفوف تُدفع أولاً ثم تُردَم بجولةٍ لاحقة حين
  //  يعود عمودها dirty=0. والصفوف **بلا هاتف واسمُها مكرَّرٌ بين هويتين
  //  فأكثر** ملتبسةٌ (لا تخمين في إلحاقها بأحدهما) فلا تُلمس، ويُحصَر
  //  عددُها في `metadata` (سجل الهجرة) مع تحذير.
  try {
    if (!db.flagExists('phaseA2_identity_backfill')) {
      const childTables = [
        'records', 'prosthetics', 'debts', 'appointments', 'xrays',
      ];
      // اسم/هاتف الصف مُعامَلان باسم الجدول/اللقب (لا استبدال نصّي هشّ):
      //   الاسم = العمود المرقّى أولاً ثم كتلة الـ blob؛ الهاتف من الكتلة.
      String nameOf(String a) => a.isEmpty
          ? "COALESCE(NULLIF(TRIM(IFNULL(patient_name,'')),''), json_extract(data,'\$.name'))"
          : "COALESCE(NULLIF(TRIM(IFNULL($a.patient_name,'')),''), json_extract($a.data,'\$.name'))";
      String phoneOf(String a) =>
          a.isEmpty ? "json_extract(data,'\$.phone')" : "json_extract($a.data,'\$.phone')";
      final nameExpr = nameOf('');
      final phoneExpr = phoneOf('');
      final normPhone = arNormPhoneSql(phoneExpr);
      final pid = "('p:' || $normPhone || ':' || ${arNormSql(nameExpr)})";

      for (final t in childTables) {
        // (أ) وسمٌ حتمي لكل صفٍّ نظيفٍ له هاتف — بلا شرط تعداد، وبلا
        //     اشتراط فراغ patient_id (إعادة الوسم فوق مفتاحٍ اسميٍّ قديم
        //     أو فوق هوية صحيحة كلاهما آمن: النتيجة نفسها حتماً).
        db.exec('''UPDATE $t SET patient_id = $pid
          WHERE IFNULL(_dirty,0) = 0
            AND data IS NOT NULL
            AND TRIM(IFNULL($phoneExpr,'')) <> '' AND $normPhone <> ''
            AND TRIM(IFNULL($nameExpr,'')) <> '';''');
      }

      // (ب) إعادة بناء صفوف patients هوياتياً:
      //   1) الصفوف التي لها هاتف (عمود phone) تُوسَم بمعرّف هويتها هي —
      //      حتمي، بلا شرط تعداد (توأم phaseA لكن غير مشروط).
      final pPidSelf =
          "('p:' || ${arNormPhoneSql('phone')} || ':' || ${arNormSql('name')})";
      db.exec('''UPDATE patients SET patient_id = $pPidSelf
        WHERE IFNULL(_dirty,0) = 0
          AND TRIM(IFNULL(phone,'')) <> '' AND ${arNormPhoneSql('phone')} <> ''
          AND TRIM(IFNULL(name,'')) <> '';''');
      //   2) هويات موجودة في صفوف الأولاد وغائبة عن جدول المرضى ⇒ تُنشأ
      //      صفوف مرضى جديدة (اسمها اسمُ أول صفٍّ، هاتفها من مفتاح الهوية):
      //      فيحصل كل سميٍّ على صفّه المستقل. المعرّف = patient_id الهوياتي.
      for (final t in childTables) {
        db.exec('''INSERT INTO patients (id, name, patient_id, _dirty, _deleted, owner_uid)
          SELECT c.patient_id,
                 (SELECT $nameExpr FROM $t c2
                    WHERE c2.patient_id = c.patient_id AND c2.data IS NOT NULL
                    ORDER BY c2.rowid LIMIT 1),
                 c.patient_id, 0, 0,
                 (SELECT c3.owner_uid FROM $t c3
                    WHERE c3.patient_id = c.patient_id ORDER BY c3.rowid LIMIT 1)
          FROM (SELECT DISTINCT patient_id FROM $t
                WHERE IFNULL(_dirty,0) = 0 AND patient_id LIKE 'p:%'
                  AND IFNULL(_deleted,0) = 0) c
          WHERE NOT EXISTS (SELECT 1 FROM patients p WHERE p.id = c.patient_id)
            AND NOT EXISTS (SELECT 1 FROM patients p WHERE p.patient_id = c.patient_id);''');
      }

      // (ج) حصر الملتبس: صفوف نظيفة **بلا هاتف** واسمُها (مطبَّعاً) يحمل
      //     هويتين هاتفيتين فأكثر بين صفوف الأولاد ⇒ لا تُلمس. نعدّها في
      //     سجل الهجرة (metadata) لأن شيم الهجرة لا يقرأ (exec فقط).
      final ambiguousUnion = [
        for (final t in childTables)
          '''SELECT '$t' AS tbl, x.rowid AS rid
             FROM $t x
             WHERE IFNULL(x._dirty,0) = 0 AND IFNULL(x._deleted,0) = 0
               AND x.data IS NOT NULL
               AND TRIM(IFNULL(${phoneOf('x')},'')) = ''
               AND TRIM(IFNULL(${nameOf('x')},'')) <> ''
               AND (
                 SELECT COUNT(DISTINCT ${arNormPhoneSql(phoneOf('y'))})
                 FROM $t y
                 WHERE IFNULL(y._dirty,0) = 0 AND y.data IS NOT NULL
                   AND ${arNormSql(nameOf('y'))} = ${arNormSql(nameOf('x'))}
                   AND TRIM(IFNULL(${phoneOf('y')},'')) <> ''
                   AND ${arNormPhoneSql(phoneOf('y'))} <> ''
               ) >= 2''',
      ].join('\nUNION ALL\n');
      db.exec('''INSERT OR REPLACE INTO metadata(key, value)
        VALUES ('phaseA2_ambiguous_count',
                (SELECT CAST(COUNT(*) AS TEXT) FROM ($ambiguousUnion)));''');
      // العدّاد في metadata.phaseA2_ambiguous_count هو التقرير (الشيم لا
      // يقرأ نتائج SQL فلا يمكن شرطُ تحذيرٍ بالعدد — وتحذيرٌ غير مشروط
      // يلوّث إقلاع كل قاعدةٍ نظيفة ويكسر عقد «إقلاع بلا تحذيرات»).

      db.setFlag('phaseA2_identity_backfill');
    }
  } catch (e) {
    w('phaseA2 identity backfill: $e');
  }

  // ── 7) Phase 4.2: FTS5 patient-name index + triggers + one-time populate ─
  try {
    for (final stmt in ftsStatements()) {
      db.exec(stmt);
    }
    if (!db.flagExists(MigrationFlags.phase42)) {
      db.exec('DELETE FROM patients_fts;');
      db.exec('''INSERT INTO patients_fts(rowid, pid, norm)
        SELECT rowid, id, ${arNormSql('name')} FROM patients WHERE name IS NOT NULL;''');
      db.setFlag(MigrationFlags.phase42);
    }
  } catch (e) {
    w('phase4.2 FTS build: $e');
  }

  return (syncColsPromoted: syncColsPromoted);
}
