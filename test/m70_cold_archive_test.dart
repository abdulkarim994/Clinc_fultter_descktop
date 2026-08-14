/// اختبارات م70 — الأرشفة الباردة: الانتقاء، الفشل المغلق، العلامة المائية،
/// والاسترجاع النظيف.
///
/// المبدأ المُختبَر: **لا حذف قبل إثبات وصول الحزمة** — أي فشل في الرفع أو
/// فساد في إعادة القراءة يجب أن يوقف الخط كاملاً بلا أي نداء حذف، وبلا
/// تقديم للعلامة المائية (كي تُلتقط الصفوف نفسها في المحاولة التالية).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/archive/cold_archive.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/db_sync.dart' show setMetaValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

/// طرف R2 مزيف في الذاكرة — بأعطاب قابلة للحقن.
class FakeRemote implements XrayRemote {
  final store = <String, Uint8List>{};
  bool failUpload = false;
  bool corruptEcho = false;
  int uploads = 0;

  @override
  Future<String> upload(Uint8List bytes, String key,
      {String patientName = '',
      String fileName = '',
      String contentType = 'image/jpeg'}) async {
    if (failUpload) throw Exception('upload down');
    uploads++;
    store[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async {
    final b = store[key];
    if (b == null) return null;
    if (corruptEcho && key.endsWith('.ndjson.gz')) {
      final c = Uint8List.fromList(b);
      c[0] = c[0] ^ 0xFF; // قلب بت — بصمة مختلفة
      return c;
    }
    return b;
  }

  @override
  Future<R2HeadResult> headObject(String key) async =>
      // مطابقٌ لدلالة R2 الحقيقية: كائنٌ غائب ⇒ 404 ⇒ notFound صريح.
      R2HeadResult(
          ok: store.containsKey(key),
          size: store[key]?.length,
          notFound: !store.containsKey(key));

  @override
  Future<void> delete(String key) async => store.remove(key);
}

/// ناقل أرشفة مزيف — يسجّل الطلبات ويحاكي حذف الخادم.
class FakeArchiveTransport implements ArchiveTransport {
  final calls = <({List<Map<String, String>> items, int minAge, int? txid})>[];
  final reports = <({String device, int cursor})>[];
  bool fail = false;

  @override
  Future<int> archiveRows(List<Map<String, String>> items,
      {required int minAgeDays, int? callerTxid}) async {
    if (fail) throw Exception('rpc down');
    calls.add((items: List.of(items), minAge: minAgeDays, txid: callerTxid));
    return items.length;
  }

  @override
  Future<void> reportSyncState(String deviceId, int cursorTxid) async {
    reports.add((device: deviceId, cursor: cursorTxid));
  }
}

void main() {
  late Directory tmp;
  late LocalDb db;
  late Repositories repos;
  late SyncContext ctx;
  late FakeRemote remote;
  late FakeArchiveTransport transport;

  final now = DateTime(2026, 7, 30, 12);
  int daysAgoMs(int d) =>
      now.subtract(Duration(days: d)).millisecondsSinceEpoch;
  String daysAgoDate(int d) {
    final t = now.subtract(Duration(days: d));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m70_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    ctx = SyncContext(db: db, repos: repos, transport: FakeSyncServer());
    remote = FakeRemote();
    transport = FakeArchiveTransport();
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  ColdArchive arch() => ColdArchive(
      ctx: ctx, remote: remote, transport: transport, now: () => now);

  /// بذر صف مباشرة بالأعمدة الحاسمة (تجاوز upsertLocal كي لا يُختم اتساخاً).
  /// `patients` بلا عمود date في المخطط المحلي — يُبذر بدونه.
  void seed(String table, String id,
      {required int modDaysAgo,
      String? date,
      int dirty = 0,
      int deleted = 0,
      Map<String, Object?> extra = const {}}) {
    // عمود التاريخ موجود في records/appointments فقط؛ patients يحتاج name
    // (NOT NULL)، وdebts تاريخه داخل data لا عموداً.
    final second = switch (table) {
      'records' || 'appointments' => ('date', date),
      'patients' => ('name', 'مريض $id'),
      _ => ('patient_name', 'مريض $id'),
    };
    db.execute(
      'INSERT INTO $table (id, ${second.$1}, _mod, _dirty, '
      '_deleted, _hlc, data) VALUES (?,?,?,?,?,?,?)',
      [
        id,
        second.$2,
        daysAgoMs(modDaysAgo),
        dirty,
        deleted,
        '${daysAgoMs(modDaysAgo)}:0:seed',
        jsonEncode({'id': id, ...extra}),
      ],
    );
  }

  void seedXray(String id, {required int modDaysAgo, int dirty = 0}) {
    db.execute(
      'INSERT INTO xrays (id, file_key, thumbnail_data, upload_status, _mod, '
      '_dirty, _deleted, _hlc, data) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        id,
        'xrays/u/$id.jpg',
        'data:image/jpeg;base64,QUJD', // مصغّرة محلية — يجب ألا تدخل الحزمة
        'uploaded',
        daysAgoMs(modDaysAgo),
        dirty,
        0,
        '${daysAgoMs(modDaysAgo)}:0:seed',
        jsonEncode({'id': id, 'file_key': 'xrays/u/$id.jpg'}),
      ],
    );
  }

  group('م70 — الانتقاء', () {
    test('النوافذ والكيانات المحظورة والمتسخ والمستقبلي', () {
      seed('records', 'rec_old', modDaysAgo: 240, date: daysAgoDate(240));
      seed('records', 'rec_new', modDaysAgo: 30, date: daysAgoDate(30));
      seed('records', 'rec_dirty',
          modDaysAgo: 240, date: daysAgoDate(240), dirty: 1);
      seed('records', 'rec_tomb',
          modDaysAgo: 240, date: daysAgoDate(240), deleted: 1);
      // موعد قديم التعديل لكن تاريخه مستقبلي ⇒ ممنوع
      seed('appointments', 'appt_future',
          modDaysAgo: 200, date: '2027-01-01');
      seed('appointments', 'appt_old',
          modDaysAgo: 200, date: daysAgoDate(200));
      seed('appointments', 'appt_recent',
          modDaysAgo: 60, date: daysAgoDate(60));
      seedXray('xr_old', modDaysAgo: 300);
      // كيانات محظورة — قديمة جداً ويجب ألا تُلتقط أصلاً
      seed('patients', 'pat_old', modDaysAgo: 400);
      seed('debts', 'debt_old', modDaysAgo: 400, date: daysAgoDate(400));

      final items = arch().selectEligible();
      final ids = {for (final it in items) '${it.entity}:${it.row['id']}'};

      expect(
          ids,
          equals({
            'records:rec_old',
            'records:rec_tomb', // شاهد قبر قديم يُؤرشف — واعٍ ومقصود
            'appointments:appt_old',
            'xrays:xr_old',
          }));
    });

    test('صف بلا _mod (صفر) لا يُلتقط — قِدمه غير مثبَت', () {
      seed('records', 'rec_nomod', modDaysAgo: 0, date: daysAgoDate(300));
      db.execute('UPDATE records SET _mod = 0 WHERE id = ?', ['rec_nomod']);
      expect(arch().selectEligible(), isEmpty);
    });
  });

  group('م70 — الفشل المغلق', () {
    setUp(() =>
        seed('records', 'rec_old', modDaysAgo: 240, date: daysAgoDate(240)));

    test('فشل الرفع ⇒ لا نداء حذف ولا تقدم للعلامة المائية', () async {
      remote.failUpload = true;
      final a = arch();
      final r = await a.run();
      expect(r.ok, isFalse);
      expect(transport.calls, isEmpty, reason: 'لا حذف بلا حزمة');
      // المحاولة التالية تلتقط الصف نفسه
      remote.failUpload = false;
      final r2 = await a.run();
      expect(r2.ok, isTrue);
      expect(transport.calls.single.items.single['id'], 'rec_old');
    });

    test('فساد إعادة القراءة (بصمة مختلفة) ⇒ لا حذف', () async {
      remote.corruptEcho = true;
      final r = await arch().run();
      expect(r.ok, isFalse);
      expect(r.reason, contains('لم تُقرأ مطابقةً'));
      expect(transport.calls, isEmpty);
    });

    test('فشل RPC بعد رفع سليم ⇒ فشل مبلَّغ والعلامة لم تتقدم', () async {
      transport.fail = true;
      final a = arch();
      final r = await a.run();
      expect(r.ok, isFalse);
      transport.fail = false;
      final r2 = await a.run();
      expect(r2.ok, isTrue, reason: 'إعادة المحاولة آمنة (idempotent خادمياً)');
      expect(transport.calls.single.items.single['id'], 'rec_old');
    });
  });

  group('م70 — النجاح والمحتوى', () {
    test('الحزمة NDJSON مضغوطة، بلا مصغّرات ولا أعلام داخلية، والفهرس مثبت',
        () async {
      seed('records', 'rec_old', modDaysAgo: 240, date: daysAgoDate(240));
      seedXray('xr_old', modDaysAgo: 300);

      final r = await arch().run();
      expect(r.ok, isTrue);
      expect(r.archived, 2);

      // الفهرس
      final idxRaw = remote.store.keys.where((k) => k.endsWith('index.json'));
      expect(idxRaw, hasLength(1));
      final idx =
          jsonDecode(utf8.decode(remote.store[idxRaw.single]!)) as Map;
      final entry = (idx['bundles'] as List).single as Map;
      expect(entry['rows'], 2);

      // الحزمة نفسها
      final bundleKey = '${entry['key']}';
      final lines = const LineSplitter()
          .convert(utf8.decode(gzip.decode(remote.store[bundleKey]!)));
      expect(lines, hasLength(2));
      for (final l in lines) {
        final row = (jsonDecode(l) as Map)['row'] as Map;
        expect(row.containsKey('thumbnail_data'), isFalse,
            reason: 'المصغّرة لا تدخل الحزم أبداً');
        expect(row.containsKey('_dirty'), isFalse);
        expect(row.containsKey('data'), isFalse);
        expect(row['_hlc'], isNotNull, reason: 'HLC يسافر للاسترجاع');
      }
    });

    test('التشغيل الثاني لا يعيد رفع المؤرشَف (العلامة المائية)', () async {
      seed('records', 'rec_old', modDaysAgo: 240, date: daysAgoDate(240));
      final a = arch();
      expect((await a.run()).archived, 1);
      expect(remote.uploads, 2, reason: 'حزمة + فهرس');

      final r2 = await a.run();
      expect(r2.ok, isTrue);
      expect(r2.archived, 0, reason: 'لا صفوف جديدة مؤهلة');
      expect(remote.uploads, 2, reason: 'لا رفع جديداً');
      expect(transport.calls, hasLength(1));
    });

    test('تعديل صف مؤرشَف يعيده للانتقاء حين يقدُم ثانيةً', () async {
      seed('records', 'rec_old', modDaysAgo: 240, date: daysAgoDate(240));
      final a = arch();
      await a.run();

      // «تعديل» يرفع _mod فوق العلامة المائية لكنه حديث ⇒ لا يُلتقط
      db.execute('UPDATE records SET _mod = ? WHERE id = ?',
          [daysAgoMs(5), 'rec_old']);
      expect(a.selectEligible(), isEmpty);

      // يقدُم ثانيةً (فوق العلامة وتحت القاطع) ⇒ يُلتقط من جديد
      db.execute('UPDATE records SET _mod = ? WHERE id = ?',
          [daysAgoMs(215), 'rec_old']);
      expect(a.selectEligible().single.row['id'], 'rec_old');
    });
  });

  m73();

  group('م70 — الاسترجاع', () {
    test('يملأ الناقص نظيفاً، لا يمسّ الأحدث، ويطبّق شواهد القبور', () async {
      // الجهاز الأول يؤرشف ثلاثة أنواع
      seed('records', 'rec_a', modDaysAgo: 240, date: daysAgoDate(240),
          extra: {'service': 'حشو', 'amount': 100});
      seed('records', 'rec_tomb',
          modDaysAgo: 240, date: daysAgoDate(240), deleted: 1);
      seed('appointments', 'appt_a',
          modDaysAgo: 200, date: daysAgoDate(200));
      final r = await arch().run();
      expect(r.archived, 3);

      // جهاز جديد فارغ يشارك نفس R2
      final tmp2 = Directory.systemTemp.createTempSync('m70_b_');
      addTearDown(() => tmp2.deleteSync(recursive: true));
      final db2 = LocalDb.open(p.join(tmp2.path, 'dental_clinic_offline.db'));
      addTearDown(db2.close);
      final repos2 = Repositories(db2);
      final ctx2 =
          SyncContext(db: db2, repos: repos2, transport: FakeSyncServer());
      // صف محلي أحدث بنفس معرف مؤرشَف — يجب ألا يُكتب فوقه
      repos2.records.upsertLocal({
        'id': 'rec_a',
        'service': 'تعديل أحدث',
        'date': daysAgoDate(240),
      });
      final before = repos2.records.getById('rec_a')!;

      final res = await ColdArchive(
              ctx: ctx2, remote: remote, transport: FakeArchiveTransport(),
              now: () => now)
          .restore();
      expect(res.ok, isTrue);
      expect(res.bundles, 1);

      // الموعد وصل نظيفاً
      final appt = db2.queryFirst(
          'SELECT * FROM appointments WHERE id = ?', ['appt_a']);
      expect(appt, isNotNull);
      expect(appt!['_dirty'], anyOf(0, isNull),
          reason: 'الترطيب نظيف — لا يعاد دفعه');

      // شاهد القبر طُبِّق
      final tomb =
          db2.queryFirst('SELECT * FROM records WHERE id = ?', ['rec_tomb']);
      expect(tomb, isNotNull);
      expect(tomb!['_deleted'], 1);

      // الأحدث المحلي صمد (HLC المحلي أحدث من المؤرشَف)
      final after = repos2.records.getById('rec_a')!;
      expect(after['service'], before['service'],
          reason: 'mergeRemoteRow لا يكتب فوق الأحدث');
    });

    test('حزمة فاسدة تُتخطى وتُبلَّغ ولا تفسد البقية', () async {
      seed('records', 'rec_a', modDaysAgo: 240, date: daysAgoDate(240));
      await arch().run();
      // إفساد الحزمة الوحيدة
      final bk =
          remote.store.keys.firstWhere((k) => k.endsWith('.ndjson.gz'));
      remote.store[bk] = Uint8List.fromList([1, 2, 3]);

      final res = await arch().restore();
      expect(res.ok, isFalse);
      expect(res.skippedBundles, 1);
      expect(res.reason, contains('تعذّرت'));
    });
  });
}

/// ═══ م73 — النافذة 90 يوماً + التبليغ اليومي + الاسترجاع التلقائي ═══
void m73() {
  late Directory tmp;
  late LocalDb db;
  late Repositories repos;
  late SyncContext ctx;
  late FakeRemote remote;
  late FakeArchiveTransport transport;
  var now = DateTime(2026, 7, 30, 12);

  int daysAgoMs(int d) =>
      now.subtract(Duration(days: d)).millisecondsSinceEpoch;
  String daysAgoDate(int d) {
    final t = now.subtract(Duration(days: d));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m73_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    ctx = SyncContext(db: db, repos: repos, transport: FakeSyncServer());
    remote = FakeRemote();
    transport = FakeArchiveTransport();
    now = DateTime(2026, 7, 30, 12);
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  ColdArchive arch() => ColdArchive(
      ctx: ctx, remote: remote, transport: transport, now: () => now);

  void seedRec(String id, int modDaysAgo) => db.execute(
        'INSERT INTO records (id, date, _mod, _dirty, _deleted, _hlc, data) '
        'VALUES (?,?,?,0,0,?,?)',
        [
          id,
          daysAgoDate(modDaysAgo),
          daysAgoMs(modDaysAgo),
          '${daysAgoMs(modDaysAgo)}:0:s',
          jsonEncode({'id': id}),
        ],
      );

  group('م179 — النافذة 180 يوماً ثابتة', () {
    test('صف 200 يوم يُلتقط و100 يوماً لا (النافذة 180)', () {
      seedRec('r200d', 200);
      seedRec('r100d', 100);
      final ids = {for (final it in arch().selectEligible()) it.row['id']};
      expect(ids, {'r200d'});
    });

    // م179 — النافذة صارت **ثابتة 180 يوماً** (قرار المالك: ستة أشهر
    // بلا تحكم مستخدم): زال الضابط، فنتحقق من الرقم الثابت وأثره على
    // الانتقاء بدل التحقق من قابلية الضبط.
    test('النافذة ثابتة 180 يوماً ولا تُضبَط', () {
      final a = arch();
      expect(a.windowDays, 180);
      expect(ColdArchive.kFixedWindowDays, 180);
    });

    test('الأرشفة مفعّلة دائماً بلا مفتاح تحكم', () {
      expect(arch().enabled, isTrue);
    });
  });

  group('م73 — التبليغ اليومي بالمؤشر', () {
    test('يبلّغ مرة يومياً بمعرّف الجهاز ومؤشره', () async {
      setMetaValue(db, 'sync.cursor.txid', '4242');
      final a = arch();
      await a.reportStateIfDue();
      expect(transport.reports, hasLength(1));
      expect(transport.reports.single.cursor, 4242);
      expect(transport.reports.single.device, ctx.deviceId);

      await a.reportStateIfDue();
      expect(transport.reports, hasLength(1), reason: 'نفس اليوم — لا تكرار');

      now = now.add(const Duration(days: 1));
      await a.reportStateIfDue();
      expect(transport.reports, hasLength(2), reason: 'يوم جديد');
    });

    test('المؤشر يُمرَّر لنداء الأرشفة (حارس الخادم)', () async {
      setMetaValue(db, 'sync.cursor.txid', '777');
      seedRec('r200d', 200); // م179 — نافذة 180 يوماً
      await arch().run();
      expect(transport.calls.single.txid, 777);
    });
  });

  group('م73 — الاسترجاع التلقائي عند الفجوة', () {
    test('مؤشر تحت الأفق ⇒ استرجاع تلقائي مرة واحدة لكل أفق', () async {
      // حساب أرشف سابقاً ⇒ توجد حزمة على R2
      seedRec('r200d', 200); // م179 — نافذة 180 يوماً
      await arch().run();
      final bundles = remote.store.keys.where((k) => k.endsWith('.gz')).length;
      expect(bundles, 1);

      // جهاز جديد: مؤشره 0 والأفق 500 ⇒ فجوة
      final tmp2 = Directory.systemTemp.createTempSync('m73b_');
      addTearDown(() => tmp2.deleteSync(recursive: true));
      final db2 = LocalDb.open(p.join(tmp2.path, 'dental_clinic_offline.db'));
      addTearDown(db2.close);
      final ctx2 = SyncContext(
          db: db2, repos: Repositories(db2), transport: FakeSyncServer());
      final a2 = ColdArchive(
          ctx: ctx2, remote: remote, transport: transport, now: () => now);

      setMetaValue(db2, 'sync.archive.horizon', '500');
      final r = await a2.restoreIfGap();
      expect(r, isNotNull);
      expect(r!.ok, isTrue);
      expect(r.bundles, 1);
      expect(db2.queryFirst('SELECT * FROM records WHERE id = ?', ['r200d']),
          isNotNull, reason: 'الصف المؤرشَف رُطِّب');

      // لا تكرار لنفس الأفق
      expect(await a2.restoreIfGap(), isNull);
    });

    test('مؤشر فوق الأفق ⇒ لا فجوة ولا استرجاع', () async {
      setMetaValue(db, 'sync.cursor.txid', '900');
      setMetaValue(db, 'sync.archive.horizon', '500');
      expect(await arch().restoreIfGap(), isNull);
    });

    test('لا أفق (خادم قديم) ⇒ لا استرجاع — فشل آمن', () async {
      setMetaValue(db, 'sync.cursor.txid', '0');
      expect(await arch().restoreIfGap(), isNull);
    });

    test('استرجاع ناقص لا يُسجَّل ⇒ يُعاد في المرة التالية', () async {
      seedRec('r200d', 200); // م179 — نافذة 180 يوماً
      await arch().run();
      final bk = remote.store.keys.firstWhere((k) => k.endsWith('.gz'));
      remote.store[bk] = Uint8List.fromList([9, 9, 9]); // إفساد الحزمة

      final tmp3 = Directory.systemTemp.createTempSync('m73c_');
      addTearDown(() => tmp3.deleteSync(recursive: true));
      final db3 = LocalDb.open(p.join(tmp3.path, 'dental_clinic_offline.db'));
      addTearDown(db3.close);
      final ctx3 = SyncContext(
          db: db3, repos: Repositories(db3), transport: FakeSyncServer());
      final a3 = ColdArchive(
          ctx: ctx3, remote: remote, transport: transport, now: () => now);
      setMetaValue(db3, 'sync.archive.horizon', '500');

      final r1 = await a3.restoreIfGap();
      expect(r1!.ok, isFalse);
      final r2 = await a3.restoreIfGap();
      expect(r2, isNotNull, reason: 'لم يُسجَّل ⇒ يُعاد');
    });
  });
}
