/// اختبارات م77 — دفعة سلامة البيانات: حدّ انحراف الساعة، وفشل قراءة فهرس
/// الأرشيف المغلق، وحذف صور الأشعة عند تبديل الحساب.
///
///  المبدأ الجامع للثلاثة: **الحارس لا يجوز أن يصير حاجزاً**. كل بند هنا
///  يمنع فقداً حقيقياً، ولكل بند اختبارٌ نظير يثبت أن المسار المشروع لم
///  يتضرّر — لأن حارساً مفرِطاً في تطبيق طبي أسوأ من العلة التي يعالجها.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/archive/cold_archive.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/hlc.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart'
    show setLastUid;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

/// طرف R2 مزيّف بإخفاق قراءة قابل للحقن — الفرق الجوهري عن مزيّف م70 أن
/// هذا يفرّق بين «المفتاح غير موجود» و«القراءة أخفقت والكائن موجود».
class FaultyRemote implements XrayRemote {
  final store = <String, Uint8List>{};

  /// مفاتيح تُخفق قراءتها رغم وجود الكائن — محاكاة انقطاع شبكة عابر.
  final failReadKeys = <String>{};
  int indexReads = 0;

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
    if (key.endsWith('index.json')) indexReads++;
    // العطل الحقيقي: `null` مع بقاء الكائن سليماً على R2 — وهو ما كان
    // العميل يقرؤه «لا فهرس بعد».
    if (failReadKeys.contains(key)) return null;
    return store[key];
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

class RecordingArchiveTransport implements ArchiveTransport {
  final deleteCalls = <List<Map<String, String>>>[];

  @override
  Future<int> archiveRows(List<Map<String, String>> items,
      {required int minAgeDays, int? callerTxid}) async {
    deleteCalls.add(List.of(items));
    return items.length;
  }

