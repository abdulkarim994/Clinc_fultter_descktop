/// اختبارات م66/دفعة صفر-د — ردم علم التعديل لـ records/xrays.
///
/// العيب الأصلي (DATA-1): `_dirty` أُضيف لـ records/xrays بـ ALTER افتراضه
/// صفر، وردم المرحلة 1ب غطّى patients/appointments/debts فقط. صفٌّ قديم
/// يحمل `_dirty:1` في كتلته يحصل على عمود = 0 فلا يُرفع أبداً بينما الواجهة
/// تعرضه بانتظار المزامنة — زيارات وأشعة تُفقد بصمت.
///
/// نبني مخططاً «قديم الشكل» يدوياً (العلم داخل الكتلة والعمود صفر) ثم نشغّل
/// الردم ونؤكد أن getDirtyRows صار يراها.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/bootstrap.dart';
import 'package:dental_clinic_flutter/data/db/migrations.dart';
import 'package:dental_clinic_flutter/data/db/schema_sql.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late Database db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m66bf_');
    db = sqlite3.open('${tmp.path}/t.db');
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('صف records بعلم داخل الكتلة يصير مرئياً للدفع بعد الردم', () {
    // 1) مخطط أساس + أعمدة المزامنة (بلا ردم بعد) — كأنه بعد ALTER فقط.
    db.execute(schemaSql);
    for (final c in syncColumns) {
      try {
        db.execute('ALTER TABLE records ADD COLUMN $c;');
      } catch (_) {/* موجود */}
    }
    // 2) صف قديم: العمود = 0 لكن الكتلة تحمل _dirty:1 (لم يُرفع بعد).
    db.execute(
        "INSERT INTO records (id, _dirty, data) VALUES "
        "('r-old', 0, '{\"_dirty\":1,\"name\":\"سالم\"}');");

    // قبل الردم: الاستعلام السريع لا يراه.
    var hits = db
        .select("SELECT id FROM records WHERE _dirty = 1")
        .length;
    expect(hits, 0, reason: 'العيب: الصف القديم غير مرئي قبل الردم');

    // 3) تشغيل الهجرات (تشمل ردم دفعة صفر/د).
    runMigrations(SqliteMigrationShim(db), phoneIdentityEnabled: false);

    // بعد الردم: العمود صار 1 فيراه مسار الدفع.
    hits = db.select("SELECT id FROM records WHERE _dirty = 1").length;
    expect(hits, 1, reason: 'م66: الصف القديم صار مرئياً للدفع');
  });

  test('العلم يمنع إعادة الردم، والردم بلا أثر على صف سليم', () {
    db.execute(schemaSql);
    // الهجرة تضيف عمود _dirty لـ records، ثم نُدخل صفاً سليماً.
    runMigrations(SqliteMigrationShim(db), phoneIdentityEnabled: false);
    db.execute("INSERT INTO records (id, _dirty, data) VALUES "
        "('r-ok', 0, '{\"name\":\"هند\"}');");
    // العلم مثبَّت الآن.
    final flag = db.select(
        "SELECT value FROM metadata WHERE key = ?",
        [MigrationFlags.phase1bRest]);
    expect(flag.isNotEmpty, isTrue, reason: 'العلم ثُبِّت');
    // إعادة التشغيل بلا خطأ (idempotent).
    runMigrations(SqliteMigrationShim(db), phoneIdentityEnabled: false);
    final r = db.select("SELECT _dirty FROM records WHERE id='r-ok'").single;
    expect(r['_dirty'], 0, reason: 'صف سليم لم يتغيّر');
  });
}
