/// م170 — اختبارات إدارة العيادات المتقدمة:
///   • تعديل الاسم «للجديد فقط»: أرشفة الاسم القديم (الصفوف لا تُمس)
///     ونسخ نسب الطبيب للاسم الجديد.
///   • جرد الحذف بأرقامٍ فعلية (سجلات/تحاليل/تركيبات/ديون/مواعيد/مرضى).
///   • تجميد اللقطة المالية الشهرية قبل الحذف (كاش/تحويل/تركيبات/تحاليل/
///     أرباح) وقراءتها بصفوف الشهر ومجاميعه.
///   • deleteClinicCascade: كنسٌ حقيقي شامل مع بقاء اللقطة المجمدة وبقاء
///     بيانات العيادات الأخرى سليمةً حرفياً، وتنظيف config والنسب.
///
/// النمط: ProviderContainer + dbDir مؤقت (توأم analyses_test) — بلا واجهات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/settings/clinic_admin.dart';
import 'package:dental_clinic_flutter/features/xrays/storage_meter.dart'
    show StorageMeter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late ProviderContainer c;

  Map<String, Object?> baseConfig() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1', 'ع2'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'doctorPct': 50,
        'clinicRates': {
          'clinics': {
            'ع1': {
              'treatments': {'حشو': 40},
              'prosthetics': 30,
            },
          },
        },
        'analyses3': {'enabled': true, 'price': 50, 'repeatMonths': 6},
      };

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('m170_');
    c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', baseConfig());
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> cfg() => Map<String, Object?>.from(
      c.read(reposProvider).settings.get('app.config') as Map);

  /// بذر بيانات لعيادتين: سجلان + تحليل + تركيبة + دين + موعدان لع1،
  /// وسجلٌ واحد لع2 (شاهد سلامة الجارة).
  void seed() {
    final repos = c.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'مريض أول',
      'date': '2026-07-10',
      'amount': 500,
      'paid': 500,
      'payment': 'كاش',
      'clinic': 'ع1',
      'service': 'حشو',
      '_t': 'r',
    });
    repos.records.upsertLocal({
      'id': 'r2',
      'name': 'مريض ثانٍ',
      'date': '2026-08-05',
      'amount': 300,
      'paid': 300,
      'payment': 'تحويل',
      'clinic': 'ع1',
      'service': 'حشو',
      '_t': 'r',
    });
    // صف تحليلٍ ثلاثي (isAnalysis: 1 — معزول مالياً بقسمه المستقل).
    repos.records.upsertLocal({
      'id': 'a1',
      'name': 'مريض أول',
      'date': '2026-07-10',
      'amount': 50,
      'paid': 50,
      'payment': 'كاش',
      'clinic': 'ع1',
      'isAnalysis': 1,
      'analysisName': 'التحاليل الثلاثية',
      '_t': 'r',
    });
    repos.prosthetics.upsertLocal({
      'id': 'p1',
      'name': 'مريض أول',
      'date': '2026-07-15',
      'total': 800,
      'doctorShare': 240,
      'payment': 'كاش',
      'clinic': 'ع1',
      '_t': 'p',
    });
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'مريض ثانٍ',
      'date': '2026-08-05',
      'amount': 200,
      'remaining': 200,
      'clinic': 'ع1',
      '_t': 'd',
    });
    repos.appointments.upsertLocal({
      'id': 'ap1',
      'name': 'مريض أول',
      'date': '2026-08-20',
      'time': '10:00',
      'clinic': 'ع1',
      'status': 'pending',
      '_t': 'a',
    });
    repos.appointments.upsertLocal({
      'id': 'ap2',
      'name': 'استراحة',
      'date': '2026-08-20',
      'time': '12:00',
      'clinic': 'ع1',
      'isBreak': 1,
      'status': 'pending',
      '_t': 'a',
    });
    // عيادة الجارة ع2 — يجب ألا تُمس إطلاقاً.
    repos.records.upsertLocal({
      'id': 'n1',
      'name': 'جار سليم',
      'date': '2026-08-05',
      'amount': 900,
      'paid': 900,
      'payment': 'كاش',
      'clinic': 'ع2',
      'service': 'حشو',
      '_t': 'r',
    });
  }

  group('م170 — تعديل الاسم «للجديد فقط» (الأرشفة)', () {
    test('يستبدل بالقائمة النشطة ويؤرشف القديم وينسخ النسب والصفوف لا تُمس',
        () {
      seed();
      final repos = c.read(reposProvider);
      final ok = renameClinicNewOnly(repos, 'ع1', 'ع1 الجديدة');
      expect(ok, isTrue);
      final cf = cfg();
      expect((cf['clinics'] as List), contains('ع1 الجديدة'));
      expect((cf['clinics'] as List), isNot(contains('ع1')));
      expect(archivedClinicsOf(cf), contains('ع1'));
      // النسب نُسخت للاسم الجديد (والقديمة باقية للتاريخ).
      final rates =
          ((cf['clinicRates'] as Map)['clinics'] as Map);
      expect(rates.containsKey('ع1 الجديدة'), isTrue);
      expect(rates.containsKey('ع1'), isTrue);
      // الصفوف التاريخية لم تُمس — ما زالت باسم ع1.
      final oldRows = repos.records
          .getAll()
          .where((r) => r['clinic'] == 'ع1')
          .length;
      expect(oldRows, 3, reason: 'سجلان + تحليل — بلا إعادة ختم');
      expect(
          repos.records.getAll().where((r) => r['clinic'] == 'ع1 الجديدة'),
          isEmpty);
    });

    test('يرفض اسماً موجوداً أو فارغاً', () {
      seed();
      final repos = c.read(reposProvider);
      expect(renameClinicNewOnly(repos, 'ع1', 'ع2'), isFalse);
      expect(renameClinicNewOnly(repos, 'ع1', ''), isFalse);
      expect(renameClinicNewOnly(repos, 'غائبة', 'س'), isFalse);
    });
  });

  group('م170 — جرد الحذف', () {
    test('أرقام الجرد الفعلية لعيادة ع1', () {
      seed();
      final inv =
          clinicDeleteInventory(c.read(reposProvider), cfg(), 'ع1');
      expect(inv.records, 2, reason: 'سجلان (التحليل يُعد مستقلاً)');
      expect(inv.analyses, 1);
      expect(inv.pros, 1);
      expect(inv.debts, 1);
      expect(inv.appts, 2);
      expect(inv.patients, 2);
    });
  });

  group('م170 — تجميد اللقطة المالية', () {
    test('أشهر النشاط بقيمها: يوليو (كاش+تركيبات+تحليل) وأغسطس (تحويل)',
        () {
      seed();
      final frozen =
          freezeClinicFinance(c.read(reposProvider), cfg(), 'ع1');
      expect(frozen.keys, containsAll(['2026-07', '2026-08']));
      final jul = frozen['2026-07']!;
      expect(jul['cash'], 500);
      expect(jul['prosCash'], 800);
      expect(jul['analCash'], 50);
      final aug = frozen['2026-08']!;
      expect(aug['xfer'], 300);
      // قارئا الصفوف والمجاميع.
      final cfgWithFrozen = {
        ...cfg(),
        kDeletedClinicsFinanceKey: {'ع1': frozen},
      };
      final rows = frozenRowsForMonth(cfgWithFrozen, '2026-07');
      expect(rows.length, 1);
      expect(rows.first.clinic, 'ع1');
      final tot = frozenTotalsForMonth(cfgWithFrozen, '2026-07');
      expect(tot.cash, 500);
      expect(tot.prosCash, 800);
      expect(tot.analCash, 50);
    });
  });

  group('م170 — الحذف الحقيقي الشامل', () {
    test('يجمد المالية ويكنس صفوف ع1 كلها ويبقي ع2 سليمة وينظف config',
        () {
      seed();
      final repos = c.read(reposProvider);
      final touched = deleteClinicCascade(
        repos,
        clinic: 'ع1',
        db: c.read(localDbProvider),
        meter: StorageMeter(c.read(localDbProvider)),
      );
      expect(touched, greaterThan(0));
      // كل صفوف ع1 زالت (سجلات/تحاليل/تركيبات/ديون/مواعيد + الاستراحة).
      expect(
          repos.records.getAll().where((r) => r['clinic'] == 'ع1'), isEmpty);
      expect(repos.prosthetics.getAll().where((r) => r['clinic'] == 'ع1'),
          isEmpty);
      expect(
          repos.debts.getAll().where((r) => r['clinic'] == 'ع1'), isEmpty);
      expect(repos.appointments.getAll().where((r) => r['clinic'] == 'ع1'),
          isEmpty);
      // الجارة ع2 سليمة حرفياً.
      final neighbor =
          repos.records.getAll().where((r) => r['clinic'] == 'ع2').toList();
      expect(neighbor.length, 1);
      expect(neighbor.first['amount'], 900);
      // config: العيادة أزيلت من القائمة والنسب، واللقطة المجمدة حاضرة.
      final cf = cfg();
      expect((cf['clinics'] as List), isNot(contains('ع1')));
      // دمج الإعدادات يقلم الخرائط الفارغة — يكفي زوال مدخل ع1.
      final ratesClinics =
          ((cf['clinicRates'] as Map?)?['clinics'] as Map?) ?? const {};
      expect(ratesClinics.containsKey('ع1'), isFalse);
      final frozen = frozenClinicsFinanceOf(cf);
      expect(frozen.containsKey('ع1'), isTrue,
          reason: 'السجل المالي القديم يبقى (قرار المالك)');
      final tot = frozenTotalsForMonth(cf, '2026-07');
      expect(tot.cash, 500);
      expect(tot.prosCash, 800);
      expect(tot.analCash, 50);
      // شواهد القبور: الصفوف حُذفت حذفاً حقيقياً (لا صفوف حية بالمعرفات).
      expect(repos.records.getById('r1'), isNull);
      expect(repos.appointments.getById('ap2'), isNull);
    });
  });
}
