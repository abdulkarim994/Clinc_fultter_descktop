/// اختبار م48 (v27) — «جهاز يمسح بيانات الجهاز الآخر» في خطة العلاج
/// والإعدادات: قاعدتا SQLite حقيقيتان تتزامنان عبر خادم مزيف بدلالات
/// الخلفية نفسها، ويجب أن **ينجو عمل الجهازين معاً** لا الأحدث فقط.
///
/// السبب الجذري قبل v27: دمج `app.config` كان يفكك المستوى الأول فقط،
/// فقيمة كل مفتاح متداخل (خطة مريض كاملة/بطاقة طبية كاملة/نسب عيادة)
/// ورقةٌ تُحسم بالساعة الأحدث ⇒ الأحدث يمسح الآخر.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/merge/config_tombs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m48_${name}_') {
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

  Map<String, Object?> get config {
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  void writeConfig(Map<String, Object?> cfg) =>
      repos.settings.set('app.config', cfg);

  /// مراحل خطة مريض كما تقرأها الواجهة.
  List<Map<String, Object?>> stages(String key) {
    final plans = config['treatmentPlans'];
    final mine = plans is Map ? plans[key] : null;
    return mine is List
        ? [for (final s in mine) Map<String, Object?>.from(s as Map)]
        : <Map<String, Object?>>[];
  }

  void setStages(String key, List<Map<String, Object?>> st) {
    final cfg = config;
    final plans = cfg['treatmentPlans'] is Map
        ? Map<String, Object?>.from(cfg['treatmentPlans'] as Map)
        : <String, Object?>{};
    plans[key] = st;
    cfg['treatmentPlans'] = plans;
    writeConfig(cfg);
  }

  /// حذف مرحلة كما تفعل الواجهة تماماً: إسقاطها + شاهد حذف صريح.
  void deleteStage(String key, String id) {
    final cfg = config;
    final plans = cfg['treatmentPlans'] is Map
        ? Map<String, Object?>.from(cfg['treatmentPlans'] as Map)
        : <String, Object?>{};
    final list = plans[key] is List ? List<Object?>.from(plans[key] as List) : [];
    plans[key] = [
      for (final el in list)
        if (!(el is Map && '${el['id']}' == id)) el,
    ];
    cfg['treatmentPlans'] = plans;
    writeConfig(markItemDeleted(cfg, planTombPath(key), id));
  }

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

Map<String, Object?> stage(String id, String desc,
        {bool done = false, String doneDate = ''}) =>
    {'id': id, 'desc': desc, 'done': done, 'doneDate': doneDate};

const seedConfig = <String, Object?>{
  'centerName': 'مركز التقارب',
  'clinics': ['الصفوة'],
  'services': ['حشو', 'خلع'],
  'payments': ['كاش'],
};

void main() {
  late FakeSyncServer server;
  late Device a;
  late Device b;

  setUp(() async {
    server = FakeSyncServer();
    a = Device('a', server);
    b = Device('b', server);
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  /// حالة أساس مشتركة: A يكتب ويزامن، B يزامن فيلتقطها (وتُضبط لقطة
  /// الأساس/الظل على الجهازين — شرط الدمج الثلاثي).
  Future<void> seedBoth(Map<String, Object?> cfg) async {
    a.writeConfig(cfg);
    await a.sync();
    await b.sync();
    await a.sync();
  }

  /// دورات تبادل حتى الاستقرار (الدفع ثم السحب على الجهازين).
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await a.sync();
      await b.sync();
    }
  }

  test('مرحلتان من جهازين لنفس المريض: الاثنتان تبقيان', () async {
    await seedBoth({
      ...seedConfig,
      'treatmentPlans': {
        'سالم|الصفوة': [stage('s1', 'تنظيف')],
      },
    });
    expect(b.stages('سالم|الصفوة').length, 1, reason: 'الأساس وصل B');

    // كل جهاز يضيف مرحلة مختلفة لنفس المريض وهما غير متزامنين.
    a.setStages('سالم|الصفوة',
        [...a.stages('سالم|الصفوة'), stage('s2', 'حشو عصب')]);
    b.setStages('سالم|الصفوة',
        [...b.stages('سالم|الصفوة'), stage('s3', 'تركيبة')]);

    await settle();

    for (final d in [a, b]) {
      final ids = d.stages('سالم|الصفوة').map((s) => s['id']).toSet();
      expect(ids, {'s1', 's2', 's3'},
          reason: '${d.name}: لا جهاز يمسح مرحلة الآخر');
      // لا شواهد قبور مكتوبة في الإعدادات (توافق Vue).
      expect(
          d.stages('سالم|الصفوة').every((s) => s['desc'] != null),
          isTrue);
    }
  });

  test('تعديل حقلين مختلفين في نفس البطاقة الطبية: الاثنان يبقيان',
      () async {
    await seedBoth({
      ...seedConfig,
      'patientMedical': {
        'سالم|الصفوة': {
          'age': '30',
          'gender': '',
          'chronic': ['سكري'],
          'diagnosis': '',
          'notes': '',
        },
      },
    });

    void edit(Device d, Map<String, Object?> patch) {
      final cfg = d.config;
      final med = Map<String, Object?>.from(cfg['patientMedical'] as Map);
      final card = Map<String, Object?>.from(med['سالم|الصفوة'] as Map);
      card.addAll(patch);
      med['سالم|الصفوة'] = card;
      cfg['patientMedical'] = med;
      d.writeConfig(cfg);
    }

    edit(a, {'diagnosis': 'التهاب لثة'});
    edit(b, {
      'gender': 'ذكر',
      'chronic': ['سكري', 'ضغط'],
    });

    await settle();

    for (final d in [a, b]) {
      final card = Map<String, Object?>.from(
          (d.config['patientMedical'] as Map)['سالم|الصفوة'] as Map);
      expect(card['diagnosis'], 'التهاب لثة',
          reason: '${d.name}: تشخيص A نجا');
      expect(card['gender'], 'ذكر', reason: '${d.name}: جنس B نجا');
      expect((card['chronic'] as List).toSet(), {'سكري', 'ضغط'},
          reason: '${d.name}: الأمراض المزمنة اتحاد الجهازين');
      expect(card['age'], '30');
    }
  });

  test('نسبتان لمعالجتين في نفس العيادة: الاثنتان تبقيان', () async {
    await seedBoth({
      ...seedConfig,
      'clinicRates': {
        'clinics': {
          'الصفوة': {
            'treatments': {'حشو': 40},
          },
        },
      },
    });

    void setRate(Device d, String service, num pct) {
      final cfg = d.config;
      final rates = Map<String, Object?>.from(cfg['clinicRates'] as Map);
      final clinics = Map<String, Object?>.from(rates['clinics'] as Map);
      final clinic = Map<String, Object?>.from(clinics['الصفوة'] as Map);
      final treatments =
          Map<String, Object?>.from(clinic['treatments'] as Map);
      treatments[service] = pct;
      clinic['treatments'] = treatments;
      clinics['الصفوة'] = clinic;
      rates['clinics'] = clinics;
      cfg['clinicRates'] = rates;
      d.writeConfig(cfg);
    }

    setRate(a, 'حشو', 55); // A يعدّل نسبة معالجة قائمة
    setRate(b, 'خلع', 35); // B يضيف نسبة معالجة أخرى بنفس العيادة

    await settle();

    for (final d in [a, b]) {
      final t = ((((d.config['clinicRates'] as Map)['clinics'] as Map)
          ['الصفوة'] as Map)['treatments'] as Map);
      expect(t['حشو'], 55, reason: '${d.name}: تعديل A نجا');
      expect(t['خلع'], 35, reason: '${d.name}: إضافة B نجت');
    }
  });

  test('حذف مرحلة على جهاز مع تعديل آخر: الحذف يصمد بلا بعث', () async {
    await seedBoth({
      ...seedConfig,
      'treatmentPlans': {
        'سالم|الصفوة': [
          stage('s1', 'تنظيف'),
          stage('s2', 'حشو'),
        ],
      },
    });
    expect(b.stages('سالم|الصفوة').length, 2);

    // A يحذف s2، وB يعلّم s1 منجزة (تعديل متزامن على عنصر آخر).
    a.deleteStage('سالم|الصفوة', 's2');
    b.setStages('سالم|الصفوة', [
      for (final s in b.stages('سالم|الصفوة'))
        if (s['id'] == 's1')
          {...s, 'done': true, 'doneDate': '2026-07-28'}
        else
          s,
    ]);

    await settle();

    for (final d in [a, b]) {
      final st = d.stages('سالم|الصفوة');
      expect(st.map((s) => s['id']).toSet(), {'s1'},
          reason: '${d.name}: الحذف صمد ولم تُبعث s2');
      expect(st.single['done'], true,
          reason: '${d.name}: تعديل B على s1 نجا');
    }
  });

  test('مراحل قديمة بلا معرّف: سقوط آمن بلا فقدان', () async {
    await seedBoth({
      ...seedConfig,
      'treatmentPlans': {
        'سالم|الصفوة': [
          {'desc': 'مرحلة قديمة بلا معرّف', 'done': false},
        ],
      },
    });

    // B يضيف مرحلة حديثة (بمعرّف) فوق القائمة القديمة.
    b.setStages('سالم|الصفوة', [
      ...b.stages('سالم|الصفوة'),
      stage('s9', 'مرحلة جديدة'),
    ]);
    await settle();

    for (final d in [a, b]) {
      final descs =
          d.stages('سالم|الصفوة').map((s) => s['desc']).toSet();
      expect(descs, contains('مرحلة قديمة بلا معرّف'),
          reason: '${d.name}: لا فقدان للمراحل القديمة');
      expect(descs, contains('مرحلة جديدة'));
    }
  });
}
