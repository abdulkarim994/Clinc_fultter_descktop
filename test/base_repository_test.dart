/// اختبارات المستودع الأساسي: CRUD، شواهد الحذف الناعم، عزل الحسابات،
/// وترقيم keyset — الثوابت التي يقف عليها كل مستودع كيان.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/base_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _cols = [
  'id', 'name', 'phone', 'notes', 'last_visit',
  'created_at', 'updated_at', '_mod', '_deleted', 'data', 'owner_uid',
  '_hlc', '_dirty', '_origin', 'server_seq', 'clinic_id', 'patient_id',
];

void main() {
  late Directory tmp;
  late LocalDb db;
  late BaseRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m1_base_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repo = BaseRepository(db, 'patients', _cols);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('upsert / getById / getAll round-trip with blob extras', () {
    repo.upsert({
      'id': 'p1',
      'name': 'أحمد الطيّب',
      'phone': '0912345678',
      'customField': 'قيمة إضافية', // unknown → data blob
      'nested': {'a': 1},
    });
    final row = repo.getById('p1')!;
    expect(row['name'], 'أحمد الطيّب');
    expect(row['customField'], 'قيمة إضافية'); // blob merged back
    expect((row['nested'] as Map)['a'], 1);
    expect(repo.getAll().length, 1);
    expect(repo.count(), 1);
  });

  test('update() merges partial updates over the existing record', () {
    repo.upsert({'id': 'p1', 'name': 'أحمد', 'notes': 'قديم'});
    repo.update('p1', {'notes': 'جديد'});
    final row = repo.getById('p1')!;
    expect(row['name'], 'أحمد');
    expect(row['notes'], 'جديد');
    expect(repo.update('missing', {'x': 1}), isNull);
  });

  test('delete() writes a sync-propagating tombstone and kicks sync', () {
    var kicks = 0;
    db.setSyncKicker(() => kicks++);
    repo.upsert({'id': 'p1', 'name': 'أحمد'});
    repo.delete('p1');

    expect(repo.getAll(), isEmpty);
    expect(repo.getById('p1'), isNull);
    expect(repo.getDeletedIds(), ['p1']);
    expect(repo.getAllIncludingDeleted().length, 1);

    final raw = db.queryFirst('SELECT * FROM patients WHERE id = ?', ['p1'])!;
    expect(raw['_deleted'], 1);
    expect(raw['_dirty'], 1);
    expect(raw['_hlc'], isNotNull);
    expect(raw['_origin'], db.deviceId);
    expect(kicks, 1);
  });

  test('upsertLocal() stamps dirty + HLC + origin and kicks sync', () {
    var kicks = 0;
    db.setSyncKicker(() => kicks++);
    repo.upsertLocal({'id': 'p1', 'name': 'أحمد'});
    final raw = db.queryFirst('SELECT * FROM patients WHERE id = ?', ['p1'])!;
    expect(raw['_dirty'], 1);
    expect((raw['_hlc'] as String).endsWith(db.deviceId), isTrue);
    expect(raw['_origin'], db.deviceId);
    expect(kicks, 1);

    repo.markDirty('p1');
    expect(kicks, 2);
  });

  test('getModifiedSince() returns only newer rows (tombstones included)', () async {
    repo.upsert({'id': 'p1', 'name': 'أ'});
    await Future<void>.delayed(const Duration(milliseconds: 15));
    final t = DateTime.now().millisecondsSinceEpoch;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    repo.upsert({'id': 'p2', 'name': 'ب'});
    repo.delete('p2'); // tombstone also counts as a modification

    final rows = repo.getModifiedSince(t);
    expect(rows.map((r) => r['id']), everyElement('p2'));
    expect(rows, isNotEmpty);
  });

  group('account isolation (owner scope)', () {
    test('reads are scoped; unstamped legacy rows stay visible', () {
      repo.upsert({'id': 'legacy', 'name': 'قديم'}); // unscoped write
      db.setOwnerUid('u1');
      repo.upsert({'id': 'mine', 'name': 'لي'});
      // a foreign account's row, injected raw:
      db.execute(
        "INSERT INTO patients (id, name, _deleted, owner_uid) VALUES ('theirs','لهم',0,'u2')",
      );

      final ids = repo.getAll().map((r) => r['id']).toSet();
      expect(ids, {'legacy', 'mine'});
      expect(repo.count(), 2);
      expect(repo.getById('theirs'), isNull);

      final mine = db.queryFirst(
          'SELECT owner_uid FROM patients WHERE id = ?', ['mine'])!;
      expect(mine['owner_uid'], 'u1'); // stamped on write
    });

    test('withOwner never restamps a foreign row', () {
      db.setOwnerUid('u1');
      repo.upsert({'id': 'x', 'name': 'ن', 'owner_uid': 'u2'});
      final raw =
          db.queryFirst('SELECT owner_uid FROM patients WHERE id = ?', ['x'])!;
      expect(raw['owner_uid'], 'u2'); // left as-is (then invisible to u1)
      expect(repo.getById('x'), isNull);
    });
  });

  group('keyset pagination (getPage)', () {
    setUp(() {
      // 5 rows, duplicate last_visit values to exercise the id tie-breaker.
      final rows = [
        {'id': 'a', 'name': 'n', 'last_visit': '2026-07-03'},
        {'id': 'b', 'name': 'n', 'last_visit': '2026-07-02'},
        {'id': 'c', 'name': 'n', 'last_visit': '2026-07-02'},
        {'id': 'd', 'name': 'n', 'last_visit': '2026-07-01'},
        {'id': 'e', 'name': 'n', 'last_visit': '2026-07-01'},
      ];
      repo.bulkUpsert(rows);
    });

    test('pages cover all rows exactly once, in stable DESC order', () {
      final collected = <String>[];
      PageCursor? cursor;
      var guard = 0;
      while (true) {
        final page = repo.getPage(
            orderBy: 'last_visit', limit: 2, cursor: cursor);
        collected.addAll(page.items.map((r) => r['id'] as String));
        if (!page.hasMore) break;
        cursor = page.nextCursor;
        expect(++guard < 10, isTrue);
      }
      expect(collected, ['a', 'c', 'b', 'e', 'd']);
    });

    test('rejects a non-identifier orderBy (injection guard)', () {
      expect(
        () => repo.getPage(orderBy: 'date; DROP TABLE x'),
        throwsArgumentError,
      );
    });
  });

  test('device id persists across re-opens of the same database', () {
    final id1 = db.deviceId;
    db.close();
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    expect(db.deviceId, id1);
  });
}
