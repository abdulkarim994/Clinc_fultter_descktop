/// اختبارات م33 — تعافي الملكية (علة «بيانات الحساب القديم تظهر عند الفتح»):
/// صفوف قديمة بلا ختم مالك + صفوف حساب آخر كانت تتسرب لأي حساب (عبارة
/// العزل تقبل المالك الفارغ). التعافي عند الإقلاع: ختم المتسخة، مسح
/// النظيفة والأجنبية، تصفير مؤشر السحب، تسجيل آخر حساب.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m33_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('cloud: المتسخة بلا مالك تُختم والنظيفة والأجنبية تُمسح والمؤشر يصفَّر',
      () {
    final db = c.read(localDbProvider);
    // صف نظيف بلا مالك (عهد قديم) + صف متسخ بلا مالك + صف حساب آخر.
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_clean', '{}', 'أ', 0, NULL)");
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_dirty', '{}', 'ب', 1, NULL)");
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_foreign', '{}', 'ج', 0, 'acc-OLD')");
    db.execute(
        "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
        "VALUES ('sync.cursor.txid', '999', datetime('now'))");

    healOwnershipAtBoot(db, 'acc-NEW', cloud: true);

    final rows = db.query('SELECT id, owner_uid FROM records ORDER BY id');
    expect(rows, hasLength(1), reason: 'النظيفة والأجنبية مُسحت');
    expect(rows.first['id'], 'r_dirty');
    expect(rows.first['owner_uid'], 'acc-NEW', reason: 'المتسخة خُتمت');
    final cursor = db.queryFirst(
        "SELECT value FROM metadata WHERE key = 'sync.cursor.txid'");
    expect(cursor, isNull, reason: 'المؤشر صُفِّر ⇒ سحب كامل تالٍ');
    expect(lastUid(db), 'acc-NEW');
  });

  test('دخول جديد (claimDirty=false): حتى المتسخة بلا مالك تُمسح', () {
    final db = c.read(localDbProvider);
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_dirty', '{}', 'ب', 1, NULL)");
    healOwnershipAtBoot(db, 'acc-B', cloud: true, claimDirty: false);
    expect(db.query('SELECT id FROM records'), isEmpty,
        reason: 'لا استمرارية جلسة ⇒ لا ادعاء');
  });

  test('local (بلا سحابة): تُختم الكل ولا يُمسح شيء', () {
    final db = c.read(localDbProvider);
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_clean', '{}', 'أ', 0, NULL)");
    healOwnershipAtBoot(db, 'acc-L', cloud: false);
    final rows = db.query('SELECT id, owner_uid FROM records');
    expect(rows, hasLength(1));
    expect(rows.first['owner_uid'], 'acc-L');
  });

  test('صفوف الحساب نفسه تبقى كما هي', () {
    final db = c.read(localDbProvider);
    db.execute(
        "INSERT INTO records(id, data, patient_name, _dirty, owner_uid) "
        "VALUES ('r_mine', '{}', 'أ', 0, 'acc-ME')");
    healOwnershipAtBoot(db, 'acc-ME', cloud: true);
    expect(db.query('SELECT id FROM records'), hasLength(1));
  });
}
