/// اختبار م51 (v30) — الإعدادات تحت التعديل المتزامن من جهازين:
/// كل تفضيل وكل عنصر قائمة صفٌّ مستقل يتزامن بنفسه، فلا يمسح جهاز عمل
/// الآخر. جهازان حقيقيان (قاعدتا SQLite) عبر خادم بدلالات الخلفية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m51_${name}_') {
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

  Set<String> list(String key) => <String>{
        for (final e in (config[key] is List ? config[key] as List : const []))
          '$e',
      };

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

  Future<void> seedBoth() async {
    a.repos.settings.set('app.config', {
      'centerName': 'مركز التقارب',
      'currency': 'د.ل',
      'doctorPct': 40,
      'clinics': ['الصفوة'],
      'services': ['حشو'],
      'payments': ['كاش'],
      'labs': ['مختبر أ'],
    });
    await settle();
    expect(b.config['centerName'], 'مركز التقارب');
  }

  test('إضافة عيادة من كل جهاز في نفس الوقت: الاثنتان تبقيان', () async {
    await seedBoth();
    a.repos.settings.configAddItem(const ['clinics'], 'عيادة A');
    b.repos.settings.configAddItem(const ['clinics'], 'عيادة B');
    await settle();

    for (final d in [a, b]) {
      expect(d.list('clinics'),
          containsAll(const {'الصفوة', 'عيادة A', 'عيادة B'}),
          reason: '${d.name}: لا جهاز يمسح عيادة الآخر');
    }
  });

  test('حذف عيادة على جهاز مع إضافة على الآخر: الحذف حتمي والإضافة باقية',
      () async {
    await seedBoth();
    a.repos.settings.configAddItem(const ['clinics'], 'قابلة للحذف');
    await settle();
    expect(b.list('clinics'), contains('قابلة للحذف'));

    a.repos.settings.configRemoveItem(const ['clinics'], 'قابلة للحذف');
    b.repos.settings.configAddItem(const ['clinics'], 'عيادة B');
    await settle();
    await settle(); // دورات إضافية: لا بعث للمحذوف

    for (final d in [a, b]) {
      expect(d.list('clinics'), isNot(contains('قابلة للحذف')),
          reason: '${d.name}: الحذف حتمي بلا بعث');
      expect(d.list('clinics'), contains('عيادة B'),
          reason: '${d.name}: إضافة B نجت');
      expect(d.list('clinics'), contains('الصفوة'));
    }
  });

  test('اسم المركز على جهاز والعملة على الآخر: الاثنان ينجوان', () async {
    await seedBoth();
    // كل جهاز يحفظ كائن الإعدادات كاملاً من لقطته (سلوك الشاشة).
    a.repos.settings.set('app.config', {...a.config, 'centerName': 'مركز A'});
    b.repos.settings.set('app.config', {...b.config, 'currency': 'ر.س'});
    await settle();

    for (final d in [a, b]) {
      expect(d.config['centerName'], 'مركز A',
          reason: '${d.name}: تعديل A نجا');
      expect(d.config['currency'], 'ر.س',
          reason: '${d.name}: تعديل B نجا');
      expect(d.config['doctorPct'], 40, reason: 'ما لم يُلمس لم يتغير');
    }
  });

  test('معالجتان جديدتان من جهازين + مختبران: الكل يبقى', () async {
    await seedBoth();
    a.repos.settings.configAddItem(const ['services'], 'خلع');
    b.repos.settings.configAddItem(const ['services'], 'تبييض');
    a.repos.settings.configAddItem(const ['labs'], 'مختبر ب');
    b.repos.settings.configAddItem(const ['labs'], 'مختبر ج');
    await settle();

    for (final d in [a, b]) {
      expect(d.list('services'), containsAll(const {'حشو', 'خلع', 'تبييض'}),
          reason: '${d.name}: المعالجات من الجهازين');
      expect(d.list('labs'),
          containsAll(const {'مختبر أ', 'مختبر ب', 'مختبر ج'}),
          reason: '${d.name}: المختبرات من الجهازين');
    }
  });

  test('نسبتان لمعالجتين في نفس العيادة: الاثنتان تبقيان', () async {
    await seedBoth();

    void setRate(Device d, String service, num pct) {
      final cfg = d.config;
      final rates = cfg['clinicRates'] is Map
          ? Map<String, Object?>.from(cfg['clinicRates'] as Map)
          : <String, Object?>{};
      final clinics = rates['clinics'] is Map
          ? Map<String, Object?>.from(rates['clinics'] as Map)
          : <String, Object?>{};
      final clinic = clinics['الصفوة'] is Map
          ? Map<String, Object?>.from(clinics['الصفوة'] as Map)
          : <String, Object?>{};
      final treatments = clinic['treatments'] is Map
          ? Map<String, Object?>.from(clinic['treatments'] as Map)
          : <String, Object?>{};
      treatments[service] = pct;
      clinic['treatments'] = treatments;
      clinics['الصفوة'] = clinic;
      rates['clinics'] = clinics;
      d.repos.settings.set('app.config', {...cfg, 'clinicRates': rates});
    }

    setRate(a, 'حشو', 55);
    setRate(b, 'خلع', 35);
    await settle();

    for (final d in [a, b]) {
      final t = ((((d.config['clinicRates'] as Map)['clinics'] as Map)
          ['الصفوة'] as Map)['treatments'] as Map);
      expect(t['حشو'], 55, reason: '${d.name}: نسبة A نجت');
      expect(t['خلع'], 35, reason: '${d.name}: نسبة B نجت');
    }
  });

  test('نفس الإعداد على الجهازين: الأحدث يفوز بلا مساس بالبقية', () async {
    await seedBoth();
    a.repos.settings.set('app.config', {...a.config, 'currency': 'A'});
    await settle();
    b.repos.settings.set('app.config', {...b.config, 'currency': 'B'});
    await settle();

    for (final d in [a, b]) {
      expect(d.config['currency'], 'B',
          reason: '${d.name}: تعارض على نفس الحقل ⇒ الأحدث');
      expect(d.config['centerName'], 'مركز التقارب',
          reason: '${d.name}: بقية الإعدادات لم تُمس');
      expect(d.list('clinics'), contains('الصفوة'));
    }
  });

  test('حفظ من لقطة قديمة لا يُرجع قيمة قديمة فوق تعديل الجهاز الآخر',
      () async {
    await seedBoth();
    final staleSnapshot = a.config; // لقطة قبل تعديل B

    b.repos.settings.set('app.config', {...b.config, 'doctorPct': 60});
    await settle();
    expect(a.config['doctorPct'], 60, reason: 'وصل تعديل B');

    // A يحفظ من لقطته القديمة (فيها 40) مع تعديل حقل آخر.
    // الشاشة تمرّر لقطتها الأساس (سلوك v30): يُكتب ما غيّرته فقط.
    a.repos.settings.set(
        'app.config', {...staleSnapshot, 'centerName': 'مركز A'},
        configBase: staleSnapshot);
    await settle();

    for (final d in [a, b]) {
      expect(d.config['doctorPct'], 60,
          reason: '${d.name}: القيمة القديمة لم تُرجَّع');
      expect(d.config['centerName'], 'مركز A');
    }
  });
}
