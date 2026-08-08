/// اختبارات م19 — ترحيل خطة العلاج مع تغيير اسم المريض:
/// التوأم الحرفي لكتلة PatientsTab.vue (السطور 608–610):
///   if (nameChanged && config.treatmentPlans[oldName]) {
///     plans[newName] = plans[oldName]; delete plans[oldName] }
/// كان الاكتساح ينقل صفوف الجداول الأربعة ويترك الخطة معلّقة على الاسم
/// القديم فتختفي من الملف الجديد (وتبقى جثةً باسمٍ لم يعد موجوداً).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m19_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    final repos = c.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'r1', 'name': 'هدى القديمة', 'clinic': 'ع1',
      'date': '2026-07-20', 'amount': 100, 'payment': 'كاش',
    });
    repos.settings.set('app.config', {
      'treatmentPlans': {
        'هدى القديمة': [
          {'id': 't1', 'desc': 'تنظيف', 'done': true, 'doneDate': '2026-07-20'},
        ],
        'مريض آخر': [
          {'id': 't9', 'desc': 'حشو', 'done': false, 'doneDate': ''},
        ],
      },
    });
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('تغيير الاسم يرحّل الخطة إلى الاسم الجديد ويحذف القديم ولا يمس غيرها',
      () {
    final repos = c.read(reposProvider);
    final touched = editPatientCascade(
      repos,
      origName: 'هدى القديمة',
      newName: 'هدى الجديدة',
    );
    expect(touched, greaterThanOrEqualTo(2)); // صف السجل + ترحيل الخطة

    final cfg = repos.settings.get('app.config') as Map;
    final plans = cfg['treatmentPlans'] as Map;
    expect(plans.containsKey('هدى القديمة'), isFalse);
    final moved = plans['هدى الجديدة'] as List;
    expect(moved, hasLength(1));
    expect((moved.single as Map)['desc'], 'تنظيف');
    expect((moved.single as Map)['done'], true);
    // خطة مريض آخر لم تُمس.
    expect((plans['مريض آخر'] as List), hasLength(1));
    // السجل نفسه انتقل للاسم الجديد (الاكتساح الأصلي).
    final recs = repos.records.getAll();
    expect(recs.single['name'], 'هدى الجديدة');
  });

  test('بلا تغيير اسم: الخطة لا تُرحّل ولا تُكتب الإعدادات عبثاً', () {
    final repos = c.read(reposProvider);
    editPatientCascade(
      repos,
      origName: 'هدى القديمة',
      newName: 'هدى القديمة',
      phone: '0911111111',
    );
    final plans = (repos.settings.get('app.config') as Map)['treatmentPlans']
        as Map;
    expect(plans.containsKey('هدى القديمة'), isTrue);
    expect(repos.records.getAll().single['phone'], '0911111111');
  });

  test('تغيير اسم مريض بلا خطة: لا كتابة إعدادات (لا صف settings قذر جديد)',
      () {
    final repos = c.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'r2', 'name': 'بلا خطة', 'clinic': 'ع1',
      'date': '2026-07-21', 'amount': 50, 'payment': 'كاش',
    });
    final before =
        '${(repos.settings.get('app.config') as Map)['treatmentPlans']}';
    editPatientCascade(repos, origName: 'بلا خطة', newName: 'اسم جديد');
    final after =
        '${(repos.settings.get('app.config') as Map)['treatmentPlans']}';
    expect(after, before); // الخطط كما هي حرفياً
    expect(
        repos.records
            .getAll()
            .where((r) => r['name'] == 'اسم جديد')
            .length,
        1);
  });
}
