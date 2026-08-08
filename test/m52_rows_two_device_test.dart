/// اختبار م52 (v31) — فحص بقية الأقسام تحت التعديل المتزامن من جهازين:
/// السجلات، الديون، المواعيد، المختبرات (التركيبات)، والأشعة.
/// جهازان حقيقيان (قاعدتا SQLite) عبر خادم بدلالات الخلفية نفسها.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m52_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine = SyncEngine(
        SyncContext(db: db, repos: repos, transport: server));
  }

  final String name;
  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncEngine engine;

  Future<void> sync() async {
    await engine.runCycle('test');
  }

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  late FakeSyncServer server;
  late Device a;
  late Device b;

  setUp(() {
    server = FakeSyncServer();
    a = Device('a', server);
    b = Device('b', server);
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await a.sync();
      await b.sync();
    }
  }

  test('السجلات: تعديل حقلين مختلفين من جهازين ⇒ الاثنان ينجوان', () async {
    a.repos.records.upsertLocal({
      'id': 'r1', 'name': 'سالم', 'patient_name': 'سالم',
      'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
      'amount': 100, 'payment': 'كاش', 'notes': '',
    });
    await settle();
    expect(b.repos.records.getById('r1'), isNotNull);

    // كل جهاز يعدّل حقلاً مختلفاً من **لقطته** (سلوك نافذة التعديل).
    final snapA = Map<String, Object?>.from(a.repos.records.getById('r1')!);
    final snapB = Map<String, Object?>.from(b.repos.records.getById('r1')!);
    a.repos.records.upsertLocal({...snapA, 'amount': 250}, base: snapA);
    b.repos.records.upsertLocal({...snapB, 'payment': 'تحويل'}, base: snapB);
    await settle();

    for (final d in [a, b]) {
      final r = d.repos.records.getById('r1')!;
      expect(r['amount'], 250, reason: '${d.name}: تعديل A نجا');
      expect(r['payment'], 'تحويل', reason: '${d.name}: تعديل B نجا');
    }
  });

  test('الديون: دفعة من كل جهاز ⇒ الدفعتان محفوظتان', () async {
    a.repos.debts.upsertLocal({
      'id': 'd1', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'service': 'تركيبة', 'date': '2026-07-20',
      'amount': 1000, 'total': 1000, 'totalAmount': 1000,
      'paidAmount': 0, 'remaining': 1000, 'status': 'unpaid',
      'installments': <Object?>[],
    });
    await settle();

    final snapA = Map<String, Object?>.from(a.repos.debts.getById('d1')!);
    final snapB = Map<String, Object?>.from(b.repos.debts.getById('d1')!);
    a.repos.debts.upsertLocal({
      ...snapA,
      'paidAmount': 300,
      'remaining': 700,
      'installments': [
        {'id': 'i1', 'amount': 300, 'date': '2026-07-21'},
      ],
    }, base: snapA);
    b.repos.debts.upsertLocal({
      ...snapB,
      'paidAmount': 200,
      'remaining': 800,
      'installments': [
        {'id': 'i2', 'amount': 200, 'date': '2026-07-22'},
      ],
    }, base: snapB);
    await settle();

    for (final d in [a, b]) {
      final row = d.repos.debts.getById('d1')!;
      final inst = (row['installments'] as List)
          .whereType<Map>()
          .where((m) => m['_deleted'] != 1)
          .map((m) => '${m['id']}')
          .toSet();
      expect(inst, {'i1', 'i2'},
          reason: '${d.name}: دفعتا الجهازين محفوظتان');
      // إعادة الحساب بعد الدمج توحّد المجاميع من الأقساط نفسها.
      expect(row['paidAmount'], 500,
          reason: '${d.name}: المدفوع = مجموع الدفعتين (إعادة حساب)');
      expect(row['remaining'], 500,
          reason: '${d.name}: المتبقي محسوب من المجموع');
      expect(row['status'], 'partial');
    }
  });

  test('المواعيد: وقت من جهاز وحالة من الآخر ⇒ الاثنان', () async {
    a.repos.appointments.upsertLocal({
      'id': 'ap1', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'date': '2026-07-30', 'time': '10:00', 'status': 'pending',
      'notes': '',
    });
    await settle();

    final snapA =
        Map<String, Object?>.from(a.repos.appointments.getById('ap1')!);
    final snapB =
        Map<String, Object?>.from(b.repos.appointments.getById('ap1')!);
    a.repos.appointments.upsertLocal({...snapA, 'time': '12:30'},
        base: snapA);
    b.repos.appointments.upsertLocal({...snapB, 'status': 'done'},
        base: snapB);
    await settle();

    for (final d in [a, b]) {
      final r = d.repos.appointments.getById('ap1')!;
      expect(r['time'], '12:30', reason: '${d.name}: وقت A نجا');
      expect(r['status'], 'done', reason: '${d.name}: حالة B نجت');
    }
  });

  test('المختبرات (التركيبات): حالة من جهاز وتكلفة من الآخر', () async {
    a.repos.prosthetics.upsertLocal({
      'id': 'pr1', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'type': 'زيركون', 'lab': 'مختبر أ', 'date': '2026-07-20',
      'amount': 500, 'labCost': 200, 'status': 'sent',
    });
    await settle();

    final snapA =
        Map<String, Object?>.from(a.repos.prosthetics.getById('pr1')!);
    final snapB =
        Map<String, Object?>.from(b.repos.prosthetics.getById('pr1')!);
    a.repos.prosthetics.upsertLocal({...snapA, 'status': 'received'},
        base: snapA);
    b.repos.prosthetics.upsertLocal({...snapB, 'labCost': 260},
        base: snapB);
    await settle();

    for (final d in [a, b]) {
      final r = d.repos.prosthetics.getById('pr1')!;
      expect(r['status'], 'received', reason: '${d.name}: حالة A نجت');
      expect(r['labCost'], 260, reason: '${d.name}: تكلفة B نجت');
    }
  });

  test('الأشعة: صورة من كل جهاز ⇒ الاثنتان + وسم من جهاز ينجو', () async {
    a.repos.xrays.upsertLocal({
      'id': 'x1', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'key': 'k1', 'label': 'قبل', 'date': '2026-07-20',
    });
    await settle();

    // كل جهاز يضيف صورة، وB يعدّل وسم صورة A في الوقت نفسه.
    a.repos.xrays.upsertLocal({
      'id': 'x2', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'key': 'k2', 'label': 'بعد', 'date': '2026-07-21',
    });
    final snapB = Map<String, Object?>.from(b.repos.xrays.getById('x1')!);
    b.repos.xrays.upsertLocal({...snapB, 'label': 'قبل العلاج'},
        base: snapB);
    b.repos.xrays.upsertLocal({
      'id': 'x3', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'key': 'k3', 'label': 'أشعة ب', 'date': '2026-07-22',
    });
    await settle();

    for (final d in [a, b]) {
      final ids = (d.repos.xrays.getAll() as List)
          .whereType<Map>()
          .map((m) => '${m['id']}')
          .toSet();
      expect(ids, {'x1', 'x2', 'x3'},
          reason: '${d.name}: صور الجهازين كلها موجودة');
      expect(d.repos.xrays.getById('x1')!['label'], 'قبل العلاج',
          reason: '${d.name}: وسم B نجا');
    }
  });

  test('الحذف على جهاز مع تعديل على الآخر: الحذف يصمد بلا بعث', () async {
    a.repos.records.upsertLocal({
      'id': 'r9', 'name': 'سالم', 'patient_name': 'سالم', 'clinic': 'ع1',
      'service': 'حشو', 'date': '2026-07-20', 'amount': 100,
      'payment': 'كاش',
    });
    await settle();

    a.repos.records.delete('r9');
    final snapB = Map<String, Object?>.from(b.repos.records.getById('r9')!);
    b.repos.records.upsertLocal({...snapB, 'amount': 999}, base: snapB);
    await settle();
    await settle();

    for (final d in [a, b]) {
      expect(d.repos.records.getById('r9'), isNull,
          reason: '${d.name}: الحذف صمد ولم يُبعث بتعديل الآخر');
    }
  });
}
