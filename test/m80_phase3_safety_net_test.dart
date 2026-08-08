/// اختبارات م80 — المرحلة الثالثة: شبكة الأمان.
///
///  هذه المرحلة **لا تُصلح عطلاً**. تبني الشبكة التي ستمسك أعطال المرحلة
///  الرابعة (قلب المزامنة) قبل أن تُمسّ. ولذلك رُتّبت قبلها رغم أن نقاطها
///  أقل: الاختبار الذي يكشف كسر المزامنة يجب أن يوجد **قبل** كسرها.
///
///  أربعة محاور، كلها كانت ثغرات مُثبَتة في التدقيق:
///    أ) ترقية قاعدة قديمة ببيانات مالية حقيقية — **صفر تغطية**، وأخطر
///       مسار غير مختبَر: فشله يعني قاعدة عيادة لا تُفتح.
///    ب) أمانة الخادم الوهمي — كان أودّ من الواقع، فأصنافُ أعطالٍ كاملة
///       يستحيل أن تظهر في الاختبار.
///    ج) `reconcile_guard` — **صفر تغطية**، وهو الحارس ضد الحذف الوهمي.
///    د) أرقام التقارير — الاختبار القائم يفحص أربعة بايتات `%PDF` فقط،
///       فبرقمٍ خاطئ في مستند مالي يمرّ أخضر.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/db/schema_sql.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/data/sync/reconcile_guard.dart';
import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m80_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // ══════════════════════════════════════════════════════════════════════
  group('م80/أ — ترقية قاعدة قديمة ببيانات مالية حقيقية', () {
    /// يبني قاعدة **بمخطط ما قبل الترقيات**: بلا أعمدة المزامنة، وبلا
    /// الأعمدة المالية المرقّاة، والمال كلّه داخل كتلة `data`. هذا شكل
    /// قاعدة عيادة عاملة قبل التحديث حرفياً.
    String seedLegacyDb() {
      final path = p.join(tmp.path, 'legacy.db');
      final db = sq.sqlite3.open(path);
      // المخطّط **الأساس الحقيقي** لا نسخة مكتوبة يدوياً.
      //
      // `schemaSql` هو المخطّط المنقول حرفياً عن الأصل، والترقيات وحدها
      // تضيف فوقه أعمدة المزامنة والأعمدة المالية المرقّاة. فتنفيذه بلا
      // ترقيات يُنتج **قاعدة ما قبل التحديث بالضبط**.
      //
      // (محاولتان بمخطّط مكتوب يدوياً أخفقتا على فهرسَي `last_visit` ثم
      //  `status`: قاعدةٌ أبسط من الواقع لا تُمثّل الواقع، ومطاردةُ عمودٍ
      //  عموداً كانت ستُنتج اختباراً يثبت شيئاً آخر.)
      db.execute(schemaSql);
      db.execute(
          "INSERT INTO patients (id,name,phone,data) VALUES "
          "('p1','سالم المبروك','0912345678','{\"id\":\"p1\"}')");
      // مبالغ حقيقية بأرقام كسرية — الترقية تنقلها إلى أعمدة مرقّاة.
      db.execute(
          "INSERT INTO records (id,patient_name,date,service,amount,clinic,data) "
          "VALUES ('r1','سالم المبروك','2026-03-11','حشو',1250.75,'الصفوة',"
          "'{\"id\":\"r1\",\"isDebt\":1,\"payment\":\"دين\",\"doctorShare\":625.38}')");
      db.execute(
          "INSERT INTO records (id,patient_name,date,service,amount,clinic,data) "
          "VALUES ('r2','سالم المبروك','2026-03-12','تركيبات',3000,'الصفوة',"
          "'{\"id\":\"r2\",\"isPros\":1,\"payment\":\"كاش\"}')");
      // صفّ كتلته تحمل `_dirty` — هذا ما تُرقّيه الترقية فعلاً.
      db.execute(
          "INSERT INTO records (id,patient_name,date,service,amount,clinic,data) "
          "VALUES ('r3','ليلى','2026-03-13','خلع',200,'الصفوة',"
          "'{\"id\":\"r3\",\"_dirty\":1}')");
      db.execute(
          "INSERT INTO debts (id,patient_name,data) VALUES ('d1','سالم المبروك',"
          "'{\"id\":\"d1\",\"totalAmount\":1250.75,\"paidAmount\":250.75}')");
      db.close();
      return path;
    }

    test('الترقية تفتح القاعدة القديمة ولا تفقد صفاً واحداً', () {
      final path = seedLegacyDb();

      // الفعل نفسه الذي يجري عند أول فتح بعد التحديث.
      final db = LocalDb.open(path);
      addTearDown(db.close);

      expect(db.query('SELECT * FROM patients'), hasLength(1));
      expect(db.query('SELECT * FROM records'), hasLength(3));
      expect(db.query('SELECT * FROM debts'), hasLength(1));

      final pat = db.queryFirst('SELECT * FROM patients WHERE id = ?', ['p1']);
      expect(pat?['name'], 'سالم المبروك', reason: 'الاسم العربي سليم');
      expect(pat?['phone'], '0912345678');
    });

    test('المال ينجو بالقيمة الكسرية بالضبط — لا تقريب ولا فقد', () {
      final path = seedLegacyDb();
      final db = LocalDb.open(path);
      addTearDown(db.close);

      final r1 = db.queryFirst('SELECT * FROM records WHERE id = ?', ['r1']);
      expect(jsNumOr0(r1?['amount']), 1250.75,
          reason: 'م80: مبلغ العلاج كما هو حرفاً');

      final merged = parseRowData(r1)!;
      expect(jsNumOr0(merged['doctorShare']), 625.38,
          reason: 'حصة الطبيب من الكتلة سليمة');

      final d1 = db.queryFirst('SELECT * FROM debts WHERE id = ?', ['d1']);
      final dm = parseRowData(d1)!;
      expect(jsNumOr0(dm['totalAmount']), 1250.75);
      expect(jsNumOr0(dm['paidAmount']), 250.75);
    });

    test('أعمدة المزامنة تُضاف والعلم يُرقّى من الكتلة إلى العمود', () {
      final path = seedLegacyDb();
      final db = LocalDb.open(path);
      addTearDown(db.close);

      final cols = {
        for (final c in db.query('PRAGMA table_info(records)')) '${c['name']}'
      };
      // بلا هذه الأعمدة لا يستطيع المحرّك دفع صفٍّ واحد.
      for (final need in ['_dirty', '_hlc', '_origin', 'server_seq', 'owner_uid']) {
        expect(cols, contains(need), reason: 'م80: عمود المزامنة $need');
      }
      // وأعمدة المال المرقّاة (المرحلة 2أ) — مصدر علّة م76.
      for (final need in ['isDebt', 'isPros', 'isDebtPayment', 'payment']) {
        expect(cols, contains(need), reason: 'م80: العمود المالي $need');
      }

      // **تصحيح توقّع**: الترقية لا تختم الصفوف القديمة متسخة — بل تُرقّي
      // العلم الموجود في الكتلة إلى عموده. أما ادّعاء الصفوف القديمة للدفع
      // فمسار مختلف تماماً (`healOwnershipAtBoot` عند الدخول لا عند فتح
      // القاعدة). كان توقّعي الأول خاطئاً، والاختبار الآن يفحص ما تَعِد به
      // الترقية فعلاً لا ما ظننتُه.
      final r3 = db.queryFirst('SELECT _dirty FROM records WHERE id = ?', ['r3']);
      expect(jsNumOr0(r3?['_dirty']), 1,
          reason: 'م80: العلم من الكتلة صار عموداً');

      final r1 = db.queryFirst('SELECT _dirty FROM records WHERE id = ?', ['r1']);
      expect(jsNumOr0(r1?['_dirty']), 0,
          reason: 'صفّ بلا علم في كتلته يبقى نظيفاً — لا اختلاق');
    });

    test('الأعمدة المالية تُرقّى من الكتلة بقيمها الصحيحة', () {
      final path = seedLegacyDb();
      final db = LocalDb.open(path);
      addTearDown(db.close);

      final r1 = db.queryFirst(
          'SELECT isDebt, isPros, payment FROM records WHERE id = ?', ['r1']);
      expect(jsNumOr0(r1?['isDebt']), 1, reason: 'م80: من الكتلة إلى العمود');
      expect(jsNumOr0(r1?['isPros']), 0);
      expect(r1?['payment'], 'دين');

      final r2 = db.queryFirst(
          'SELECT isDebt, isPros, payment FROM records WHERE id = ?', ['r2']);
      expect(jsNumOr0(r2?['isPros']), 1);
      expect(jsNumOr0(r2?['isDebt']), 0);
      expect(r2?['payment'], 'كاش');
    });

    test('الترقية عديمة الأثر — إعادة الفتح لا تُكرّر ولا تُفسد', () {
      final path = seedLegacyDb();
      LocalDb.open(path).close();
      LocalDb.open(path).close();
      final db = LocalDb.open(path);
      addTearDown(db.close);

      expect(db.query('SELECT * FROM records'), hasLength(3),
          reason: 'م80: ثلاث فتحات ⇒ ثلاثة صفوف لا تسعة');
      expect(jsNumOr0(db.queryFirst(
              'SELECT amount FROM records WHERE id = ?', ['r1'])?['amount']),
          1250.75);
    });

    test('رقم المخطط يُثبَّت بعد الترقية', () {
      final path = seedLegacyDb();
      final db = LocalDb.open(path);
      addTearDown(db.close);
      final v = db.query('PRAGMA user_version').first.values.first as int;
      expect(v, dbVersion);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م80/ب — أمانة الخادم الوهمي', () {
    ({LocalDb db, SyncContext ctx, FakeSyncServer srv, SyncEngine eng}) boot(
        String name) {
      final db = LocalDb.open(p.join(tmp.path, '$name.db'));
      final srv = FakeSyncServer();
      final repos = Repositories(db);
      final ctx = SyncContext(db: db, repos: repos, transport: srv);
      return (db: db, ctx: ctx, srv: srv, eng: SyncEngine(ctx));
    }

    test('الصفوف المكرّرة في الصفحة لا تُنتج صفوفاً مكرّرة محلياً', () async {
      final a = boot('dupA');
      addTearDown(a.db.close);
      a.ctx.repos.patients.upsertLocal({'id': 'p1', 'name': 'سالم'});
      await a.eng.runCycle('t');

      final b = boot('dupB');
      addTearDown(b.db.close);
      // الجهاز الثاني يقرأ من الخادم نفسه، والخادم يكرّر كل صفّ.
      final b2 = SyncContext(
          db: b.db, repos: Repositories(b.db), transport: a.srv);
      a.srv.duplicateRows = true;
      await SyncEngine(b2).runCycle('t');

      expect(b.ctx.repos.patients.getAll(), hasLength(1),
          reason: 'م80: التسليم المكرّر لا يُنتج مريضاً مرتين');
    });

    test('الصفوف خارج الترتيب تصل كاملةً', () async {
      final a = boot('ordA');
      addTearDown(a.db.close);
      for (var i = 0; i < 5; i++) {
        a.ctx.repos.patients.upsertLocal({'id': 'p$i', 'name': 'مريض $i'});
      }
      await a.eng.runCycle('t');

      final b = boot('ordB');
      addTearDown(b.db.close);
      final b2 = SyncContext(
          db: b.db, repos: Repositories(b.db), transport: a.srv);
      a.srv.shuffleRows = true;
      await SyncEngine(b2).runCycle('t');

      expect(b2.repos.patients.getAll(), hasLength(5),
          reason: 'م80: ترتيبٌ معكوس لا يُسقط صفاً');
    });

    test('انتهاء صلاحية الرمز صنفٌ مميَّز عن الفشل العام', () async {
      final a = boot('authA');
      addTearDown(a.db.close);
      a.ctx.repos.patients.upsertLocal({'id': 'p1', 'name': 'سالم'});

      a.srv.failPushes = 1;
      a.srv.nextFailureIsAuth = true;
      await a.eng.runCycle('t'); // يبتلع الفشل ويبقى الصف متسخاً

      expect(a.srv.authFailures, 1,
          reason: 'م80: 401 مساره مختلف عن العطل العام');
      expect(a.eng.getEngineStatus().pending, greaterThan(0),
          reason: 'الصف لم يُفقد');

      // `force: true` لازم هنا: الإخفاق يضبط تراجعاً أُسّياً، والدورة
      // التالية غير المُجبَرة تُتخطّى — وهو سلوك صحيح للمحرّك، وكان
      // توقّعي أنا هو الخاطئ.
      await a.eng.runCycle('t', force: true);
      expect(a.eng.getEngineStatus().pending, 0,
          reason: 'م80: الصف وصل في المحاولة التالية');
    });

    test('التأخير لا يكسر دورة كاملة — كشفُ سباقاتٍ يخفيها الردّ الفوري',
        () async {
      final a = boot('latA');
      addTearDown(a.db.close);
      a.srv.latency = const Duration(milliseconds: 12);
      a.ctx.repos.patients.upsertLocal({'id': 'p1', 'name': 'سالم'});

      await a.eng.runCycle('t');
      expect(a.eng.getEngineStatus().pending, 0);
      expect(a.srv.rows['patients']?.containsKey('p1'), isTrue);
    });

    test('الأعلام مطفأة افتراضياً — لا يتغيّر أي اختبار قائم', () {
      final s = FakeSyncServer();
      expect(s.latency, Duration.zero);
      expect(s.duplicateRows, isFalse);
      expect(s.shuffleRows, isFalse);
      expect(s.nextFailureIsAuth, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م80/ج — حارس الحذف الوهمي (كان بصفر تغطية)', () {
    setUp(resetHydrationReady);
    tearDown(resetHydrationReady);

    test('البوابة مغلقة ⇒ لا حذف مهما بدا الصف غائباً', () {
      // الحالة الأخطر: الذاكرة لم تُرطَّب بعد، فغيابُ الصف منها لا يعني
      // شيئاً. حذفٌ هنا يمحو سجلّاً حيّاً.
      expect(isHydrationReady(), isFalse);
      expect(shouldTombstone({'id': 'r1'}, <String>{}), isFalse,
          reason: 'م80: فشل آمن — التأخير خير من الفقد');
    });

    test('البوابة مفتوحة والصف غائب فعلاً ⇒ يُحذف', () {
      setHydrationReady();
      expect(shouldTombstone({'id': 'r1'}, {'r2', 'r3'}), isTrue);
    });

    test('الصف الحاضر في الذاكرة لا يُحذف', () {
      setHydrationReady();
      expect(shouldTombstone({'id': 'r1'}, {'r1'}), isFalse);
    });

    test('كل حالة ملتبسة تُرفض', () {
      setHydrationReady();
      expect(shouldTombstone(null, {'x'}), isFalse, reason: 'صف معدوم');
      expect(shouldTombstone({'name': 'س'}, {'x'}), isFalse, reason: 'بلا id');
      expect(shouldTombstone({'id': ''}, {'x'}), isFalse, reason: 'id فارغ');
      expect(shouldTombstone({'id': 'r1', '_deleted': 1}, <String>{}), isFalse,
          reason: 'شاهد قبر أصلاً');
    });

    test('التجاوز الصريح يعمل في الاتجاهين', () {
      expect(shouldTombstone({'id': 'r1'}, <String>{}, hydrated: true), isTrue);
      setHydrationReady();
      expect(shouldTombstone({'id': 'r1'}, <String>{}, hydrated: false),
          isFalse);
    });

    test('إعادة التسليح تُغلق البوابة — الخروج يعيدها إلى الفشل الآمن', () {
      setHydrationReady();
      expect(isHydrationReady(), isTrue);
      resetHydrationReady();
      expect(isHydrationReady(), isFalse);
      expect(shouldTombstone({'id': 'r1'}, <String>{}), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م80/د — أرقام التقارير (لا مجرّد %PDF)', () {
    test('formatNumber: الفواصل والتقريب والحدود', () {
      expect(formatNumber(1000), '1,000');
      expect(formatNumber(1234567), '1,234,567');
      expect(formatNumber(999), '999');
      expect(formatNumber(1250.75), '1,250.75');
      expect(formatNumber(1250.5), '1,250.5', reason: 'بلا صفر زائد');
      expect(formatNumber(1250.0), '1,250', reason: 'بلا كسر زائد');
      expect(formatNumber(0), '0');
      expect(formatNumber(null), '0');
      expect(formatNumber(''), '0');
      expect(formatNumber('غير رقم'), '0', reason: 'لا يرمي ولا يطبع NaN');
      expect(formatNumber(-1250.75), '-1,250.75');
      expect(formatNumber(0.005), '0.01', reason: 'تقريب لخانتين');
    });

    test('جداول المعالجات: المجاميع تساوي مجموع الصفوف بالضبط', () {
      // الحصة تُشتقّ من **لقطة النسبة المجمّدة** `_rateSnapshot` لا من حقل
      // `doctorShare` جاهز — وهو جوهر تصميم م4: النسبة تُجمَّد وقت العملية
      // فلا يُعيد تغييرُ الإعدادات لاحقاً كتابةَ تقارير الماضي.
      final t = buildTreatmentTables([
        {
          'service': 'حشو', 'name': 'سالم', 'date': '2026-03-01',
          'amount': 1000, '_rateSnapshot': {'doctorPct': 50},
        },
        {
          'service': 'حشو', 'name': 'ليلى', 'date': '2026-03-02',
          'amount': 500, '_rateSnapshot': {'doctorPct': 50},
        },
        {
          'service': 'تركيبات', 'name': 'خالد', 'date': '2026-03-03',
          'amount': 3000, '_rateSnapshot': {'doctorPct': 40},
        },
      ]);

      expect(t.revenue, 4500, reason: 'م80: الإيراد الكلي');
      expect(t.doctor, 1950, reason: '500 + 250 + 1200');
      expect(t.clinic, 4500 - 1950, reason: 'العيادة = الإيراد − الطبيب');

      // كل مجموعة تساوي مجموع صفوفها — الخطأ هنا مستند مالي كاذب.
      for (final g in t.groups) {
        var rev = 0.0, doc = 0.0;
        for (final r in g.rows) {
          rev += r.amount;
          doc += r.doctor;
        }
        expect(g.revenue, closeTo(rev, 0.001), reason: 'مجموع ${g.service}');
        expect(g.doctor, closeTo(doc, 0.001));
        expect(g.clinic, closeTo(rev - doc, 0.001));
      }
      expect(t.groups.map((g) => g.service), containsAll(['حشو', 'تركيبات']));
    });

    test('النسبة المعروضة فعلية لا عامة — وهي ما يوقّع عليه الطبيب', () {
      // 40٪ فعلية بينما الافتراضي 50٪: عرضُ 50 هنا كذبٌ في مستند مالي.
      final t = buildTreatmentTables([
        {
          'service': 'حشو', 'name': 'س', 'date': '2026-03-01',
          'amount': 1000, '_rateSnapshot': {'doctorPct': 40},
        },
      ], fallbackPct: 50);
      expect(t.groups.single.effPct, 40);
    });

    test('نسبة صفر تُعلَّم فتُخفى أعمدة الأرباح', () {
      final t = buildTreatmentTables([
        {
          'service': 'كشف', 'name': 'س', 'date': '2026-03-01',
          'amount': 50, '_rateSnapshot': {'doctorPct': 0},
        },
      ]);
      expect(t.groups.single.zeroPct, isTrue);
      expect(t.groups.single.doctor, 0);
    });

    test('لا صفوف ⇒ أصفار لا انهيار ولا NaN', () {
      final t = buildTreatmentTables(const []);
      expect(t.groups, isEmpty);
      expect(t.revenue, 0);
      expect(t.doctor, 0);
      expect(t.clinic, 0);
    });
  });
}
