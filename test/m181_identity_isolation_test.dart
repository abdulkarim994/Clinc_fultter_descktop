/// اختبارات م181/ب — العزل الجذري لهوية المريض المتشابه (قرار المالك:
/// «احتاج جذري وليس ترميم... عزل حقيقي بالقيم والسجلات داخل نفس العيادة»):
///
///  • **سكّ الكتابة**: سجل الدفعة الأولى (record_saver) وسجل دفعة الدين
///    (debt_actions) يحملان الهاتف + patient_id — كانا بلا هوية فيلدان
///    مريض «بلا رقم» شبحاً بصفر قيم («ملفان بدل ملف» — بلاغ المالك).
///  • **حلّال القراءة الموروث** (IdentityIndex): دفعةُ ما قبل م181 بلا
///    هاتفٍ تُحلّ لهوية دينها وسجلها عبر الروابط القائمة — فتُصلَح
///    البيانات المكسورة الحالية قراءةً، حتمياً وبلا هجرة كتابة.
///  • **ترويسة الملف** (patientForClinic): ترشيحٌ بالهوية ثم بناءٌ بلا
///    انقسام — فلا 0/0/0 أبداً (تطابق الترويسة الصفوف الظاهرة).
///  • **هوية الملاحة** (navIdentityOf): فتح الملف من أي صف دفترٍ يمرّ
///    بالحلّال — لا فتح مدموجاً يخلط سميّاً بسميّه.
///  • **الاكتساح**: تعديل بيانات هويةٍ يعيد سكّ patient_id ولا يمسّ
///    السميّ (بما فيه دفعاته القديمة بلا هاتف — تتبع دينها).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    show SaveRecordInput, saveNewRecord;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

/// بذرة بلاغ المالك حرفياً (بيانات ما قبل م181 المكسورة):
/// سميّان «محمد حسين» في «عيادة ا» — الأول تركيبات 1500 كاش بهاتفه،
/// والثاني حالة 1500 ديناً بدفعة أولى 500 بهاتفه، ودفعتُه **بلا هاتف**
/// (الثغرة القديمة) مربوطة بدينه عبر debtId.
({List<JMap> recs, List<JMap> pros, List<JMap> dbts}) ownerScenario() {
  final pros = <JMap>[
    {
      'id': 'pa', 'name': 'محمد حسين', 'patient_name': 'محمد حسين',
      'clinic': 'عيادة ا', 'phone': '0919292254',
      'service': 'تركيبات', 'date': '2026-08-14',
      'total': 1500, 'payment': 'كاش', 'isDebt': 0, '_t': 'p',
    },
  ];
  final recs = <JMap>[
    {
      'id': 'rb', 'name': 'محمد حسين', 'patient_name': 'محمد حسين',
      'clinic': 'عيادة ا', 'phone': '09192922258',
      'service': 'حشو عصب أمامي', 'date': '2026-08-14',
      'amount': 1500, 'payment': 'دين', 'isDebt': 1, '_t': 'r',
    },
    {
      // الدفعة الأولى — **بلا هاتف** (كما كتبها record_saver قبل م181).
      'id': 'rp', 'name': 'محمد حسين', 'patient_name': 'محمد حسين',
      'clinic': 'عيادة ا',
      'service': 'دفعة أولى (دين)', 'date': '2026-08-14',
      'amount': 500, 'payment': 'تحويل',
      'isDebt': 0, 'isDebtPayment': 1, 'debtId': 'db', '_t': 'r',
    },
  ];
  final dbts = <JMap>[
    {
      'id': 'db', 'name': 'محمد حسين', 'patient_name': 'محمد حسين',
      'clinic': 'عيادة ا', 'phone': '09192922258',
      'service': 'حشو عصب أمامي', 'date': '2026-08-14',
      'type': 'regular', 'status': 'partial',
      'totalAmount': 1500, 'total': 1500,
      'paidAmount': 500, 'remaining': 1000,
      'recordId': 'rb', '_t': 'd',
    },
  ];
  return (recs: recs, pros: pros, dbts: dbts);
}

