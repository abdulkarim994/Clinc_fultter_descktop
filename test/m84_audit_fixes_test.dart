/// اختبارات م84 — إصلاحات التدقيق النهائي العدائي.
///
///  كل مجموعة هنا تحرس عيباً **مُثبَتاً بالتشغيل** كشفته مراجعة عدائية
///  مستقلة، ولها تحكّمٌ يضمن أنها تفشل بلا الإصلاح لا أنها تمرّ لسببٍ خاطئ.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/archive/cold_archive.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:dental_clinic_flutter/data/sync/conflict.dart';
import 'package:dental_clinic_flutter/data/sync/push.dart';
import 'package:dental_clinic_flutter/data/sync/merge/shadow_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'helpers/fake_sync_server.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════
  //  م84/أ — التباعد المالي: تراجع جهازٍ آخر لا يُهمَل (Vane C1)
  // ══════════════════════════════════════════════════════════════════════
  group('م84/أ — تثبيت لقطة الأساس عند الدفع', () {
    late Directory tmp;
    late LocalDb db;
    late Repositories repos;
    late SyncContext ctx;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m84a_');
      db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      repos = Repositories(db);
      ctx = SyncContext(db: db, repos: repos, transport: _Noop());
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Map<String, Object?> sRow(num a, String h, int seq) => {
          'id': 'r1',
          'amount': a,
          'notes': 'x',
          '_fmeta': {'amount': h},
          '_hlc': h,
          '_deleted': 0,
          'server_seq': seq,
        };

    test('الدفع المؤكَّد يقدّم اللقطة إلى القيمة المدفوعة', () {
      mergeRemoteRow(ctx, 'records', sRow(100, '1000:0:A', 1));
      repos.records.upsertLocal({
        'id': 'r1',
        'amount': 250,
        'notes': 'x',
        '_fmeta': {'amount': '2000:0:B'},
        '_hlc': '2000:0:B',
      });
      final pushedHlc = '${repos.records.getById('r1')!['_hlc']}';
      markRowSynced(ctx, 'records', 'r1', 2, pushedHlc);
      expect(getShadow(db, 'records', 'r1')?['amount'], 250,
          reason: 'م84: القيمة المدفوعة صارت الأساس المشترك');
    });

    test('تراجع جهازٍ آخر إلى قيمةٍ قديمة يصل ولا يُهمَل', () {
      mergeRemoteRow(ctx, 'records', sRow(100, '1000:0:A', 1));
      repos.records.upsertLocal({
        'id': 'r1',
        'amount': 250,
        'notes': 'x',
        '_fmeta': {'amount': '2000:0:B'},
        '_hlc': '2000:0:B',
      });
      markRowSynced(
          ctx, 'records', 'r1', 2, '${repos.records.getById('r1')!['_hlc']}');
      mergeRemoteRow(ctx, 'records', sRow(100, '3000:0:A', 3));
      expect(repos.records.getById('r1')!['amount'], 100,
          reason: 'م84/C1: بلا تثبيت اللقطة يبقى 250 — تباعدٌ دائم');
    });

    test('التحكّم: لا يُثبَّت الأساس إن عُدّل الصف بعد الدفع (stillSame)', () {
      mergeRemoteRow(ctx, 'records', sRow(100, '1000:0:A', 1));
      repos.records.upsertLocal({
        'id': 'r1',
        'amount': 250,
        'notes': 'x',
        '_fmeta': {'amount': '2000:0:B'},
        '_hlc': '2000:0:B',
      });
      markRowSynced(ctx, 'records', 'r1', 2, '1:0:stale');
      expect(getShadow(db, 'records', 'r1')?['amount'], isNot(250),
          reason: 'م84: قيمةٌ عُدّل الصف بعدها لا تصير أساساً');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م84/ب — الأرشيف: رأسٌ فاشل عابر لا يُعلَن غياباً فيُدهس الفهرس (Bram C1)
  // ══════════════════════════════════════════════════════════════════════
  group('م84/ب — تمييز غياب الفهرس عن إخفاق قراءته', () {
    test('R2HeadResult: 404 يُميَّز عن الخطأ العابر', () {
      const notFound = R2HeadResult(ok: false, notFound: true);
      const transient = R2HeadResult(ok: false);
      expect(notFound.notFound, isTrue, reason: 'غيابٌ مؤكَّد');
      expect(transient.notFound, isFalse, reason: 'م84: إخفاقٌ عابر ليس غياباً');
    });

    test('جهازٌ جديد + رأسٌ عابر الفشل ⇒ لا يُدهَس الفهرس الموجود', () async {
      final tmp = Directory.systemTemp.createTempSync('m84b_');
      final db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      final repos = Repositories(db);
      final ctx = SyncContext(db: db, repos: repos, transport: _Noop());
      final remote = _FlakyHeadRemote();
      final transport = _CountingArchiveTransport();

      final old = DateTime.now()
          .subtract(const Duration(days: 240))
          .millisecondsSinceEpoch;
      db.execute(
        "INSERT INTO records (id, date, _mod, _dirty, _deleted, _hlc, data) "
        "VALUES ('rec1', '2025-01-01', ?, 0, 0, ?, ?)",
        [old, '$old:0:seed', jsonEncode({'id': 'rec1'})],
      );

      final uid = db.getOwnerUid() ?? 'local';
      final indexKey = 'archive/$uid/index.json';
      final goodIndex = utf8.encode(jsonEncode({
        'bundles': [
          {'key': 'archive/$uid/bundle_OLD.ndjson.gz', 'sha256': 'deadbeef'}
        ]
      }));
      remote.store[indexKey] = Uint8List.fromList(goodIndex);
      remote.indexReadFails = true;
      remote.headTransientError = true;

      final arch = ColdArchive(ctx: ctx, remote: remote, transport: transport);
      await arch.run();

      expect(remote.store[indexKey], orderedEquals(goodIndex),
          reason: 'م84/C1: إخفاق الرأس العابر لا يُبرّر دهس فهرسٍ قائم');
      expect(transport.archiveCalls, 0,
          reason: 'م84: لا حذف خادميّ على مسارٍ أُجهِض');

      db.close();
      tmp.deleteSync(recursive: true);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م84/هـ — ساعة مستقبلية مسمومة لا تحجب التعديلات اللاحقة (Vane HIGH)
  // ══════════════════════════════════════════════════════════════════════
  group('م84/هـ — قصّ الختم المستقبلي عند الخادم', () {
    test('سمٌّ بختم 2100 يُقصّ فيصل تعديلٌ سليمٌ لاحق', () async {
      final server = FakeSyncServer();
      // جهازٌ بعيد بساعة 2100 يدفع الصف مباشرةً (يحفظ ختمه على الخادم).
      const poison = '4102444800000:0:evil';
      await server.applyChanges([
        WireOp(
            opId: 'po',
            entity: 'patients',
            action: 'upsert',
            row: {
              'id': 'p1',
              'name': 'ص',
              'phone': '0911',
              '_fmeta': {'phone': poison},
              '_hlc': poison,
              '_deleted': 0
            },
            pushedHlc: poison),
      ]);
      // الختم المخزَّن قُصّ للحاضر لا 2100.
      final storedMs =
          int.parse('${server.rows['patients']!['p1']!.hlc}'.split(':')[0]);
      final ceiling =
          DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000;
      expect(storedMs <= ceiling, isTrue,
          reason: 'م84: الختم المستقبلي قُصّ إلى الحاضر');

      // جهاز A سليم الساعة يسحب ثم يعدّل الهاتف.
      final tmp = Directory.systemTemp.createTempSync('m84e_');
      final db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      final repos = Repositories(db);
      final eng =
          SyncEngine(SyncContext(db: db, repos: repos, transport: server));
      await eng.runCycle('t');
      repos.patients.upsertLocal({'id': 'p1', 'name': 'ص', 'phone': '0999'});
      await eng.runCycle('t');
      await eng.runCycle('t');

      expect(server.rows['patients']!['p1']!.payload['phone'], '0999',
          reason: 'م84/HIGH: التعديل السليم يصل الخادم لا يُحجَب بالسمّ');
      db.close();
      tmp.deleteSync(recursive: true);
    });

    test('التحكّم: ختمٌ حاضرٌ لا يُقصّ', () async {
      final server = FakeSyncServer();
      final now = DateTime.now().millisecondsSinceEpoch;
      await server.applyChanges([
        WireOp(
            opId: 'ok',
            entity: 'patients',
            action: 'upsert',
            row: {'id': 'p2', 'name': 'س', '_hlc': '$now:0:dev', '_deleted': 0},
            pushedHlc: '$now:0:dev'),
      ]);
      expect('${server.rows['patients']!['p2']!.hlc}', '$now:0:dev',
          reason: 'م84: الختم المعقول يبقى حرفياً');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م84/ج — الأرقام العربية‑الهندية في المال لا تُمحى صفراً (Cade H1)
  // ══════════════════════════════════════════════════════════════════════
  group('م84/ج — طيّ الأرقام العربية عند التحليل', () {
    test('١٥٠٠ تُقرأ 1500 لا صفراً', () {
      expect(jsNumOr0('١٥٠٠'), 1500);
      expect(jsNumOr0('۱۵۰۰'), 1500, reason: 'الفارسية أيضاً');
    });
    test('المختلط والعشري والفاصل', () {
      expect(jsNumOr0('5٥'), 55);
      expect(jsNumOr0('٠٫٥'), 0.5, reason: 'الفاصلة العشرية العربية');
      expect(jsNumOr0('١٬٥٠٠'), 1500, reason: 'فاصل الآلاف يُسقَط');
    });
    test('التحكّم: ASCII لا يتغيّر والفارغ صفر والنص NaN→0', () {
      expect(jsNumOr0('1500'), 1500);
      expect(jsNumber('1500.5'), 1500.5);
      expect(jsNumOr0(''), 0);
      expect(jsNumOr0('كلمة'), 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  م84/د — bulkUpsert يطبّق أسماء الأعمدة كالمفرد (Cade M1)
  // ══════════════════════════════════════════════════════════════════════
  group('م84/د — اتّساق bulkUpsert مع upsert', () {
    test('المفاتيح camelCase تصل الأعمدة الحقيقية لا المدونة وحدها', () {
      final tmp = Directory.systemTemp.createTempSync('m84d_');
      final db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      final repos = Repositories(db);

      repos.debts.bulkUpsert([
        {
          'id': 'd1',
          'patientName': 'مريض',
          'totalAmount': 500,
          'paidAmount': 200,
        }
      ]);

      final col = db.query(
          "SELECT total_amount, paid_amount FROM debts WHERE id='d1'");
      expect(col.first['total_amount'], 500,
          reason: 'م84/M1: العمود الحقيقي لا صفر');
      expect(col.first['paid_amount'], 200);

      db.close();
      tmp.deleteSync(recursive: true);
    });
  });
}

class _Noop implements SyncTransport {
  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// طرفٌ بعيد يحاكي إخفاق قراءة الفهرس ورأسه عابراً بينما هو موجودٌ فعلاً.
class _FlakyHeadRemote implements XrayRemote {
  final store = <String, Uint8List>{};
  bool indexReadFails = false;
  bool headTransientError = false;

  @override
  Future<String> upload(Uint8List bytes, String key,
      {String patientName = '',
      String fileName = '',
      String contentType = 'image/jpeg'}) async {
    store[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async {
    if (indexReadFails && key.endsWith('index.json')) return null;
    return store[key];
  }

  @override
  Future<R2HeadResult> headObject(String key) async {
    if (headTransientError && key.endsWith('index.json')) {
      return const R2HeadResult(ok: false); // عابرٌ: لا ok ولا notFound
    }
    return R2HeadResult(
        ok: store.containsKey(key), notFound: !store.containsKey(key));
  }

  @override
  Future<void> delete(String key) async => store.remove(key);
}

class _CountingArchiveTransport implements ArchiveTransport {
  int archiveCalls = 0;
  @override
  Future<int> archiveRows(List<Map<String, String>> items,
      {required int minAgeDays, int? callerTxid}) async {
    archiveCalls++;
    return items.length;
  }

  @override
  noSuchMethod(Invocation i) => throw UnimplementedError();
}
