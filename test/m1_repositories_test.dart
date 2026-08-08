/// اختبارات مستودعات م1 — الكيانات التسعة فوق القاعدة الحرفية، مع تثبيت
/// المجاميع المالية الشهرية على قيم محسوبة يدوياً (تكافؤ بالسنت).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late LocalDb db;
  late Repositories repos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m1_repos_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    syncFlags.resetForTest();
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
    syncFlags.resetForTest();
  });

  // ═══════════════ stable key derivers ═══════════════
  group('patientKeyFor / clinicKeyFor / clinicScopedKey', () {
    test('legacy mode (flag OFF): TRIM(name) or null', () {
      expect(patientKeyFor(name: '  أحمد الطيب  '), 'أحمد الطيب');
      expect(patientKeyFor(name: '   '), isNull);
      expect(patientKeyFor(), isNull);
      expect(patientIdForName(' خالد '), 'خالد');
    });

    test('phone-identity mode (flag ON): deterministic p:/n: keys', () {
      syncFlags.phoneIdentity = true;
      expect(
        patientKeyFor(name: 'أَحْمَد', phone: '+218 91-234 5678'),
        'p:912345678:احمد',
      );
      expect(patientKeyFor(name: 'مصطفى'), 'n:مصطفي');
      expect(patientKeyFor(), isNull);
    });

    test('clinic keys', () {
      expect(clinicKeyFor('  عيادة الزهراء '), 'عيادة الزهراء');
      expect(clinicKeyFor(null), '');
      expect(
        clinicScopedKey(clinic: ' ع1 ', name: ' أحمد '),
        'ع1|أحمد',
      );
      expect(clinicScopedKey(), isNull);
    });
  });

  // ═══════════════ patients ═══════════════
  group('PatientsRepository', () {
    test('searchByName uses the Arabic-normalised FTS index', () {
      repos.patients.bulkUpsert([
        {'id': 'p1', 'name': 'أحمد الطيّب', 'last_visit': '2026-07-01'},
        {'id': 'p2', 'name': 'خالد المهدي', 'last_visit': '2026-07-02'},
        {'id': 'p3', 'name': 'احمد سالم', 'last_visit': '2026-07-03'},
      ]);
      // normalised query (hamza + tashkeel insensitive) hits both spellings
      final hits = repos.patients.searchByName('أَحْمَد');
      expect(hits.map((r) => r['id']).toSet(), {'p1', 'p3'});
      // empty query → all
      expect(repos.patients.searchByName('  ').length, 3);
      // miss
      expect(repos.patients.searchByName('يوسف'), isEmpty);
    });

    test('cacheFromRecords aggregates last_visit + _mod and stamps keys', () {
      repos.patients.cacheFromRecords(
        [
          {'name': ' أحمد ', 'date': '2026-07-01', '_mod': 5},
          {'name': 'أحمد', 'date': '2026-07-10', '_mod': 3},
        ],
        [
          {'name': 'سالم', 'date': '2026-06-20', '_mod': 9},
        ],
      );
      final ahmed = repos.patients.getById('أحمد')!;
      expect(ahmed['last_visit'], '2026-07-10');
      expect(ahmed['patient_id'], 'أحمد');
      final salem = repos.patients.getById('سالم')!;
      expect(salem['last_visit'], '2026-06-20');
      expect(repos.patients.count(), 2);
    });

    test('getRecentPatients orders by last_visit DESC with limit', () {
      repos.patients.bulkUpsert([
        {'id': 'a', 'name': 'أ', 'last_visit': '2026-01-01'},
        {'id': 'b', 'name': 'ب', 'last_visit': '2026-03-01'},
        {'id': 'c', 'name': 'ج', 'last_visit': '2026-02-01'},
      ]);
      final recent = repos.patients.getRecentPatients(2);
      expect(recent.map((r) => r['id']).toList(), ['b', 'c']);
    });
  });

  // ═══════════════ debts ═══════════════
  group('DebtsRepository', () {
    setUp(() {
      repos.debts.bulkUpsert([
        {
          'id': 'd1',
          'patient_name': 'أحمد',
          'total_amount': 300,
          'paid_amount': 100,
          'remaining': 200,
          'status': 'unpaid',
          'totalAmount': 300,
          'paidAmount': 100,
          'date': '2026-07-05',
        },
        {
          'id': 'd2',
          'patient_name': 'خالد',
          'status': 'paid',
          'total_amount': 50,
          'remaining': 0,
        },
      ]);
    });

    test('getUnpaidDebts / getDebtsByPatient filter correctly', () {
      expect(repos.debts.getUnpaidDebts().single['id'], 'd1');
      expect(repos.debts.getDebtsByPatient('أحمد').single['id'], 'd1');
      expect(repos.debts.getDebtsByPatient('غائب'), isEmpty);
    });

    test('addPayment accumulates, clamps and flips status when settled', () {
      repos.debts.addPayment('d1', 150);
      var d = repos.debts.getById('d1')!;
      expect(d['paidAmount'], 250);
      expect(d['remaining'], 50);
      expect(d['status'], 'unpaid');

      repos.debts.addPayment('d1', 75); // overshoot → clamp + paid
      d = repos.debts.getById('d1')!;
      expect(d['remaining'], 0);
      expect(d['status'], 'paid');
      expect(repos.debts.addPayment('missing', 5), isNull);
    });

    test('markAsPaid', () {
      repos.debts.markAsPaid('d1');
      expect(repos.debts.getById('d1')!['status'], 'paid');
    });

    test('getMonthlyTotals — unpaid debts in month, cent precision', () {
      // d1 (unpaid, blob date 2026-07-05, remaining col 200) counts;
      // d2 paid → excluded; d3 other month → excluded.
      repos.debts.upsert({
        'id': 'd3',
        'patient_name': 'س',
        'status': 'unpaid',
        'remaining': 99,
        'date': '2026-06-01',
      });
      final t = repos.debts.getMonthlyTotals('2026-07')!;
      expect(t.count, 1);
      expect(t.remaining, 200);
      expect(repos.debts.getMonthlyTotals(''), isNull);
    });
  });

  // ═══════════════ records (monthly financial parity fixture) ═══════════════
  group('RecordsRepository.getMonthlyTotals', () {
    setUp(() {
      repos.debts.bulkUpsert([
        {'id': 'dn', 'patient_name': 'أ', 'status': 'unpaid'}, // normal debt
        {
          'id': 'dp',
          'patient_name': 'ب',
          'status': 'unpaid',
          'type': 'prosthetic', // → blob
        },
      ]);
      repos.records.bulkUpsert([
        // r1 normal cash: counts, cash 100
        {
          'id': 'r1', 'patient_name': 'أ', 'date': '2026-07-01',
          'amount': 100, 'payment': 'كاش',
          'isDebt': 0, 'isPros': 0, 'isDebtPayment': 0,
        },
        // r2 transfer with frozen 40% snapshot: doctor 80
        {
          'id': 'r2', 'patient_name': 'ب', 'date': '2026-07-02',
          'amount': 200, 'payment': 'تحويل',
          'isDebt': 0, 'isPros': 0, 'isDebtPayment': 0,
          '_rateSnapshot': {'doctorPct': 40}, // → blob
        },
        // r3 debt-origin row: excluded from income
        {
          'id': 'r3', 'patient_name': 'ج', 'date': '2026-07-03',
          'amount': 500, 'payment': 'دين', 'isDebt': 1,
        },
        // r4 normal-debt payment (cash 50, not in count)
        {
          'id': 'r4', 'patient_name': 'أ', 'date': '2026-07-04',
          'amount': 50, 'payment': 'كاش', 'isDebtPayment': 1, 'debtId': 'dn',
        },
        // r5 PROSTHETIC-debt payment: excluded entirely
        {
          'id': 'r5', 'patient_name': 'ب', 'date': '2026-07-05',
          'amount': 999, 'payment': 'كاش', 'isDebtPayment': 1, 'debtId': 'dp',
        },
      ]);
    });

    test('matches the hand-computed JS aggregate at cent precision', () {
      final t = repos.records.getMonthlyTotals('2026-07')!;
      // income rows: r1, r2 (count) + r4 (payment, uncounted)
      expect(t.count, 2);
      expect(t.cash, 150.0); // 100 + 50
      expect(t.total, 350.0); // 100 + 200 + 50
      expect(t.doctorShare, 155); // 100*.5 + 200*.4 + 50*.5
      expect(t.xfer, 200.0);
      expect(t.clinicShare, 195.0);
    });

    test('month filter + getByMonth + pagination exclusion of prosthetics', () {
      expect(repos.records.getByMonth('2026-07').length, 5);
      expect(repos.records.getByMonth('2026-06'), isEmpty);
      repos.records.upsert({
        'id': 'r6', 'patient_name': 'د', 'date': '2026-07-06',
        'amount': 10, 'isPros': 1,
      });
      final page = repos.records.getRecordsPage(limit: 10);
      expect(page.items.map((r) => r['id']), isNot(contains('r6')));
      final withPros = repos.records.getRecordsPage(limit: 10, includePros: true);
      expect(withPros.items.map((r) => r['id']), contains('r6'));
    });

    test('getByPatientId falls back to empty for blank ids', () {
      expect(repos.records.getByPatientId(''), isEmpty);
      expect(repos.records.getByPatientId(null), isEmpty);
    });
  });

  // ═══════════════ prosthetics (two-part monthly fixture) ═══════════════
  group('ProstheticsRepository.getMonthlyTotals', () {
    setUp(() {
      repos.debts.upsert({
        'id': 'dp2',
        'patient_name': 'ب',
        'status': 'unpaid',
        'type': 'prosthetic',
      });
      repos.prosthetics.bulkUpsert([
        {
          'id': 'p1', 'patient_name': 'أ', 'date': '2026-07-10',
          'total': 500, 'labValue': 200, 'clinicShare': 100,
          'doctorShare': 200, 'payment': 'كاش', 'isDebt': 0,
        },
        {
          'id': 'p2', 'patient_name': 'ب', 'date': '2026-07-11',
          'total': 300, 'labValue': 100, 'clinicShare': 60,
          'doctorShare': 140, 'payment': 'تحويل', 'isDebt': 0,
        },
      ]);
      // legacy-style prosthetic-debt payment row: payment lives in the BLOB
      // (exactly the shape part B of the query reads).
      db.execute(
        "INSERT INTO records (id, date, amount, isDebtPayment, debtId, _deleted, data) "
        "VALUES ('r7', '2026-07-20', 70, 1, 'dp2', 0, '{\"payment\":\"كاش\"}')",
      );
    });

    test('combines table totals with prosthetic-debt payments', () {
      final t = repos.prosthetics.getMonthlyTotals('2026-07')!;
      expect(t.count, 2);
      expect(t.revenue, 800.0);
      expect(t.labCost, 300.0);
      expect(t.profit, 500.0);
      expect(t.clinicShare, 160.0);
      expect(t.pCash, 270.0); // 200 (p1) + 70 (r7)
      expect(t.pXfer, 140.0); // p2
      expect(t.doctorShare, 410.0);
    });

    test('getByMonth respects the prefix', () {
      expect(repos.prosthetics.getByMonth('2026-07').length, 2);
      expect(repos.prosthetics.getByMonth('2025-01'), isEmpty);
    });
  });

  // ═══════════════ appointments ═══════════════
  group('AppointmentsRepository', () {
    setUp(() {
      repos.appointments.bulkUpsert([
        {
          'id': 'a1', 'patient_name': 'أحمد', 'date': '2026-07-20',
          'time': '10:00', 'clinic': 'ع1', 'clinic_id': 'ع1',
          'patient_id': 'أحمد',
        },
        {
          'id': 'a2', 'patient_name': 'خالد', 'date': '2026-07-20',
          'time': '09:00', 'clinic': 'ع1', 'clinic_id': '', // legacy row
        },
        {
          'id': 'a3', 'patient_name': 'أحمد', 'date': '2026-07-21',
          'time': '11:00', 'clinic': 'ع2', 'clinic_id': 'ع2',
        },
      ]);
    });

    test('getByDate orders by time; range and count work', () {
      final day = repos.appointments.getByDate('2026-07-20');
      expect(day.map((r) => r['id']).toList(), ['a2', 'a1']);
      expect(
        repos.appointments.getByDateRange('2026-07-20', '2026-07-21').length,
        3,
      );
      expect(repos.appointments.countByDate('2026-07-20'), 2);
    });

    test('getByClinicDate self-heals legacy rows without clinic_id', () {
      final rows = repos.appointments.getByClinicDate('ع1', '2026-07-20');
      expect(rows.map((r) => r['id']).toSet(), {'a1', 'a2'});
      // empty clinic → global day list
      expect(
        repos.appointments.getByClinicDate('', '2026-07-20').length,
        2,
      );
    });

    test('getByPatientId matches stable key OR legacy trimmed name', () {
      final rows = repos.appointments.getByPatientId('أحمد');
      expect(rows.map((r) => r['id']).toSet(), {'a1', 'a3'});
      expect(repos.appointments.getByPatientId('  '), isEmpty);
    });

    test('getUpcoming returns today-and-future only', () {
      repos.appointments.upsert({
        'id': 'future', 'patient_name': 'س', 'date': '2999-01-01',
        'time': '08:00',
      });
      final up = repos.appointments.getUpcoming();
      expect(up.map((r) => r['id']), contains('future'));
      expect(up.map((r) => r['id']), isNot(contains('a1'))); // past
    });

    test('cacheFromSupabase maps fields, derives keys, keeps full blob', () {
      repos.appointments.cacheFromSupabase([
        {
          'id': 'srv1',
          'name': 'سالم',
          'phone': '0911111111',
          'date': '2026-08-01',
          'time': '12:00',
          'service': 'فحص',
          'clinic': ' ع3 ',
          'serverOnlyField': 'kept',
        },
      ]);
      final row = repos.appointments.getById('srv1')!;
      expect(row['patient_name'], 'سالم');
      expect(row['status'], 'pending');
      expect(row['clinic_id'], 'ع3'); // derived via clinicKeyFor
      expect(row['patient_id'], 'سالم'); // legacy TRIM(name) key
      expect(row['serverOnlyField'], 'kept'); // preserved through the blob
    });
  });

  // ═══════════════ xrays ═══════════════
  group('XraysRepository', () {
    test('addXray stamps stable keys and pending status', () {
      final x = repos.xrays.addXray('أحمد', 'key1',
          thumbnailData: 'thumb1', clinic: ' ع1 ');
      expect(x['clinic_id'], 'ع1');
      expect(x['patient_id'], 'أحمد');
      expect(repos.xrays.getPendingUploads().single['id'], 'key1');
      expect(repos.xrays.countByPatient('أحمد'), 1);
    });

    test('thumbnail save / get / remove', () {
      repos.xrays.addXray('أحمد', 'key1');
      repos.xrays.saveThumbnail('key1', 'DATAURL');
      expect(repos.xrays.getThumbnail('key1'), 'DATAURL');
      repos.xrays.removeThumbnail('key1');
      expect(repos.xrays.getThumbnail('key1'), isNull);
    });

    test('markUploaded COALESCEs file_key/checksum and marks dirty', () {
      repos.xrays.addXray('أحمد', 'key1');
      repos.xrays.markUploaded('key1', checksum: 'sha');
      final raw = db.queryFirst('SELECT * FROM xrays WHERE id = ?', ['key1'])!;
      expect(raw['upload_status'], 'uploaded');
      expect(raw['file_key'], 'key1'); // kept (COALESCE with null)
      expect(raw['checksum'], 'sha');
      expect(raw['_dirty'], 1);
      expect(repos.xrays.getPendingUploads(), isEmpty);
    });

    test('cleanup NEVER drops the only copy of an un-uploaded image', () {
      repos.xrays.addXray('أ', 'pendingKey', thumbnailData: 't1');
      repos.xrays.addXray('أ', 'uploadedKey', thumbnailData: 't2');
      repos.xrays.markUploaded('uploadedKey');
      // age both rows far beyond the cutoff
      db.execute('UPDATE xrays SET _mod = 1');
      repos.xrays.cleanupOldThumbnails();
      expect(repos.xrays.getThumbnail('pendingKey'), 't1'); // survived
      expect(repos.xrays.getThumbnail('uploadedKey'), isNull); // cleaned
    });

    test('getByClinicPatient self-heals rows with NULL keys', () {
      repos.xrays.addXray('أحمد', 'k1', clinic: 'ع1');
      db.execute(
        "INSERT INTO xrays (id, patient_name, file_key, upload_status, _deleted) "
        "VALUES ('legacy', 'أحمد', 'legacy', 'pending', 0)",
      );
      final rows = repos.xrays.getByClinicPatient('ع1', 'أحمد');
      expect(rows.map((r) => r['id']).toSet(), {'k1', 'legacy'});
    });
  });

  // ═══════════════ queue ═══════════════
  group('QueueRepository', () {
    setUp(() {
      repos.queue.bulkUpsert([
        {
          'id': 'q1', 'clinic': 'ع1', 'date': '2026-07-26',
          'period': 'morning', 'seq': 2, 'patient_name': 'أ',
          'state': 'waiting',
        },
        {
          'id': 'q2', 'clinic': 'ع1', 'date': '2026-07-26',
          'period': 'morning', 'seq': 1, 'patient_name': 'ب',
          'state': 'waiting',
        },
        {
          'id': 'q3', 'clinic': 'ع1', 'date': '2026-07-26',
          'period': 'evening', 'seq': 1, 'patient_name': 'ج',
          'state': 'done', 'archive_seq': 1,
        },
        {
          'id': 'old', 'clinic': 'ع1', 'date': '2026-07-01',
          'period': 'morning', 'seq': 1, 'patient_name': 'قديم',
        },
        {
          'id': 'fut', 'clinic': 'ع1', 'date': '2026-07-30',
          'period': 'morning', 'seq': 1, 'patient_name': 'قادم',
        },
      ]);
    });

    test('getByClinicDate orders by period, state, seq', () {
      final rows = repos.queue.getByClinicDate('ع1', '2026-07-26');
      expect(rows.map((r) => r['id']).toList(), ['q3', 'q2', 'q1']);
    });

    test('getUpcomingDates returns sorted distinct future dates', () {
      expect(repos.queue.getUpcomingDates('2026-07-26'), ['2026-07-30']);
    });

    test('purgeOlderThan tombstones stale rows with sync stamps', () {
      final n = repos.queue.purgeOlderThan('2026-07-26');
      expect(n, 1);
      final raw =
          db.queryFirst('SELECT * FROM queue_patients WHERE id = ?', ['old'])!;
      expect(raw['_deleted'], 1);
      expect(raw['_dirty'], 1);
      expect(raw['_hlc'], isNotNull);
      expect(
        repos.queue.getByClinicDate('ع1', '2026-07-01'),
        isEmpty,
      );
    });
  });

  // ═══════════════ settings + config ═══════════════
  group('SettingsRepository', () {
    test('set/get round-trips JSON values and getAll flattens', () {
      repos.settings.set('clinic.name', 'عيادة الزهراء');
      repos.settings.set('rates', {'doctorPct': 40});
      expect(repos.settings.get('clinic.name'), 'عيادة الزهراء');
      expect((repos.settings.get('rates') as Map)['doctorPct'], 40);
      final all = repos.settings.getAll();
      expect(all.keys.toSet(), {'clinic.name', 'rates'});
      expect(repos.settings.get('missing'), isNull);
    });

    test('set marks the row dirty for the sync engine', () {
      repos.settings.set('k', 'v');
      final raw =
          db.queryFirst('SELECT * FROM settings WHERE id = ?', ['k'])!;
      expect(raw['_dirty'], 1);
    });

    test('setBaseline seeds only gaps, non-dirty, sentinel HLC', () {
      repos.settings.setBaseline('clinic.name', 'افتراضي');
      var raw =
          db.queryFirst('SELECT * FROM settings WHERE id = ?', ['clinic.name'])!;
      expect(raw['_dirty'], 0);
      expect(raw['_hlc'], seedHlc);

      // a real value overwrites…
      repos.settings.set('clinic.name', 'الاسم الحقيقي');
      // …and a later baseline can NEVER clobber it
      repos.settings.setBaseline('clinic.name', 'افتراضي');
      raw = db
          .queryFirst('SELECT * FROM settings WHERE id = ?', ['clinic.name'])!;
      expect(repos.settings.get('clinic.name'), 'الاسم الحقيقي');
      expect(raw['_dirty'], 1);
    });
  });

  test('ConfigRepository round-trips the clinic config blob', () {
    expect(repos.config.getConfig(), isNull);
    repos.config.saveConfig({'clinics': ['ع1', 'ع2'], 'fs': 1});
    final cfg = repos.config.getConfig() as Map;
    expect(cfg['clinics'], ['ع1', 'ع2']);
  });
}