void main() {
  group('م181/ب — الحلّال الموروث يصلح بيانات ما قبل م181', () {
    test('لا «بلا رقم» شبح: الدفعة بلا هاتف تتبع دينها (سيناريو المالك)',
        () {
      final s = ownerScenario();
      final map = buildPatientMap(s.recs, s.pros, s.dbts);
      // ملفان اثنان فقط — لا ثالث شبحاً (كان قبل الإصلاح 3 مع «بلا رقم»).
      expect(map.length, 2,
          reason: 'دفعة بلا هاتف ترث هوية دينها عبر debtId — لا شبح');
      expect(map.values.any((a) => a.identity == 'none'), isFalse);

      // ملف أ (0919292254): تركيباته وحدها — 1500/1500.
      final a = map.values
          .singleWhere((x) => x.identity == 'p:0919292254');
      expect(a.grossTotal, 1500);
      expect(a.total, 1500);
      expect(a.debtRemaining, 0);
      expect(a.visitCount, 1);

      // ملف ب (09192922258): حالته الدَّينية + دفعتُه الموروثة — قيمه
      // كما في لقطات المالك: إجمالي 1500، محصَّل 500، متبقٍّ 1000.
      final b = map.values
          .singleWhere((x) => x.identity == 'p:09192922258');
      expect(b.grossTotal, 1500);
      expect(b.total, 500, reason: 'المحصَّل = مدفوع الدين وحده');
      expect(b.debtRemaining, 1000);
      expect(b.entries.any((e) => e['id'] == 'rp'), isTrue,
          reason: 'الدفعة اليتيمة صارت ضمن ملف صاحبها');
    });

    test('phoneOf: خام ← مسكوك ← موروث عبر الروابط (وعمقها المركّب)', () {
      final s = ownerScenario();
      final idx = IdentityIndex(s.recs, s.pros, s.dbts);
      // خام.
      expect(idx.phoneOf(s.recs[0]), '09192922258');
      // موروث عبر debtId (دفعة ← دين).
      expect(idx.phoneOf(s.recs[1]), '09192922258');
      // موروث بقفزتين: دفعةٌ لدينٍ بلا هاتف مربوطٍ بسجلٍ بهاتف.
      final rec = <JMap>[
        {'id': 'r1', 'name': 'س', 'clinic': 'ع', 'phone': '0911'},
        {'id': 'p1', 'name': 'س', 'clinic': 'ع',
          'isDebtPayment': 1, 'debtId': 'd1'},
      ];
      final dbt = <JMap>[
        {'id': 'd1', 'name': 'س', 'clinic': 'ع', 'recordId': 'r1'},
      ];
      final idx2 = IdentityIndex(rec, const [], dbt);
      expect(idx2.phoneOf(rec[1]), '0911',
          reason: 'دفعة ← دين ← سجل (قفزتان)');
      expect(idx2.phoneOf(dbt[0]), '0911', reason: 'دين ← سجله');
      // مسكوك: patient_id يحمل الهاتف حين يغيب الحقل الخام.
      expect(
          idx2.phoneOf({'id': 'x', 'patient_id': 'p:0922:اسم'}), '0922');
      // بلا أي مصدر ⇒ فارغ («بلا رقم» حقيقةً).
      expect(idx2.phoneOf({'id': 'y', 'name': 'س'}), '');
    });

    test('مريض بلا هاتف حقيقةً (بلا روابط) يبقى «بلا رقم» — عقد م90', () {
      final recs = <JMap>[
        {'id': '1', 'name': 'س', 'clinic': 'ع', 'phone': '0911',
          'amount': 100, 'date': '2026-08-01', 'payment': 'كاش'},
        {'id': '2', 'name': 'س', 'clinic': 'ع', 'phone': '0922',
          'amount': 200, 'date': '2026-08-02', 'payment': 'كاش'},
        {'id': '3', 'name': 'س', 'clinic': 'ع',
          'amount': 50, 'date': '2026-08-03', 'payment': 'كاش'},
      ];
      final map = buildPatientMap(recs, const [], const []);
      expect(map.length, 3);
      expect(map.values.where((a) => a.identity == 'none').length, 1,
          reason: 'لا تخمين: بلا هاتف ولا روابط = «بلا رقم» مستقل');
    });
  });

  group('م181/ب — ترويسة الملف (patientForClinic)', () {
    test('هوية ب: الترويسة 1500/500/1000 رغم دفعةٍ بلا هاتف', () {
      final s = ownerScenario();
      final b = patientForClinic('محمد حسين', 'عيادة ا',
          records: s.recs, prosthetics: s.pros, debts: s.dbts,
          identity: 'p:09192922258')!;
      expect(b.grossTotal, 1500);
      expect(b.total, 500);
      expect(b.debtRemaining, 1000);
      // الدفعة الموروثة ضمن قيود الهوية (تظهر في «الزيارات»).
      expect(b.entries.any((e) => e['id'] == 'rp'), isTrue);
    });

    test('هوية «بلا رقم» في سيناريو المالك = لا شيء (الشبح زال)', () {
      final s = ownerScenario();
      final ghost = patientForClinic('محمد حسين', 'عيادة ا',
          records: s.recs, prosthetics: s.pros, debts: s.dbts,
          identity: 'none');
      expect(ghost, isNull,
          reason: 'كل الصفوف تُحلّ لهاتفٍ — لا صفوف «بلا رقم»');
    });

    test('بلا هوية على مجموعة منقسمة: تجميعة موحّدة (لا null ⇒ لا 0/0/0)',
        () {
      final s = ownerScenario();
      final merged = patientForClinic('محمد حسين', 'عيادة ا',
          records: s.recs, prosthetics: s.pros, debts: s.dbts);
      expect(merged, isNotNull,
          reason: 'م181: البناء بلا انقسام — مفتاح الاسم يجدها دائماً');
      expect(merged!.grossTotal, 3000, reason: '1500 تركيبات + 1500 دين');
      expect(merged.total, 2000, reason: '1500 كاش + 500 مدفوع الدين');
      expect(merged.debtRemaining, 1000);
    });
  });

  group('م181/ب — هوية الملاحة (navIdentityOf) والكتابة المسكوكة', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m181b_');
      c = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Map<String, Object?> cfg() => {
          'centerName': 'مركز', 'clinics': ['عيادة ا'],
          'services': ['حشو عصب أمامي', 'تركيبات'], 'payments': ['كاش', 'تحويل'],
        };

    test('سكّ الكتابة: سجل الدفعة الأولى يحمل هاتف صاحبه (لا شبح جديد)',
        () {
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', cfg());
      // سميّ قائم بهاتف أول.
      repos.records.upsertLocal({
        'id': 'a0', 'name': 'محمد حسين', 'patient_name': 'محمد حسين',
        'clinic': 'عيادة ا', 'phone': '0919292254', 'service': 'حشو',
        'date': '2026-08-14', 'amount': 100, 'payment': 'كاش', '_t': 'r',
      });
      // حالة دين بدفعة أولى لسميّ جديد بهاتف مختلف — مسار الحفظ الموحد.
      saveNewRecord(
        repos,
        cfg(),
        SaveRecordInput(
          name: 'محمد حسين',
          clinic: 'عيادة ا',
          service: 'حشو عصب أمامي',
          amount: 1500,
          payment: 'تحويل',
          date: '2026-08-14',
          phone: '09192922258',
          isDebt: true,
          firstPay: 500,
        ),
      );
      final payRows = repos.records
          .getAll()
          .where((r) => r['isDebtPayment'] == 1)
          .toList();
      expect(payRows.length, 1);
      expect('${payRows.single['phone']}', '09192922258',
          reason: 'م181: الدفعة الأولى تحمل هاتف صاحبها عند الكتابة');

      // والقوائم: ملفان فقط — لا «بلا رقم».
      final map = buildPatientMap(
        repos.records.getAll(),
        repos.prosthetics.getAll(),
        repos.debts.getAll(),
      );
      expect(map.length, 2);
      expect(map.values.any((a) => a.identity == 'none'), isFalse);
    });

    test('سكّ الكتابة: دفعة الدين (debt_actions) ترث هاتف الدين', () {
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', cfg());
      repos.debts.upsertLocal({
        'id': 'd9', 'name': 'سالم', 'patient_name': 'سالم',
        'clinic': 'عيادة ا', 'phone': '0955555555',
        'service': 'حشو', 'date': '2026-08-10',
        'type': 'regular', 'status': 'partial',
        'totalAmount': 800, 'total': 800,
        'paidAmount': 100, 'remaining': 700,
        'installments': const [], '_t': 'd',
      });
      final res = payDebtInstallment(
        repos, cfg(), repos.debts.getById('d9')!,
        amount: 200, date: '2026-08-14', payment: 'كاش',
      );
      final pay = repos.records.getById(res.payRecordId)!;
      expect('${pay['phone']}', '0955555555',
          reason: 'م181: سجل الدفعة يرث هاتف دينه');
      expect(pay['isDebtPayment'], 1);
    });

    test('navIdentityOf: صف دفترٍ (دفعة قديمة بلا هاتف) يفتح بهوية صاحبه',
        () {
      final repos = c.read(reposProvider);
      final s = ownerScenario();
      for (final r in s.recs) {
        repos.records.upsertLocal(r);
      }
      for (final p in s.pros) {
        repos.prosthetics.upsertLocal(p);
      }
      for (final d in s.dbts) {
        repos.debts.upsertLocal(d);
      }
      final payRow = repos.records.getById('rp')!;
      expect(navIdentityOf(repos, payRow), 'p:09192922258',
          reason: 'م181: الملاحة من صف الدفعة تفتح ملف صاحبها لا شبحاً');
      final prosRow = repos.prosthetics.getById('pa')!;
      expect(navIdentityOf(repos, prosRow), 'p:0919292254');
    });

    test('الاكتساح بهوية يعيد سكّ patient_id ولا يمسّ السميّ ودفعاته', () {
      final repos = c.read(reposProvider);
      final s = ownerScenario();
      for (final r in s.recs) {
        repos.records.upsertLocal(r);
      }
      for (final p in s.pros) {
        repos.prosthetics.upsertLocal(p);
      }
      for (final d in s.dbts) {
        repos.debts.upsertLocal(d);
      }
      // تعديل بيانات صاحب الهاتف الأول (أ) وحده.
      final touched = editPatientCascade(
        repos,
        origName: 'محمد حسين',
        newName: 'محمد حسين الأب',
        phone: '0919292254',
        clinic: 'عيادة ا',
        identity: 'p:0919292254',
      );
      expect(touched, greaterThanOrEqualTo(1));
      // أ: أعيدت تسميته وسُكّ معرّفه من جديد.
      final a = repos.prosthetics.getById('pa')!;
      expect(a['name'], 'محمد حسين الأب');
      expect('${a['patient_id']}', isNotEmpty,
          reason: 'م181: الاكتساح يسكّ patient_id');
      // ب: سجلاته ودفعته القديمة (بلا هاتف — ترث دينه) لم تُمس.
      expect(repos.records.getById('rb')!['name'], 'محمد حسين');
      expect(repos.records.getById('rp')!['name'], 'محمد حسين',
          reason: 'الدفعة الموروثة تُحسب على هوية ب فلا يكتسحها تعديل أ');
      expect(repos.debts.getById('db')!['name'], 'محمد حسين');
    });
  });
}
