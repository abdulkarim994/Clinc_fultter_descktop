/// اختبار م49 (v28) — «نسختان بنفس الحساب تُظهران خطة مختلفة»:
///   1) حفظ الواجهة من لقطة قديمة لا يمحو مرحلة وصلت لتوّها من الجهاز
///      الآخر (كتابة عبر الدمج بدل الكتابة الكاسحة).
///   2) نسختان تضيفان وتحفظان بالتناوب مع مزامنة خلفية ⇒ تتقاربان إلى
///      الاتحاد بلا فقدان أي مرحلة.
///   3) دورة أنتجت دمجاً تدفع نتيجته فوراً (لا انتظار المؤقّت).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/push.dart' show getPendingCount;
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m49_${name}_') {
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

  Future<void> sync() async {
    await engine.runCycle('test');
  }

  Map<String, Object?> get config {
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  List<Map<String, Object?>> stages(String key) {
    final plans = config['treatmentPlans'];
    final mine = plans is Map ? plans[key] : null;
    return mine is List
        ? [for (final s in mine) Map<String, Object?>.from(s as Map)]
        : <Map<String, Object?>>[];
  }

  /// حفظ كما تفعل الواجهة: من **لقطة** قد تكون قديمة.
  void saveFromSnapshot(
      Map<String, Object?> snapshot, String key, List<Object?> stages) {
    final cfg = Map<String, Object?>.from(snapshot);
    final plans = cfg['treatmentPlans'] is Map
        ? Map<String, Object?>.from(cfg['treatmentPlans'] as Map)
        : <String, Object?>{};
    plans[key] = stages;
    cfg['treatmentPlans'] = plans;
    repos.settings.set('app.config', cfg);
  }

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

Map<String, Object?> stage(String id, String desc) =>
    {'id': id, 'desc': desc, 'done': false, 'doneDate': ''};

const seedConfig = <String, Object?>{
  'centerName': 'مركز التقارب',
  'clinics': ['الصفوة'],
  'services': ['حشو'],
  'payments': ['كاش'],
};

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

  Future<void> seedBoth() async {
    a.repos.settings.set('app.config', {
      ...seedConfig,
      'treatmentPlans': {
        'سالم|الصفوة': [stage('s1', 'تنظيف')],
      },
    });
    await a.sync();
    await b.sync();
    await a.sync();
  }

  test('v30 — حفظ إعداد من لقطة قديمة لا يمحو إعداد الجهاز الآخر',
      () async {
    await seedBoth();

    // لقطة الواجهة تُقرأ الآن (بلا تعديلات B).
    final snapshot = a.config;

    // بين القراءة والحفظ: يصل تعديل B (العملة) ويُدمج في قاعدة A.
    b.repos.settings.set('app.config', {...b.config, 'currency': 'ر.س'});
    await b.sync();
    await a.sync();
    expect(a.config['currency'], 'ر.س', reason: 'وصل تعديل B إلى A');

    // الآن تحفظ واجهة A من لقطتها القديمة (بلا العملة الجديدة) + تعديلها.
    a.repos.settings
        .set('app.config', {...snapshot, 'centerName': 'مركز A'});

    expect(a.config['centerName'], 'مركز A', reason: 'تعديل A حُفظ');
    expect(a.config['currency'], 'ر.س',
        reason: 'v30 — الكتابة تمس الصفوف المتغيّرة فقط: تعديل B لم يُمحَ');
  });

  test('v30 — إضافة عيادة من كل جهاز بنداء صريح: الاثنتان تبقيان',
      () async {
    await seedBoth();

    // كل جهاز يضيف عيادته (نداء نية صريح ⇒ صف مستقل لكل عنصر).
    a.repos.settings.configAddItem(const ['clinics'], 'عيادة A');
    b.repos.settings.configAddItem(const ['clinics'], 'عيادة B');

    for (var i = 0; i < 3; i++) {
      await a.sync();
      await b.sync();
    }

    for (final d in [a, b]) {
      final clinics = <String>{
        for (final e in (d.config['clinics'] as List)) '$e',
      };
      expect(clinics, containsAll(const {'الصفوة', 'عيادة A', 'عيادة B'}),
          reason: '${d.name}: إضافتا الجهازين نجتا معاً');
    }
  });

  test('دورة أنتجت دمجاً تدفع نتيجتها فوراً بلا انتظار المؤقّت', () async {
    await seedBoth();

    // A يضيف ويدفع أولاً، ثم B يضيف من لقطته ويدفع فيكتب فوق صف الخادم.
    a.saveFromSnapshot(a.config, 'سالم|الصفوة',
        [...a.stages('سالم|الصفوة'), stage('a9', 'من A')]);
    await a.sync();
    b.saveFromSnapshot(b.config, 'سالم|الصفوة',
        [...b.stages('سالم|الصفوة'), stage('b9', 'من B')]);
    await b.sync();

    // دورة A الآن تسحب صف B وتدمج ⇒ نتيجة الدمج صفٌّ غير مدفوع.
    await a.sync();
    expect(a.stages('سالم|الصفوة').map((s) => s['id']).toSet(),
        {'s1', 'a9', 'b9'},
        reason: 'الدمج وحّد المرحلتين على A');

    // v28 — الدفع الفوري: بلا استدعاء مزامنة يدوي آخر، تنطلق دورة تالية
    // خلال أجزاء من الثانية فتُدفع نتيجة الدمج.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(getPendingCount(a.ctx), 0,
        reason: 'دُفعت نتيجة الدمج تلقائياً بلا انتظار المؤقّت');

    await b.sync();
    expect(b.stages('سالم|الصفوة').map((s) => s['id']).toSet(),
        {'s1', 'a9', 'b9'},
        reason: 'B استلم الاتحاد فوراً');
  });
}