  @override
  Future<void> reportSyncState(String deviceId, int cursorTxid) async {}
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  group('م77/أ — حدّ انحراف الساعة المنطقية', () {
    test('الساعة المحفوظة المسمومة تُصلَح مرة واحدة عند الإقلاع', () {
      final c = Hlc();
      final poisoned = DateTime.now().millisecondsSinceEpoch +
          400 * 24 * 3600 * 1000; // بعد أكثر من سنة

      c.restore((ms: poisoned, counter: 7));

      expect(c.driftRepairs, 1);
      expect(c.getState().ms, lessThan(poisoned));
      expect(c.getState().ms,
          closeTo(DateTime.now().millisecondsSinceEpoch, 60000),
          reason: 'أُعيدت إلى الزمن الجداري');
      expect(c.getState().counter, 0);
    });

    test('الساعة المحفوظة السليمة لا تُمسّ — الإصلاح الوقائي بلا أثر جانبي',
        () {
      final c = Hlc();
      final sane = DateTime.now().millisecondsSinceEpoch - 5000;
      c.restore((ms: sane, counter: 3));

      expect(c.driftRepairs, 0, reason: 'لا إصلاح على جهاز سليم');
      expect(c.getState(), (ms: sane, counter: 3),
          reason: 'الحالة المحفوظة كما هي بالضبط');
    });

    test('العدوى تتوقف: ساعة الجهاز المسموم لا تنتقل إلى القرين', () {
      final peer = Hlc();
      final poisonedHlc = '99999999999999:3:sick-device';

      // خمسة صفوف من الجهاز المسموم في دورة سحب واحدة.
      for (var i = 0; i < 5; i++) {
        peer.receive(poisonedHlc);
      }

      expect(peer.driftRejections, 5);
      final t = peer.tick('healthy');
      expect(hlcMillis(t),
          closeTo(DateTime.now().millisecondsSinceEpoch, 60000),
          reason: 'م77: القرين لم يُعدَ — وهذا ما يكسر سلسلة الانتشار');
    });

    test('حدٌّ محقون: الرتابة تبقى محفوظة بعد الرفض', () {
      // حدّ ضيّق (ثانية واحدة) ليُفحص السلوك بلا انتظار.
      final c = Hlc(maxDriftMs: 1000);
      final a = c.tick('dev');
      c.receive('99999999999999:9:bad');
      final b = c.tick('dev');
      final d = c.tick('dev');

      expect(c.driftRejections, 1);
      expect(isNewer(b, a), isTrue, reason: 'الرتابة لم تنكسر بالرفض');
      expect(isNewer(d, b), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م77/ب — فشل قراءة فهرس الأرشيف يوقف الحذف', () {
    late Directory tmp;
    late LocalDb db;
    late SyncContext ctx;
    late FaultyRemote remote;
    late RecordingArchiveTransport transport;

    final now = DateTime(2026, 7, 30, 12);
    int daysAgoMs(int d) =>
        now.subtract(Duration(days: d)).millisecondsSinceEpoch;
    String daysAgoDate(int d) {
      final t = now.subtract(Duration(days: d));
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m77a_');
      db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
      ctx = SyncContext(
          db: db, repos: Repositories(db), transport: FakeSyncServer());
      remote = FaultyRemote();
      transport = RecordingArchiveTransport();
    });
    tearDown(() {
      db.close();
      tmp.deleteSync(recursive: true);
    });

    ColdArchive arch() => ColdArchive(
        ctx: ctx, remote: remote, transport: transport, now: () => now);

    void seedOldRecord(String id, int daysAgo) {
      db.execute(
        'INSERT INTO records (id, date, _mod, _dirty, _deleted, _hlc, data) '
        'VALUES (?,?,?,?,?,?,?)',
        [
          id,
          daysAgoDate(daysAgo),
          daysAgoMs(daysAgo),
          0,
          0,
          '${daysAgoMs(daysAgo)}:0:seed',
          jsonEncode({'id': id}),
        ],
      );
    }

    /// مفتاح الفهرس حتمي: `archive/<uid>/index.json`، والـuid هنا 'local'
    /// لأن الاختبار لا يثبّت مالكاً — نطابقه بالبحث كي لا نكرّر الاشتقاق.
    String? indexKey() {
      for (final k in remote.store.keys) {
        if (k.endsWith('index.json')) return k;
      }
      return null;
    }

    /// م77 — بذرُ صفٍّ **أحدث من العلامة المائية** للدورة الثانية.
    ///
    ///  فخٌّ وقعت فيه النسخة الأولى من هذه الاختبارات: بُذر الصف الثاني
    ///  أقدمَ من الأول (250 يوماً مقابل 240)، والانتقاء يشترط
    ///  `_mod > العلامة المائية` — والعلامة صارت `_mod` الصف الأول بعد
    ///  أرشفته. فرُشِّح الصف الثاني، وعادت الدورة `ok: true` بسبب **«لا شيء
    ///  مؤهل»**، وهو نجاحٌ مشروع لا علاقة له بالحارس.
    ///
    ///  النتيجة أن الاختبارات كانت **تمرّ من مسار لا يمسّ ما تدّعي فحصه**.
    ///  ولذلك تؤكّد [expectEligible] أدناه وجود مرشّحين **قبل** كل تشغيل:
    ///  فإن عاد الانتقاء فارغاً يسقط الاختبار بدل أن يتظاهر بالنجاح.
    void seedNewerThanWatermark(String id, int daysAgo) =>
        seedOldRecord(id, daysAgo);

    void expectEligible(String why) {
      expect(arch().selectEligible(), isNotEmpty,
          reason: 'شرط صحة الاختبار: $why — بلا مرشّحين تعود الدورة '
              'ok:true لسبب لا علاقة له بالحارس');
    }

    test('الدورة الأولى تنجح وتبني الفهرس', () async {
      seedOldRecord('r1', 240);
      final r = await arch().run(manual: true);

      expect(r.ok, isTrue, reason: r.reason);
      expect(transport.deleteCalls, hasLength(1));
      expect(indexKey(), isNotNull);
      final idx = jsonDecode(utf8.decode(remote.store[indexKey()!]!)) as Map;
      expect((idx['bundles'] as List), hasLength(1));
    });

    test('إخفاق قراءة الفهرس في الدورة الثانية ⇒ لا حذف ولا دهس للفهرس',
        () async {
      // دورة أولى سليمة تبني الفهرس وترفع المرساة المحلية.
      seedOldRecord('r1', 240);
      expect((await arch().run(manual: true)).ok, isTrue);
      final key = indexKey()!;
      final goodIndex = Uint8List.fromList(remote.store[key]!);
      expect(transport.deleteCalls, hasLength(1));

      // دورة ثانية والشبكة تُخفق على الفهرس **وحده** — الكائن سليم على R2.
      // 200 يوماً: أحدث من العلامة المائية (240) وأقدم من نافذة الـ90.
      seedNewerThanWatermark('r2', 200);
      expectEligible('يجب أن يوجد صفّ مؤهل للدورة الثانية');
      remote.failReadKeys.add(key);
      final r2 = await arch().run(manual: true);

      expect(r2.ok, isFalse, reason: 'م77: الفشل المغلق يشمل قراءة الفهرس');
      expect(r2.archived, 0);
      expect(r2.reason, contains('فهرس'));
      expect(transport.deleteCalls, hasLength(1),
          reason: 'م77: **لا نداء حذف ثانٍ** — هذا جوهر الإصلاح');
      expect(remote.store[key], equals(goodIndex),
          reason: 'م77: الفهرس السليم لم يُدهَس بفهرس يتيم');
    });

    test('الفهرس الأقصر من المعروف محلياً يُعدّ مبتوراً لا جديداً', () async {
      seedOldRecord('r1', 240);
      expect((await arch().run(manual: true)).ok, isTrue);
      final key = indexKey()!;

      // فهرس يقرأ بنجاح لكنه فارغ — كتابة فاشلة سابقة أو بتر.
      remote.store[key] = Uint8List.fromList(
          utf8.encode(jsonEncode({'v': 1, 'bundles': <Object?>[]})));

      seedNewerThanWatermark('r2', 200);
      expectEligible('يجب أن يوجد صفّ مؤهل ليُختبَر البتر');
      final r2 = await arch().run(manual: true);

      expect(r2.ok, isFalse);
      expect(transport.deleteCalls, hasLength(1),
          reason: 'المرساة المحلية تكشف البتر ولو نجحت القراءة');
    });

    test('الفهرس الفاسد يوقف الحذف بدل «البدء من جديد»', () async {
      seedOldRecord('r1', 240);
      expect((await arch().run(manual: true)).ok, isTrue);
      final key = indexKey()!;
      remote.store[key] = Uint8List.fromList(utf8.encode('{ليس JSON صالحاً'));

      seedNewerThanWatermark('r2', 200);
      expectEligible('يجب أن يوجد صفّ مؤهل ليُختبَر الفهرس الفاسد');
      final r2 = await arch().run(manual: true);

      expect(r2.ok, isFalse);
      expect(transport.deleteCalls, hasLength(1));
    });

    test('أول تشغيل حقيقي (لا فهرس ولا مرساة) يمضي كالمعتاد', () async {
      // النظير الذي يمنع الحارس من أن يصير حاجزاً: غياب حقيقي ⇒ لا إعاقة.
      seedOldRecord('r1', 240);
      final r = await arch().run(manual: true);

      expect(r.ok, isTrue, reason: 'م77: الغياب الحقيقي ليس فشلاً');
      expect(transport.deleteCalls, hasLength(1));
    });

    test('restore يميّز تعذّر القراءة عن غياب الأرشيف', () async {
      seedOldRecord('r1', 240);
      expect((await arch().run(manual: true)).ok, isTrue);
      final key = indexKey()!;
      remote.failReadKeys.add(key);

      final res = await arch().restore();
      expect(res.ok, isFalse,
          reason: 'م77: لا يُقال «لا أرشيف» لجهاز عجز عن القراءة');
      expect(res.reason, contains('تعذّر'));
      expect(res.reason, isNot(contains('لا أرشيف لهذا الحساب')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م77/ج — صور الأشعة لا تنجو من تبديل الحساب', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m77c_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory imagesDir() => Directory(p.join(tmp.path, 'xray_images'));

    void seedImages() {
      final d = imagesDir()..createSync(recursive: true);
      // اسم الملف يحمل اسم المريض عربياً — المُنقّي يُبقي النطاق عمداً،
      // فسرد المجلد وحده كشفٌ لقائمة المرضى بلا فتح صورة.
      File(p.join(d.path, 'مريم_علي_scan.jpg')).writeAsBytesSync([1, 2, 3]);
      File(p.join(d.path, 'خالد_عمر_pano.jpg')).writeAsBytesSync([4, 5, 6]);
    }

    test('تبديل الحساب يمحو مجلد الصور كاملاً', () {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);

      final db = c.read(localDbProvider);
      db.setOwnerUid('user-A');
      setLastUid(db, 'user-A');
      seedImages();
      expect(imagesDir().listSync(), hasLength(2));

      // دخول حساب مختلف ⇒ مسار التبديل.
      c.read(authProvider.notifier).handleAccountSwitchForTest('user-B');

      expect(imagesDir().existsSync(), isFalse,
          reason: 'م77: صور الحساب السابق لا تبقى على جهاز مشترك');
    });

    test('نفس الحساب لا يمحو شيئاً — offline-first يبقى سليماً', () {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);

      final db = c.read(localDbProvider);
      db.setOwnerUid('user-A');
      setLastUid(db, 'user-A');
      seedImages();

      c.read(authProvider.notifier).handleAccountSwitchForTest('user-A');

      expect(imagesDir().existsSync(), isTrue);
      expect(imagesDir().listSync(), hasLength(2),
          reason: 'إعادة الدخول بالحساب نفسه ليست تبديلاً');
    });

    test('غياب المجلد لا يُسقط الدخول', () {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);

      final db = c.read(localDbProvider);
      db.setOwnerUid('user-A');
      setLastUid(db, 'user-A');
      // لا مجلد صور أصلاً
      expect(
          () => c.read(authProvider.notifier).handleAccountSwitchForTest('user-B'),
          returnsNormally);
    });
  });
}
