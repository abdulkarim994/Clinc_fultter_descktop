/// اختبار م50 (v29) — خطة العلاج بعد إعادة البناء: **كل مرحلة صف مستقل**
/// يتزامن بنفسه. جهازان حقيقيان (قاعدتا SQLite) عبر خادم بدلالات الخلفية:
///   • إضافة من كل جهاز ⇒ المرحلتان على الاثنين (لا تعارض أصلاً).
///   • تعليم الإنجاز على مرحلتين مختلفتين ⇒ الاثنان ينجوان.
///   • حذف مرحلة ⇒ تختفي على الجهازين ولا تُبعث بعد دورات.
///   • خطة قديمة في app.config ⇒ تُستورد مرة واحدة بلا تكرار، والمحذوف
///     منها لا يعود.
///   • العدّاد = طول القائمة، والعزل بالعيادة محفوظ.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/features/patients/treatment_plan_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m50_${name}_') {
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
    await engine.runCycle('test');
  }

  List<String> descsOf(String patient, String clinic) =>
      [for (final s in plans.read(patient, clinic)) s.desc];

  List<PlanStage> stagesOf(String patient, String clinic) =>
      plans.read(patient, clinic);

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

  test('إضافة مرحلة من كل جهاز: الاثنتان تظهران على الجهازين', () async {
    a.plans.add('سالم', 'الصفوة', 'تنظيف');
    await settle();
    expect(b.descsOf('سالم', 'الصفوة'), ['تنظيف']);

    // الآن كل جهاز يضيف مرحلته وهما غير متزامنين.
    a.plans.add('سالم', 'الصفوة', 'حشو عصب');
    b.plans.add('سالم', 'الصفوة', 'تركيبة');
    await settle();

    for (final d in [a, b]) {
      expect(d.descsOf('سالم', 'الصفوة').toSet(),
          {'تنظيف', 'حشو عصب', 'تركيبة'},
          reason: '${d.name}: لا جهاز يمسح مرحلة الآخر');
      expect(d.stagesOf('سالم', 'الصفوة').length, 3,
          reason: '${d.name}: العدّاد = طول القائمة');
    }
  });

  test('تعليم الإنجاز على مرحلتين مختلفتين: الاثنان ينجوان', () async {
    final s1 = a.plans.add('سالم', 'الصفوة', 'مرحلة أولى');
    final s2 = a.plans.add('سالم', 'الصفوة', 'مرحلة ثانية');
    await settle();

    a.plans.setDone('سالم', 'الصفوة', s1.id, true, doneDate: '2026-07-28');
    b.plans.setDone('سالم', 'الصفوة', s2.id, true, doneDate: '2026-07-28');
    await settle();

    for (final d in [a, b]) {
      final done = {
        for (final st in d.stagesOf('سالم', 'الصفوة')) st.desc: st.done
      };
      expect(done['مرحلة أولى'], true, reason: '${d.name}: إنجاز A نجا');
      expect(done['مرحلة ثانية'], true, reason: '${d.name}: إنجاز B نجا');
    }
  });

  test('حذف مرحلة: تختفي على الجهازين ولا تُبعث', () async {
    final s1 = a.plans.add('سالم', 'الصفوة', 'تبقى');
    final s2 = a.plans.add('سالم', 'الصفوة', 'تُحذف');
    await settle();
    expect(b.descsOf('سالم', 'الصفوة').length, 2);

    // A يحذف، وB يعدّل مرحلة أخرى في الوقت نفسه.
    a.plans.remove('سالم', 'الصفوة', s2.id);
    b.plans.setDone('سالم', 'الصفوة', s1.id, true);
    await settle();
    await settle(); // دورات إضافية: لا بعث للمحذوف

    for (final d in [a, b]) {
      expect(d.descsOf('سالم', 'الصفوة'), ['تبقى'],
          reason: '${d.name}: الحذف حتمي بلا بعث');
      expect(d.stagesOf('سالم', 'الصفوة').single.done, true,
          reason: '${d.name}: تعديل B نجا');
    }
  });

  test('استيراد خطة قديمة من الإعدادات مرة واحدة بلا تكرار', () async {
    // خطة بشكل الإعدادات القديم (كما هي على أجهزة المستخدم الآن).
    a.repos.settings.set('app.config', {
      'centerName': 'مركز',
      'clinics': ['الصفوة'],
      'treatmentPlans': {
        'سالم|الصفوة': [
          {'id': 'old1', 'desc': 'بلحح4', 'done': false, 'doneDate': ''},
          {'id': 'old2', 'desc': 'doddo', 'done': false, 'doneDate': ''},
        ],
      },
    });
    final cfg = Map<String, Object?>.from(
        a.repos.settings.get('app.config') as Map);

    // أول قراءة تستورد، والقراءة الثانية لا تكرّر.
    expect(a.plans.read('سالم', 'الصفوة', legacyConfig: cfg).length, 2);
    expect(a.plans.read('سالم', 'الصفوة', legacyConfig: cfg).length, 2,
        reason: 'الاستيراد مرة واحدة — بلا تكرار');

    await settle();
    expect(b.descsOf('سالم', 'الصفوة').toSet(), {'بلحح4', 'doddo'},
        reason: 'المراحل المستوردة تتزامن كصفوف مستقلة');

    // حذف مرحلة مستوردة لا يعيدها استيراد لاحق (شاهد قبرها موجود).
    a.plans.remove('سالم', 'الصفوة', 'old1');
    expect(a.plans.read('سالم', 'الصفوة', legacyConfig: cfg).length, 1,
        reason: 'المحذوف لا يعود بالاستيراد');
    await settle();
    expect(b.descsOf('سالم', 'الصفوة'), ['doddo']);
  });

  test('العزل بالعيادة: نفس الاسم بعيادتين خطتان مستقلتان', () async {
    a.plans.add('سالم', 'الصفوة', 'خطة الصفوة');
    a.plans.add('سالم', 'كاريزما', 'خطة كاريزما');
    await settle();

    for (final d in [a, b]) {
      expect(d.descsOf('سالم', 'الصفوة'), ['خطة الصفوة'],
          reason: '${d.name}: لا تسرب بين العيادتين');
      expect(d.descsOf('سالم', 'كاريزما'), ['خطة كاريزما']);
    }
  });
}
