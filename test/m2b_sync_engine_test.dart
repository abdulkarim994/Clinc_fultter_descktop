/// اختبارات م2ب — طبقة التنسيق كاملة + **اختبار التقارب بجهازين**: قاعدتا
/// SQLite حقيقيتان تتزامنان عبر خادم مزيف بنفس دلالات الخلفية الفعلية،
/// ويجب أن تتقاربا إلى نفس الحالة تماماً في كل السيناريوهات الحرجة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/db_sync.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/entities.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:dental_clinic_flutter/data/sync/merge/tombstones.dart'
    show activeItems;
import 'package:dental_clinic_flutter/data/sync/push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

/// جهاز اختبار كامل: قاعدة حقيقية + مستودعات + محرك متصل بالخادم المشترك.
class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m2b_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    ctx = SyncContext(db: db, repos: repos, transport: server);
    engine = SyncEngine(ctx);
  }

  final String name;
  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncContext ctx;
  late final SyncEngine engine;

  Future<CycleResult> sync() => engine.runCycle('test');

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

/// Domain fields of one row (sync/transport columns stripped) for comparison.
Map<String, Object?> domainOf(Row? row) {
  if (row == null) return const {};
  final out = Map<String, Object?>.from(row);
  for (final k in [
    '_hlc', '_dirty', '_deleted', '_origin', 'server_seq', 'data',
    'owner_uid', '_mod', 'updated_at', 'created_at', '_entity',
  ]) {
    out.remove(k);
  }
  return out;
}

