/// اختبارات م30 — مسح بيانات الحساب عند تبديل الحساب (دلالات clearLocalData):
///   • دخول uid مختلف عن آخر uid ⇒ مسح كامل لصفوف الحساب السابق.
///   • نفس المستخدم ⇒ لا مسح (offline-first: بياناته تبقى).
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
    tmp = Directory.systemTemp.createTempSync('m30_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('wipeAllAccountData يمسح كل صفوف الجداول ومفاتيح المزامنة', () {
    final db = c.read(localDbProvider);
    final repos = c.read(reposProvider);
    db.setOwnerUid('acc-1');
    repos.records.upsertLocal({
      'id': 'r1', 'name': 'أ', 'patient_name': 'أ', 'amount': 100,
      'date': '2026-07-27', 'clinic': 'ع1', 'payment': 'كاش',
    });
    repos.settings.set('app.config',
        {'centerName': 'مركز أ', 'clinics': ['ع1']});
    expect(repos.records.getAll(), hasLength(1));

    wipeAllAccountData(db);
    expect(repos.records.getAll(), isEmpty);
    expect(repos.settings.get('app.config'), isNull);
  });

  test('كشف التبديل: آخر uid مختلف ⇒ تبديل؛ نفسه ⇒ لا تبديل', () {
    final db = c.read(localDbProvider);
    expect(lastUid(db), isNull);
    setLastUid(db, 'acc-1');
    expect(lastUid(db), 'acc-1');
    // نفس المستخدم.
    expect(lastUid(db) != 'acc-1', isFalse);
    // مستخدم مختلف.
    expect(lastUid(db) != 'acc-2', isTrue);
  });

  test('علم الإعداد per-uid يصمد ولا يخلط بين الحسابات', () {
    final db = c.read(localDbProvider);
    markSetupComplete(db, 'acc-1');
    expect(isSetupFlagSet(db, 'acc-1'), isTrue);
    expect(isSetupFlagSet(db, 'acc-2'), isFalse,
        reason: 'العلم منفصل لكل حساب');
    // المسح لا يمحو علم الإعداد per-uid (device-local).
    wipeAllAccountData(db);
    expect(isSetupFlagSet(db, 'acc-1'), isTrue);
  });

  // إصلاح ثغرة تسرّب مالي: wipeAllAccountData كان يمسح migrationTables
  // الثمانية فقط، فيبقى جدولا employees (الرواتب) وexpenses (المصروفات)
  // للحساب السابق مرئيَّين للحساب الجديد بعد التبديل. هذا الاختبار حارسٌ
  // يمنع عودة الثغرة.
  test('المسح يشمل employees و expenses — لا تسرّب مالي عند التبديل', () {
    final db = c.read(localDbProvider);
    db.setOwnerUid('acc-1');
    db.execute(
        "INSERT INTO employees(id, name, base_salary) VALUES('e1','موظف',900)");
    db.execute(
        "INSERT INTO expenses(id, amount, category, date) "
        "VALUES('x1', 250, 'other', '2026-07-27')");
    expect(db.query('SELECT COUNT(*) c FROM employees').single['c'], 1);
    expect(db.query('SELECT COUNT(*) c FROM expenses').single['c'], 1);

    wipeAllAccountData(db);

    expect(db.query('SELECT COUNT(*) c FROM employees').single['c'], 0,
        reason: 'رواتب الحساب السابق مُسحت');
    expect(db.query('SELECT COUNT(*) c FROM expenses').single['c'], 0,
        reason: 'مصروفات الحساب السابق مُسحت');
  });
}
