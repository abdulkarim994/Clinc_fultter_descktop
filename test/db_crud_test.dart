/// اختبار طبقة drift المكتوبة فوق المخطط الحرفي: إدخال/قراءة/تحديث/حذف
/// ببيانات عربية حقيقية، مع التحقق من أن محفزات FTS تُبقي فهرس البحث
/// العربي متزامناً مع كل عملية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart';
import 'package:dental_clinic_flutter/data/db/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';


void main() {

  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m0_crud_');
    db = AppDatabase.openAt(tmp.path);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<List<String>> ftsSearch(String query) async {
    final rows = await db.customSelect(
      'SELECT pid FROM patients_fts WHERE norm MATCH ?',
      variables: [Variable.withString('${arNorm(query)}*')],
    ).get();
    return rows.map((r) => r.read<String>('pid')).toList();
  }

  test('Arabic patient CRUD round-trip through typed drift API', () async {
    await db.into(db.patients).insert(
          PatientsCompanion.insert(
            id: 'p1',
            name: 'أحمد الطيّب',
            phone: const Value('+218 91-234 5678'),
          ),
        );

    final fetched = await (db.select(db.patients)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(fetched.name, 'أحمد الطيّب');
    expect(normPhone(fetched.phone), '912345678');

    // FTS trigger kept the search index in sync on INSERT
    expect(await ftsSearch('أحمد'), contains('p1'));
    expect(await ftsSearch('احمد'), contains('p1')); // normalised query

    // UPDATE — trigger replaces the indexed row
    await (db.update(db.patients)..where((t) => t.id.equals('p1'))).write(
      const PatientsCompanion(name: Value('خالد المهدي')),
    );
    expect(await ftsSearch('خالد'), contains('p1'));
    expect(await ftsSearch('أحمد'), isNot(contains('p1')));

    // DELETE — trigger removes the indexed row
    await (db.delete(db.patients)..where((t) => t.id.equals('p1'))).go();
    expect(await ftsSearch('خالد'), isNot(contains('p1')));
    expect(
      await (db.select(db.patients)..where((t) => t.id.equals('p1')))
          .getSingleOrNull(),
      isNull,
    );
  });

  test('sync bookkeeping columns are writable through drift', () async {
    await db.into(db.patients).insert(
          PatientsCompanion.insert(
            id: 'p2',
            name: 'سالم أبو زيد',
            phone: const Value('0913334455'),
          ).copyWith(
            dirty: const Value(1),
            hlc: const Value('2026-07-26T12:00:00.000Z-0001-device1'),
            clinicId: const Value('العيادة الرئيسية'),
          ),
        );

    final row = await (db.select(db.patients)
          ..where((t) => t.id.equals('p2')))
        .getSingle();
    expect(row.dirty, 1);
    expect(row.hlc, isNotNull);
    expect(row.clinicId, 'العيادة الرئيسية');

    // and the raw sqlite view of the same row agrees (shared file, no drift
    // shadow state) — the guarantee that lets Vue and Flutter co-exist.
    final raw = await db.customSelect(
      'SELECT _dirty AS d, clinic_id AS c FROM patients WHERE id = ?',
      variables: [Variable.withString('p2')],
    ).getSingle();
    expect(raw.read<int>('d'), 1);
    expect(raw.read<String>('c'), 'العيادة الرئيسية');
  });
}
