/// اختبارات م71 — احتفاظ المواعيد: الشطب بعد أسبوع بتاريخ الموعد،
/// والبوابتان اليومية والأسبوعية، والحذف الفعلي للشواهد.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/retention.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class FakePurge implements TombstonePurge {
  final calls = <int>[];
  bool fail = false;

  @override
  Future<int> purgeExpired({required int retainDays}) async {
    if (fail) throw Exception('purge down');
    calls.add(retainDays);
    return 5;
  }
}

void main() {
  late Directory tmp;
  late LocalDb db;
  late Repositories repos;
  late SyncContext ctx;
  late FakePurge purge;
  var now = DateTime(2026, 7, 30, 12);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m71_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    ctx = SyncContext(db: db, repos: repos, transport: FakeSyncServer());
    purge = FakePurge();
    now = DateTime(2026, 7, 30, 12);
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  RetentionSweeper sweeper() =>
      RetentionSweeper(ctx: ctx, purge: purge, now: () => now);

  String dateOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void seedAppt(String id, {required int daysFromNow, String? date}) {
    db.execute(
      'INSERT INTO appointments (id, date, _mod, _dirty, _deleted, _hlc, data) '
      'VALUES (?,?,?,0,0,?,?)',
      [
        id,
        date ?? dateOf(now.add(Duration(days: daysFromNow))),
        now.millisecondsSinceEpoch,
        '${now.millisecondsSinceEpoch}:0:seed',
        jsonEncode({'id': id}),
      ],
    );
  }

  Map<String, Object?>? raw(String id) =>
      db.queryFirst('SELECT * FROM appointments WHERE id = ?', [id]);

  group('م71 — شطب المواعيد', () {
    test('الأقدم من أسبوع يُشطب بشاهد متسخ؛ الحديث والمستقبلي وبلا تاريخ تبقى',
        () async {
      seedAppt('appt_8d', daysFromNow: -8);
      seedAppt('appt_6d', daysFromNow: -6);
      seedAppt('appt_today', daysFromNow: 0);
      seedAppt('appt_future', daysFromNow: 30);
      seedAppt('appt_nodate', daysFromNow: 0, date: '');

      final r = await sweeper().sweep();
      expect(r.swept, 1);

      final tomb = raw('appt_8d')!;
      expect(tomb['_deleted'], 1);
      expect(tomb['_dirty'], 1, reason: 'الشاهد يسافر بالمزامنة');
      expect('${tomb['_hlc']}', isNot('${now.millisecondsSinceEpoch}:0:seed'),
          reason: 'ساعة جديدة للشاهد');

      for (final id in ['appt_6d', 'appt_today', 'appt_future', 'appt_nodate']) {
        expect(raw(id)!['_deleted'], 0, reason: '$id يجب أن يبقى');
      }
    });

    test('موعد ماضٍ قديم بتعديل حديث يُشطب أيضاً (العبرة بتاريخ الموعد)',
        () async {
      // أُنشئ الآن (_mod حديث) لكن تاريخه قبل شهر — انتهى ولن يعود.
      seedAppt('appt_old_edit', daysFromNow: -30);
      final r = await sweeper().sweep();
      expect(r.swept, 1);
      expect(raw('appt_old_edit')!['_deleted'], 1);
    });

    test('بوابة اليوم: كنستان بنفس اليوم = كنسة واحدة', () async {
      seedAppt('a1', daysFromNow: -10);
      final s = sweeper();
      expect((await s.sweep()).swept, 1);

      seedAppt('a2', daysFromNow: -10);
      expect((await s.sweep()).swept, 0, reason: 'نفس اليوم — البوابة تمنع');

      now = now.add(const Duration(days: 1));
      expect((await s.sweep()).swept, 1, reason: 'يوم جديد — تُلتقط a2');
    });
  });

  group('م71 — الحذف الفعلي للشواهد', () {
    test('يُستدعى بثلاثين يوماً، مرة أسبوعياً', () async {
      final s = sweeper();
      await s.sweep();
      expect(purge.calls, [30]);

      now = now.add(const Duration(days: 3));
      await s.sweep();
      expect(purge.calls, [30], reason: 'قبل أسبوع — لا نداء');

      now = now.add(const Duration(days: 5));
      await s.sweep();
      expect(purge.calls, [30, 30], reason: 'بعد الأسبوع — نداء ثانٍ');
    });

    test('فشل النداء لا يقدّم البوابة — يُعاد بالدورة التالية', () async {
      purge.fail = true;
      final s = sweeper();
      await expectLater(s.sweep(), throwsA(anything));
      purge.fail = false;
      await s.sweep();
      expect(purge.calls, [30], reason: 'أعيد بعد الفشل مباشرة');
    });

    test('الوضع المحلي (بلا منفذ): الكنسة تعمل والحذف الخادمي يصمت', () async {
      seedAppt('a1', daysFromNow: -10);
      final s = RetentionSweeper(ctx: ctx, purge: null, now: () => now);
      final r = await s.sweep();
      expect(r.swept, 1);
      expect(r.purged, isNull);
    });
  });

  group('م71 — الدور بلا مساس', () {
    test('كنسة المواعيد لا تلمس صفوف الدور', () async {
      db.execute(
        'INSERT INTO queue_patients (id, patient_name, date, _mod, _dirty, _deleted, _hlc, data) '
        'VALUES (?,?,?,?,0,0,?,?)',
        [
          'q1',
          'مريض دور',
          dateOf(now.subtract(const Duration(days: 30))),
          now.millisecondsSinceEpoch,
          '${now.millisecondsSinceEpoch}:0:seed',
          jsonEncode({'id': 'q1'}),
        ],
      );
      await sweeper().sweep();
      final q = db.queryFirst(
          'SELECT * FROM queue_patients WHERE id = ?', ['q1']);
      expect(q!['_deleted'], 0,
          reason: 'الدور له تنظيفه اليومي الخاص (م56) — خارج نطاق م71');
    });
  });
}