void main() {
  late FakeSyncServer server;
  late Device a;
  late Device b;

  setUp(() {
    syncFlags.resetForTest();
    server = FakeSyncServer();
    a = Device('A', server);
    b = Device('B', server);
  });

  tearDown(() {
    a.dispose();
    b.dispose();
    syncFlags.resetForTest();
  });

  /// دورة تقارب كاملة: أ يدفع ويسحب، ب يدفع (وقد يدمج) ويسحب، ثم أ يسحب
  /// نتيجة الدمج — وهي الرقصة القياسية لثلاث دورات.
  Future<void> converge() async {
    await a.sync();
    await b.sync();
    await a.sync();
    await b.sync();
  }

  group('التكرار الأساسي عبر الخادم', () {
    test('صف يُنشأ على أ يصل ب نظيفاً ويُمسح علم dirty على أ بعد الإقرار',
        () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد الطيّب'});
      expect(getPendingCount(a.ctx), 1);

      final ra = await a.sync();
      expect(ra.status, 'ok');
      expect(ra.pushed, 1);
      expect(getPendingCount(a.ctx), 0); // امتُصّ الإقرار

      final rb = await b.sync();
      expect(rb.merged, greaterThan(0));
      final row = b.repos.patients.getById('p1')!;
      expect(row['name'], 'أحمد الطيّب');
      final raw = b.db.queryFirst(
          'SELECT _dirty, server_seq FROM patients WHERE id = ?', ['p1'])!;
      expect(raw['_dirty'], 0); // server-origin — لن يُعاد دفعه
      expect(raw['server_seq'], isNotNull);
    });

    test('الدفع idempotent: إعادة دفع نفس الإصدار لا تضاعف شيئاً', () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      await a.sync();
      // نفس الصف بنفس HLC (لم يتغير) — أعد لفّ العلم يدوياً وادفع ثانية
      a.db.execute('UPDATE patients SET _dirty = 1 WHERE id = ?', ['p1']);
      await a.sync();
      expect(server.rows['patients']!.length, 1);
      await b.sync();
      expect(b.repos.patients.count(), 1);
    });
  });

  group('اختبار التقارب بجهازين — المسار القديم (row-LWW)', () {
    test('الصف الأحدث بساعة HLC يفوز والقديم يُسجَّل في conflict_log',
        () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'الاسم الأول'});
      await converge();

      // تعديلان متزامنان على نفس الصف — ب أحدث (ساعته تتقدم بعد أ)
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'تعديل أ'});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      b.repos.patients.upsertLocal({'id': 'p1', 'name': 'تعديل ب'});

      await converge();

      final na = a.repos.patients.getById('p1')!['name'];
      final nb = b.repos.patients.getById('p1')!['name'];
      expect(na, nb); // تقاربا
      expect(na, 'تعديل ب'); // الأحدث فاز
      // الطرف المهزوم محفوظ في سجل التعارضات على أ (حيث حصل السحق)
      final logged = a.db
          .query('SELECT * FROM conflict_log WHERE entity = ?', ['patients']);
      expect(logged, isNotEmpty);
    });
  });

  group('اختبار التقارب بجهازين — الدمج الحقلي', () {
    setUp(() => syncFlags.fieldMerge = true);

    test('تعديلان على حقلين مختلفين لنفس المريض ينجوان معاً على الجهازين',
        () async {
      a.repos.patients.upsertLocal({
        'id': 'p1',
        'name': 'أحمد الطيّب',
        'phone': '0912345678',
        'notes': '',
      });
      await converge();

      // ترتيب العقد الفعلي: من يدفع ثانياً (ب) يجب أن يحمل ساعة أقدم —
      // فيرفضه الخادم ويصنع سحبُه «المزيج» الذي يحمل التعديلين معاً.
      b.repos.patients
          .upsertLocal({...b.repos.patients.getById('p1')!, 'phone': '0925554433'});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      a.repos.patients
          .upsertLocal({...a.repos.patients.getById('p1')!, 'name': 'أحمد الطيّب الفيتوري'});

      await converge();
      await converge(); // جولة إضافية ليستقر الدفع المدموج

      final ra = a.repos.patients.getById('p1')!;
      final rb = b.repos.patients.getById('p1')!;
      expect(ra['name'], 'أحمد الطيّب الفيتوري');
      expect(ra['phone'], '0925554433');
      expect(domainOf(ra), equals(domainOf(rb))); // تطابق كامل للجهازين
      expect(getPendingCount(a.ctx), 0);
      expect(getPendingCount(b.ctx), 0);
    });

    test('دفعتا دين متزامنتان: كل الأقساط تنجو والمجاميع تُعاد من الأقساط',
        () async {
      a.repos.debts.upsertLocal({
        'id': 'd1',
        'patient_name': 'أحمد',
        'total': 300,
        'installments': [
          {'id': 'i1', 'amount': 100}
        ],
        'paidAmount': 100,
        'remaining': 200,
        'status': 'partial',
      });
      await converge();

      final dbb = b.repos.debts.getById('d1')!;
      b.repos.debts.upsertLocal({
        ...dbb,
        'installments': [
          ...?(dbb['installments'] as List?),
          {'id': 'i3', 'amount': 75},
        ],
        'paidAmount': 175,
        'remaining': 125,
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final da = a.repos.debts.getById('d1')!;
      a.repos.debts.upsertLocal({
        ...da,
        'installments': [
          ...?(da['installments'] as List?),
          {'id': 'i2', 'amount': 50},
        ],
        'paidAmount': 150,
        'remaining': 150,
      });

      await converge();
      await converge();

      final fa = a.repos.debts.getById('d1')!;
      final fb = b.repos.debts.getById('d1')!;
      final ids = (fa['installments'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(ids, {'i1', 'i2', 'i3'}); // ولا دفعة ضاعت
      expect(fa['paidAmount'], 225); // recompute من الأقساط المدموجة
      expect(fa['remaining'], 75);
      expect(fa['status'], 'partial');
      expect(domainOf(fa), equals(domainOf(fb)));
    });

    test('حذف قسط يتقارب لشاهدة على الجهازين ولا يعود مع تعديل متزامن',
        () async {
      a.repos.debts.upsertLocal({
        'id': 'd1',
        'patient_name': 'س',
        'total': 100,
        'installments': [
          {'id': 'i1', 'amount': 40}
        ],
      });
      await converge();

      // ب يعدّل مبلغه أولاً؛ ثم أ يحذف القسط (إزالة فعلية) بساعة أحدث
      final dbb = b.repos.debts.getById('d1')!;
      b.repos.debts.upsertLocal({
        ...dbb,
        'installments': [
          {'id': 'i1', 'amount': 99}
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final da = a.repos.debts.getById('d1')!;
      a.repos.debts.upsertLocal({...da, 'installments': <Object?>[]});

      await converge();
      await converge();

      for (final dev in [a, b]) {
        final row = dev.repos.debts.getById('d1')!;
        final inst = row['installments'] as List;
        expect(activeItems(inst), isEmpty,
            reason: '${dev.name}: القسط المحذوف يجب ألا يظهر');
        expect((inst.single as Map)['_deleted'], 1); // شاهدة قانونية باقية
        expect(row['paidAmount'], 0); // المجاميع أعيد اشتقاقها
        expect(row['status'], 'unpaid');
      }
    });

    test('app.config: إضافة عيادة مقابل تغيير عملة يتقاربان معاً', () async {
      syncFlags.fieldMergeOverride['settings'] = true;
      a.repos.settings.set('app.config', {
        'clinics': ['الرئيسية'],
        'currency': 'د.ل',
      });
      await converge();

      final cfgB =
          Map<String, Object?>.from(b.repos.settings.get('app.config') as Map);
      b.repos.settings.set('app.config', {...cfgB, 'currency': 'USD'});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final cfgA =
          Map<String, Object?>.from(a.repos.settings.get('app.config') as Map);
      a.repos.settings.set('app.config', {
        ...cfgA,
        'clinics': [...(cfgA['clinics'] as List), 'عيادة الفتح'],
      });

      await converge();
      await converge();

      for (final dev in [a, b]) {
        final cfg =
            Map<String, Object?>.from(dev.repos.settings.get('app.config') as Map);
        expect(cfg['currency'], 'USD', reason: dev.name);
        expect(cfg['clinics'], containsAll(['الرئيسية', 'عيادة الفتح']),
            reason: dev.name);
      }
    });
  });

  group('انتشار الحذف الناعم', () {
    test('حذف سجل على أ يصل ب كشاهدة ولا يظهر في القراءات', () async {
      a.repos.records.upsertLocal(
          {'id': 'r1', 'patient_name': 'أحمد', 'date': '2026-07-26', 'amount': 50});
      await converge();
      expect(b.repos.records.getById('r1'), isNotNull);

      a.repos.records.delete('r1');
      await converge();

      expect(b.repos.records.getById('r1'), isNull);
      expect(b.repos.records.getAll(), isEmpty);
      expect(b.repos.records.getDeletedIds(), ['r1']); // إشارة الحذف الرسمية
      expect(getPendingCount(a.ctx), 0);
    });
  });

  group('الإعدادات per-key LWW', () {
    test('مفتاحان مختلفان من جهازين يتعايشان؛ ونفس المفتاح يفوز به الأحدث',
        () async {
      a.repos.settings.set('clinic.name', 'عيادة أ');
      b.repos.settings.set('doctor.name', 'د. خالد');
      await converge();

      for (final dev in [a, b]) {
        expect(dev.repos.settings.get('clinic.name'), 'عيادة أ');
        expect(dev.repos.settings.get('doctor.name'), 'د. خالد');
      }

      // نفس المفتاح: ب يكتب لاحقاً → يفوز على الجهازين
      a.repos.settings.set('clinic.name', 'تعديل أ');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      b.repos.settings.set('clinic.name', 'تعديل ب');
      await converge();
      await converge();
      expect(a.repos.settings.get('clinic.name'), 'تعديل ب');
      expect(b.repos.settings.get('clinic.name'), 'تعديل ب');
    });
  });

  group('الأعطال والحصانة', () {
    test('فشل الدفع يبقي الصفوف dirty ويرفع العدادات ثم ينجح لاحقاً', () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      server.failPushes = 1;

      final r1 = await a.sync();
      expect(r1.status, 'error');
      expect(getPendingCount(a.ctx), 1); // لم يُفقد شيء
      final attempts = getMetaJson<Map>(a.db, attemptsKey, const {});
      expect(attempts['patients:p1'], 1);

      final r2 = await a.engine.syncNow(); // forced يتجاوز التراجع
      expect(r2.status, 'ok');
      expect(getPendingCount(a.ctx), 0);
    });

    test('الحجر بعد 8 محاولات فاشلة ثم retryQuarantined يعيد التأهيل',
        () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      server.failPushes = maxAttempts;
      for (var i = 0; i < maxAttempts; i++) {
        await a.engine.syncNow(); // forced ليتجاوز backoff في كل مرة
      }
      expect(getQuarantinedCount(a.ctx), 1);
      expect(getPendingCount(a.ctx), 0); // معزول عن الدفع

      // retryFailedAndSync يعيد التأهيل لكنه دورة غير قسرية — بعد 8 إخفاقات
      // نافذة التراجع الأسّي ضخمة (سلوك الأصل نفسه)، فنُتبعها بدورة قسرية.
      await a.engine.retryFailedAndSync();
      expect(getQuarantinedCount(a.ctx), 0); // أعيد تأهيل الصفوف فوراً
      final r = await a.engine.syncNow();
      expect(r.status, 'ok');
      expect(server.rows['patients']!.containsKey('p1'), isTrue);
    });

    test('عدم الاتصال يرجع offline دون لمس أي شيء', () async {
      a.ctx.isOnline = () => false;
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      final r = await a.sync();
      expect(r.status, 'offline');
      expect(getPendingCount(a.ctx), 1);
    });

    test('single-flight: متصلان أثناء دورة جارية يستلمان نتيجتها الحقيقية',
        () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      final f1 = a.engine.runCycle('bg');
      final f2 = a.engine.runCycle('rider'); // يركب الدورة الجارية
      final results = await Future.wait([f1, f2]);
      expect(results[0].status, 'ok');
      expect(results[1].status, 'ok');
      expect(server.rows['patients']!.length, 1);
    });

    test('المؤشر يتقدم ولا يُعاد دمج صفحات قديمة عبثاً', () async {
      a.repos.patients.upsertLocal({'id': 'p1', 'name': 'أحمد'});
      await a.sync();
      await b.sync();
      final c1 = getMetaValue(b.db, 'sync.cursor.txid');
      final r = await b.sync(); // لا جديد
      expect(r.merged, 0);
      expect(getMetaValue(b.db, 'sync.cursor.txid'), c1);
    });
  });

  group('التقارب الشامل متعدد الكيانات (السيناريو الكبير)', () {
    test('مريض + سجل + دين + إعداد عبر جهازين = حالة نهائية متطابقة',
        () async {
      syncFlags.fieldMerge = true;
      // أ ينشئ كل شيء
      a.repos.patients.upsertLocal({'id': 'أحمد', 'name': 'أحمد'});
      a.repos.records.upsertLocal({
        'id': 'r1', 'patient_name': 'أحمد', 'date': '2026-07-26',
        'amount': 250, 'payment': 'كاش',
      });
      a.repos.debts.upsertLocal({
        'id': 'd1', 'patient_name': 'أحمد', 'total': 300,
        'installments': [
          {'id': 'i1', 'amount': 100}
        ],
      });
      a.repos.settings.set('clinic.name', 'عيادة الزهراء');
      await converge();

      // تعديلات متقاطعة (ب أولاً — ساعة أقدم لمن يدفع ثانياً)
      b.repos.records.upsertLocal(
          {...b.repos.records.getById('r1')!, 'amount': 275});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final da = a.repos.debts.getById('d1')!;
      a.repos.debts.upsertLocal({
        ...da,
        'installments': [
          ...?(da['installments'] as List?),
          {'id': 'i2', 'amount': 60},
        ],
      });
      await converge();
      await converge();

      // كل كيان متطابق بين الجهازين
      for (final entity in syncEntities) {
        if (entity == 'settings') continue;
        final repoA = repoFor(a.ctx, entity)!;
        final repoB = repoFor(b.ctx, entity)!;
        final rowsA = {
          for (final r in repoA.getAllIncludingDeleted()) r['id']: domainOf(r)
        };
        final rowsB = {
          for (final r in repoB.getAllIncludingDeleted()) r['id']: domainOf(r)
        };
        expect(rowsA, equals(rowsB), reason: 'divergence in $entity');
      }
      expect(a.repos.settings.get('clinic.name'),
          b.repos.settings.get('clinic.name'));
      expect(a.repos.debts.getById('d1')!['paidAmount'], 160);
      expect(b.repos.records.getById('r1')!['amount'], 275);
      expect(getPendingCount(a.ctx), 0);
      expect(getPendingCount(b.ctx), 0);
    });
  });
}
