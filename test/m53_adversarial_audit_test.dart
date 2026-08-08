/// اختبار م53 (v32) — التدقيق العدائي الدقيق للتعديل المتزامن:
///   • فحص عشوائي مُبذور (30 جولة) على كل الكيانات والإعدادات وخطة
///     العلاج بترتيبات مزامنة متنوعة ⇒ شرطان بعد الاستقرار:
///     التقارب التام (مجالا القاعدتين متطابقان حقلاً بحقل) + عدم فقدان
///     أي نيّة (كل إضافة باقية، كل حذف نافذ).
///   • سيناريوهات عدائية موجهة: أوفلاين طويل، تناوب سريع على نفس الحقل،
///     حذف مع قسط متزامن، إعادة تسمية مع تعديل، حذف مريض مع تعديل مرحلة،
///     فشل دفع/سحب في منتصف الدورة، وثلاثة أجهزة.
library;

import 'dart:io';
import 'dart:math';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart'
    show editPatientCascade;
import 'package:dental_clinic_flutter/features/patients/treatment_plan_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

const syncCols = {
  '_hlc', '_dirty', '_deleted', '_origin', 'server_seq', 'data',
  'owner_uid', '_mod', 'updated_at', 'created_at', '_entity',
};

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m53_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine = SyncEngine(
        SyncContext(db: db, repos: repos, transport: server));
    plans = TreatmentPlanStore(repos.settings);
  }

  final String name;
  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncEngine engine;
  late final TreatmentPlanStore plans;

  Future<void> sync() async {
    // force: يتجاوز تراجع ما بعد الفشل (يمثل ضغطة «مزامنة» من المستخدم).
    await engine.runCycle('test', force: true);
  }

  Map<String, Object?> get config {
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  /// لقطة المجال الحيّ لكيان (بلا أعمدة النقل) مفهرسة بالمعرّف.
  Map<String, Map<String, Object?>> domain(String entity) {
    final repo = switch (entity) {
      'records' => repos.records,
      'debts' => repos.debts,
      'appointments' => repos.appointments,
      'prosthetics' => repos.prosthetics,
      'xrays' => repos.xrays,
      _ => throw ArgumentError(entity),
    };
    final out = <String, Map<String, Object?>>{};
    for (final r in repo.getAll().whereType<Map>()) {
      final m = <String, Object?>{};
      for (final e in r.entries) {
        if (!syncCols.contains(e.key)) m['${e.key}'] = e.value;
      }
      out['${m['id']}'] = m;
    }
    return out;
  }

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

bool deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// أول اختلاف بين خريطتين (للتشخيص المقروء عند الفشل).
String? firstDiff(Map<String, Map<String, Object?>> x,
    Map<String, Map<String, Object?>> y) {
  for (final id in {...x.keys, ...y.keys}) {
    final a = x[id];
    final b = y[id];
    if (a == null) return 'id=$id موجود في B فقط: $b';
    if (b == null) return 'id=$id موجود في A فقط: $a';
    for (final k in {...a.keys, ...b.keys}) {
      if (!deepEq(a[k], b[k])) {
        return 'id=$id حقل=$k: A=${a[k]} ≠ B=${b[k]}';
      }
    }
  }
  return null;
}

void main() {
  Future<void> settleAll(List<Device> ds, {int rounds = 4}) async {
    for (var i = 0; i < rounds; i++) {
      for (final d in ds) {
        await d.sync();
      }
    }
  }

  void expectConverged(Device a, Device b) {
    for (final entity in const [
      'records', 'debts', 'appointments', 'prosthetics', 'xrays',
    ]) {
      final diff = firstDiff(a.domain(entity), b.domain(entity));
      expect(diff, isNull, reason: '$entity لم يتقارب: $diff');
    }
    // الإعدادات المركّبة متطابقة.
    expect(deepEq(a.config, b.config), isTrue,
        reason: 'الإعدادات لم تتقارب:\nA=${a.config}\nB=${b.config}');
  }

  group('م53/1 — الفحص العشوائي المبذور', () {
    test('30 جولة عمليات عشوائية من جهازين: تقارب تام ولا فقدان نيّة',
        () async {
      final rnd = Random(20260728);
      final server = FakeSyncServer();
      final a = Device('a', server);
      final b = Device('b', server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      // نيّات يجب أن تصمد حتى النهاية.
      final mustExist = <String, Set<String>>{
        'records': {}, 'debts': {}, 'appointments': {},
        'prosthetics': {}, 'xrays': {},
      };
      final mustBeGone = <String, Set<String>>{
        'records': {}, 'debts': {}, 'appointments': {},
        'prosthetics': {}, 'xrays': {},
      };
      final planMust = <String>{};
      final planGone = <String>{};
      final clinicsMust = <String>{};
      final clinicsGone = <String>{};
      var seq = 0;

      String nid(String p) => '$p${seq++}';

      void randomOp(Device d) {
        final dice = rnd.nextInt(10);
        switch (dice) {
          case 0: // سجل جديد
            final id = nid('r');
            d.repos.records.upsertLocal({
              'id': id, 'name': 'سالم', 'patient_name': 'سالم',
              'clinic': 'ع1', 'service': 'حشو',
              'date': '2026-07-2${rnd.nextInt(8)}',
              'amount': 50 + rnd.nextInt(500), 'payment': 'كاش',
            });
            mustExist['records']!.add(id);
          case 1: // تعديل حقل بسجل قائم (من لقطة)
            final ids = mustExist['records']!.toList();
            if (ids.isEmpty) return;
            final id = ids[rnd.nextInt(ids.length)];
            final row = d.repos.records.getById(id);
            if (row == null) return;
            final snap = Map<String, Object?>.from(row);
            d.repos.records.upsertLocal(
                {...snap, 'amount': 1000 + rnd.nextInt(1000)},
                base: snap);
          case 2: // حذف سجل
            final ids = mustExist['records']!.toList();
            if (ids.isEmpty) return;
            final id = ids[rnd.nextInt(ids.length)];
            d.repos.records.delete(id);
            mustExist['records']!.remove(id);
            mustBeGone['records']!.add(id);
          case 3: // موعد جديد/تعديل حالته
            final id = nid('ap');
            d.repos.appointments.upsertLocal({
              'id': id, 'name': 'سالم', 'patient_name': 'سالم',
              'clinic': 'ع1', 'date': '2026-08-0${rnd.nextInt(9)}',
              'time': '1${rnd.nextInt(2)}:00', 'status': 'pending',
            });
            mustExist['appointments']!.add(id);
          case 4: // تركيبة جديدة
            final id = nid('pr');
            d.repos.prosthetics.upsertLocal({
              'id': id, 'name': 'سالم', 'patient_name': 'سالم',
              'clinic': 'ع1', 'type': 'زيركون', 'lab': 'مختبر أ',
              'date': '2026-07-20', 'amount': 300, 'labCost': 100,
              'status': 'sent',
            });
            mustExist['prosthetics']!.add(id);
          case 5: // صورة أشعة جديدة
            final id = nid('x');
            d.repos.xrays.upsertLocal({
              'id': id, 'name': 'سالم', 'patient_name': 'سالم',
              'clinic': 'ع1', 'key': 'k$id', 'label': 'صورة',
              'date': '2026-07-20',
            });
            mustExist['xrays']!.add(id);
          case 6: // دين جديد
            final id = nid('d');
            d.repos.debts.upsertLocal({
              'id': id, 'name': 'سالم', 'patient_name': 'سالم',
              'clinic': 'ع1', 'service': 'تركيبة',
              'date': '2026-07-20', 'amount': 500, 'total': 500,
              'totalAmount': 500, 'paidAmount': 0, 'remaining': 500,
              'status': 'unpaid', 'installments': <Object?>[],
            });
            mustExist['debts']!.add(id);
          case 7: // مرحلة خطة جديدة / حذف مرحلة
            if (rnd.nextBool() || planMust.isEmpty) {
              final st = d.plans.add('سالم', 'ع1', 'مرحلة ${seq++}');
              planMust.add(st.id);
            } else {
              final id = planMust.first;
              d.plans.remove('سالم', 'ع1', id);
              planMust.remove(id);
              planGone.add(id);
            }
          case 8: // عيادة جديدة / حذف عيادة
            if (rnd.nextBool() || clinicsMust.length < 2) {
              final c = 'عيادة ${seq++}';
              d.repos.settings.configAddItem(const ['clinics'], c);
              clinicsMust.add(c);
            } else {
              final c = clinicsMust.first;
              d.repos.settings.configRemoveItem(const ['clinics'], c);
              clinicsMust.remove(c);
              clinicsGone.add(c);
            }
          case 9: // تفضيل مفرد
            d.repos.settings.set('app.config',
                {...d.config, 'doctorPct': 30 + rnd.nextInt(40)});
        }
      }

      // بذرة مشتركة.
      a.repos.settings.set('app.config', {
        'centerName': 'مركز التدقيق',
        'currency': 'د.ل',
        'doctorPct': 40,
        'clinics': ['ع1'],
        'services': ['حشو'],
        'payments': ['كاش'],
      });
      await settleAll([a, b]);

      for (var round = 0; round < 30; round++) {
        final opsA = 1 + rnd.nextInt(3);
        final opsB = 1 + rnd.nextInt(3);
        for (var i = 0; i < opsA; i++) {
          randomOp(a);
        }
        for (var i = 0; i < opsB; i++) {
          randomOp(b);
        }
        // ترتيبات مزامنة متنوعة: متزامن/متأخر/متقطع.
        switch (rnd.nextInt(3)) {
          case 0:
            await a.sync();
            await b.sync();
          case 1:
            await b.sync();
            await a.sync();
          case 2:
            if (rnd.nextBool()) await a.sync();
        }
      }
      await settleAll([a, b], rounds: 5);

      // ① التقارب التام.
      expectConverged(a, b);
      // ② لا فقدان نيّة: كل إضافة باقية وكل حذف نافذ — على الجهازين.
      for (final d in [a, b]) {
        for (final e in mustExist.entries) {
          final have = d.domain(e.key).keys.toSet();
          expect(have.containsAll(e.value), isTrue,
              reason:
                  '${d.name}/${e.key}: مفقود ${e.value.difference(have)}');
        }
        for (final e in mustBeGone.entries) {
          final have = d.domain(e.key).keys.toSet();
          expect(have.intersection(e.value), isEmpty,
              reason: '${d.name}/${e.key}: بُعث محذوف');
        }
        final planIds =
            d.plans.read('سالم', 'ع1').map((s) => s.id).toSet();
        expect(planIds.containsAll(planMust), isTrue,
            reason: '${d.name}: مراحل مفقودة');
        expect(planIds.intersection(planGone), isEmpty,
            reason: '${d.name}: مرحلة محذوفة بُعثت');
        final clinics = <String>{
          for (final c in (d.config['clinics'] as List)) '$c',
        };
        expect(clinics.containsAll(clinicsMust), isTrue,
            reason: '${d.name}: عيادات مفقودة');
        expect(clinics.intersection(clinicsGone), isEmpty,
            reason: '${d.name}: عيادة محذوفة بُعثت');
      }
    });
  });

  group('م53/2 — سيناريوهات عدائية موجهة', () {
    late FakeSyncServer server;
    late Device a;
    late Device b;

    setUp(() async {
      server = FakeSyncServer();
      a = Device('a', server);
      b = Device('b', server);
      a.repos.settings.set('app.config', {
        'centerName': 'مركز', 'clinics': ['ع1'],
        'services': ['حشو'], 'payments': ['كاش'],
      });
      await settleAll([a, b]);
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('أوفلاين طويل على الجهازين ثم مزامنة واحدة: لا فقدان', () async {
      // عشر عمليات متراكمة على كل جهاز بلا أي مزامنة.
      for (var i = 0; i < 10; i++) {
        a.repos.records.upsertLocal({
          'id': 'ra$i', 'name': 'سالم', 'patient_name': 'سالم',
          'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
          'amount': 100 + i, 'payment': 'كاش',
        });
        b.repos.records.upsertLocal({
          'id': 'rb$i', 'name': 'سالم', 'patient_name': 'سالم',
          'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
          'amount': 200 + i, 'payment': 'كاش',
        });
        a.plans.add('سالم', 'ع1', 'مرحلة A$i');
        b.plans.add('سالم', 'ع1', 'مرحلة B$i');
      }
      await settleAll([a, b]);
      expectConverged(a, b);
      expect(a.domain('records').length, 20);
      expect(a.plans.read('سالم', 'ع1').length, 20);
    });

    test('تناوب سريع على نفس الحقل: الأحدث يفوز والجهازان متطابقان',
        () async {
      a.repos.records.upsertLocal({
        'id': 'r1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
        'amount': 100, 'payment': 'كاش',
      });
      await settleAll([a, b]);
      for (var i = 0; i < 5; i++) {
        final ra = Map<String, Object?>.from(a.repos.records.getById('r1')!);
        a.repos.records
            .upsertLocal({...ra, 'amount': 1000 + i}, base: ra);
        await a.sync();
        final rb = Map<String, Object?>.from(b.repos.records.getById('r1')!);
        b.repos.records
            .upsertLocal({...rb, 'amount': 2000 + i}, base: rb);
        await b.sync();
      }
      await settleAll([a, b]);
      expectConverged(a, b);
      expect(a.domain('records')['r1']!['amount'], 2004,
          reason: 'آخر كتابة فعلية لنفس الحقل تفوز');
    });

    test('قسط على جهاز وحذف الدين على الآخر: الحذف نهائي بلا بعث',
        () async {
      a.repos.debts.upsertLocal({
        'id': 'd1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'تركيبة', 'date': '2026-07-20',
        'amount': 500, 'total': 500, 'totalAmount': 500,
        'paidAmount': 0, 'remaining': 500, 'status': 'unpaid',
        'installments': <Object?>[],
      });
      await settleAll([a, b]);

      final snapB = Map<String, Object?>.from(b.repos.debts.getById('d1')!);
      b.repos.debts.upsertLocal({
        ...snapB,
        'installments': [
          {'id': 'i1', 'amount': 100, 'date': '2026-07-21'},
        ],
      }, base: snapB);
      a.repos.debts.delete('d1');
      await settleAll([a, b], rounds: 6);

      for (final d in [a, b]) {
        expect(d.repos.debts.getById('d1'), isNull,
            reason: '${d.name}: حذف الدين نهائي');
      }
      expectConverged(a, b);
    });

    test('إعادة تسمية مريض على جهاز مع تعديل سجله على الآخر: تقارب',
        () async {
      a.repos.records.upsertLocal({
        'id': 'r1', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
        'amount': 100, 'payment': 'كاش', 'phone': '0911',
      });
      await settleAll([a, b]);

      // A يعيد التسمية (اكتساح الجداول)، B يعدّل مبلغ نفس السجل.
      editPatientCascade(a.repos,
          origName: 'سالم', clinic: 'ع1',
          newName: 'سالم المحدث', phone: '0911');
      final rb = Map<String, Object?>.from(b.repos.records.getById('r1')!);
      b.repos.records.upsertLocal({...rb, 'amount': 750}, base: rb);
      await settleAll([a, b], rounds: 6);

      expectConverged(a, b);
      final row = a.domain('records')['r1']!;
      expect(row['name'], 'سالم المحدث', reason: 'إعادة التسمية نجت');
      expect(row['amount'], 750, reason: 'تعديل B نجا معها');
    });

    test('حذف المريض على جهاز مع مرحلة خطة جديدة على الآخر: تقارب حتمي',
        () async {
      a.plans.add('سالم', 'ع1', 'قديمة');
      await settleAll([a, b]);

      // B يضيف مرحلة، A يحذف كل مراحل المريض في الوقت نفسه.
      b.plans.add('سالم', 'ع1', 'جديدة من B');
      a.plans.removeAllFor('سالم', 'ع1');
      await settleAll([a, b], rounds: 6);

      // الدلالة الحتمية: القديمة (المعروفة لحظة الحذف) زالت،
      // والجديدة (لم يرها الحاذف) تبقى — والجهازان متطابقان.
      for (final d in [a, b]) {
        final descs =
            d.plans.read('سالم', 'ع1').map((s) => s.desc).toSet();
        expect(descs, {'جديدة من B'},
            reason: '${d.name}: الحذف طال المعروف وقتها فقط');
      }
      expectConverged(a, b);
    });

    test('فشل دفع في منتصف التبادل ثم استئناف: تقارب بلا فقدان', () async {
      a.repos.records.upsertLocal({
        'id': 'rA', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
        'amount': 111, 'payment': 'كاش',
      });
      b.repos.records.upsertLocal({
        'id': 'rB', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'ع1', 'service': 'حشو', 'date': '2026-07-20',
        'amount': 222, 'payment': 'كاش',
      });
      server.failPushes = 1; // أول دفع يفشل (انقطاع شبكة مصطنع)
      await a.sync(); // يفشل دفعه
      await b.sync();
      server.failPulls = 1; // ثم سحب يفشل
      await a.sync();
      await settleAll([a, b], rounds: 5);

      expectConverged(a, b);
      expect(a.domain('records').keys.toSet(), {'rA', 'rB'});
    });
  });

  group('م53/3 — ثلاثة أجهزة', () {
    test('إضافات وتعديلات من ثلاث نسخ: تقارب الجميع', () async {
      final server = FakeSyncServer();
      final a = Device('a', server);
      final b = Device('b', server);
      final c = Device('c', server);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);

      a.repos.settings.set('app.config', {
        'centerName': 'مركز', 'clinics': ['ع1'],
        'services': ['حشو'], 'payments': ['كاش'],
      });
      await settleAll([a, b, c]);

      a.plans.add('سالم', 'ع1', 'من A');
      b.plans.add('سالم', 'ع1', 'من B');
      c.plans.add('سالم', 'ع1', 'من C');
      a.repos.settings.configAddItem(const ['services'], 'خلع');
      b.repos.settings.configAddItem(const ['services'], 'تبييض');
      c.repos.settings.set(
          'app.config', {...c.config, 'currency': 'ر.س'});
      await settleAll([a, b, c], rounds: 5);

      for (final pair in [(a, b), (b, c), (a, c)]) {
        final diff = firstDiff(
            pair.$1.domain('records'), pair.$2.domain('records'));
        expect(diff, isNull);
        expect(deepEq(pair.$1.config, pair.$2.config), isTrue,
            reason:
                'إعدادات ${pair.$1.name}/${pair.$2.name} لم تتقارب');
      }
      for (final d in [a, b, c]) {
        expect(d.plans.read('سالم', 'ع1').length, 3,
            reason: '${d.name}: مراحل النسخ الثلاث');
        expect(<String>{
          for (final s in (d.config['services'] as List)) '$s',
        }, containsAll(const {'حشو', 'خلع', 'تبييض'}));
        expect(d.config['currency'], 'ر.س');
      }
    });
  });
}
