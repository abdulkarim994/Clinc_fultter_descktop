/// م149 — اختبارات قاعدة تكرار التحليل الثلاثي + مساعدات سجل الخزينة النقية.
///
/// (أ) الدوال النقية: triRepeatMonths (الافتراضي 6/الصفر يعطّل)،
///     lastTriAnalysisDate (هوية بالمعرّف ثم الاسم المطبَّع)، addMonths
///     (إضافة تقويمية)، triRepeatBlockMessage (حدود بالضبط/قبل/بعد + نص
///     الرسالة حرفياً بصيغة المواصفة).
/// (ب) فلاتر السجل: clinic في filterAnalysesRows + صفوف/إجمالي الشهر الجاري.
/// (ج) الكاتب addAnalysisToVisit يصدّ التكرار داخل المدة ويسمح بعدها
///     وبتعطيل القاعدة (repeatMonths=0) — دفاعٌ في العمق تحت الواجهة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart'
    show arNorm;
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate, jsTruthy;
import 'package:dental_clinic_flutter/features/finance/analyses_filter.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

void main() {
  // ═══ (أ) الدوال النقية ═══════════════════════════════════════════════════

  group('triRepeatMonths — قراءة المدة من الإعدادات', () {
    test('الافتراضي 6 حين غياب الحقل أو الخريطة كلها', () {
      expect(triRepeatMonths(const {}), 6);
      expect(triRepeatMonths(const {'analyses3': {'price': 50}}), 6);
    });
    test('قيمة مضبوطة تُقرأ كما هي — والصفر صفر', () {
      expect(triRepeatMonths(const {'analyses3': {'repeatMonths': 3}}), 3);
      expect(triRepeatMonths(const {'analyses3': {'repeatMonths': 0}}), 0);
      expect(triRepeatMonths(const {'analyses3': {'repeatMonths': '12'}}), 12);
    });
  });

  group('addMonths — إضافة تقويمية على YYYY-MM-DD', () {
    test('إضافة عادية داخل السنة وعبرها', () {
      expect(addMonths('2026-01-15', 6), '2026-07-15');
      expect(addMonths('2026-08-09', 6), '2027-02-09');
    });
    test('نهاية الشهر تفيض بسلوك DateTime القياسي', () {
      // 31 كانون الثاني + شهر = 2/31 غير موجود → يفيض إلى آذار.
      expect(addMonths('2026-01-31', 1), '2026-03-03');
    });
  });

  group('lastTriAnalysisDate — هوية المريض وتاريخ آخر تحليل', () {
    const tri = kTriAnalysesName;
    final rows = <JMap>[
      // زيارة عادية — ليست تحليلاً فلا تُحتسب أبداً.
      {'isAnalysis': 0, 'patient_id': 'p1', 'patient_name': 'أحمد', 'date': '2026-07-01'},
      {'isAnalysis': 1, 'analysisName': tri, 'patient_id': 'p1', 'patient_name': 'أحمد', 'date': '2026-02-10'},
      {'isAnalysis': 1, 'analysisName': tri, 'patient_id': 'p1', 'patient_name': 'أحمد', 'date': '2026-05-20'},
      // تحليل حر من النظام القديم (قبل م145) — أحدث تاريخاً لكنه لا يُحتسب.
      {'isAnalysis': 1, 'analysisName': 'صورة دم', 'patient_id': 'p1', 'patient_name': 'أحمد', 'date': '2026-07-15'},
      // مريض آخر بلا معرّف — بالاسم فقط، وبهمزة مختلفة.
      {'isAnalysis': 1, 'analysisName': tri, 'patient_name': 'إبراهيم', 'date': '2026-03-03'},
    ];

    test('بالمعرّف: يعيد أحدث تحليلٍ ثلاثي ويتجاهل غير التحاليل والحرة القديمة',
        () {
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p1', patientName: 'أحمد', normalize: arNorm),
        '2026-05-20',
      );
    });
    test('بالاسم المطبَّع حين غياب المعرّف (ابراهيم = إبراهيم)', () {
      expect(
        lastTriAnalysisDate(rows, patientName: 'ابراهيم', normalize: arNorm),
        '2026-03-03',
      );
    });
    test('لا تطابق = null', () {
      expect(
        lastTriAnalysisDate(rows,
            patientId: 'p9', patientName: 'غريب', normalize: arNorm),
        isNull,
      );
    });
  });

  group('triRepeatBlockMessage — حدود القرار ونص الرسالة', () {
    test('لا تحليل سابقاً = مسموح', () {
      expect(
        triRepeatBlockMessage(
            lastDate: null, today: '2026-08-09', repeatMonths: 6),
        isNull,
      );
    });
    test('اليوم = آخر تحليل + 6 أشهر بالضبط = مسموح (حد السماح)', () {
      expect(
        triRepeatBlockMessage(
            lastDate: '2026-02-09', today: '2026-08-09', repeatMonths: 6),
        isNull,
      );
    });
    test('قبل الحد بيوم = محجوب بنص المواصفة حرفياً', () {
      expect(
        triRepeatBlockMessage(
            lastDate: '2026-02-10', today: '2026-08-09', repeatMonths: 6),
        'لا يمكن إجراء تحليل ثلاثي جديد لهذا المريض. '
        'آخر تحليل تم بتاريخ 2026-02-10. '
        'يجب مرور 6 أشهر على الأقل.',
      );
    });
    test('بعد الحد بكثير = مسموح', () {
      expect(
        triRepeatBlockMessage(
            lastDate: '2025-01-01', today: '2026-08-09', repeatMonths: 6),
        isNull,
      );
    });
    test('repeatMonths = 0 يُعطّل القاعدة حتى مع تحليلٍ بالأمس', () {
      expect(
        triRepeatBlockMessage(
            lastDate: '2026-08-08', today: '2026-08-09', repeatMonths: 0),
        isNull,
      );
    });
  });

  // ═══ (ب) فلاتر سجل التحاليل ═══════════════════════════════════════════════

  group('filterAnalysesRows — معامل العيادة (م149)', () {
    final rows = <JMap>[
      {'patient_name': 'أحمد', 'payment': 'كاش', 'clinic': 'الصفوة', 'amount': 50},
      {'patient_name': 'سارة', 'payment': 'تحويل', 'clinic': 'النور', 'amount': 50},
      {'patient_name': 'خالد', 'payment': 'كاش', 'clinic_id': 'النور', 'amount': 50},
    ];
    test('فارغ = كل العيادات (السلوك القديم دون تغيير)', () {
      expect(filterAnalysesRows(rows, query: '', mode: 'all').length, 3);
    });
    test('تقييد بعيادة يطابق clinic ثم clinic_id احتياطاً', () {
      final v = filterAnalysesRows(rows, query: '', mode: 'all', clinic: 'النور');
      expect(v.length, 2);
      expect(v.every((r) => r['patient_name'] != 'أحمد'), isTrue);
    });
    test('العيادة تتقاطع مع طريقة الدفع والبحث', () {
      final v = filterAnalysesRows(rows,
          query: 'خالد', mode: 'cash', clinic: 'النور');
      expect(v.length, 1);
      expect(v.single['patient_name'], 'خالد');
    });
  });

  group('currentMonthRows/Total — الشهر التقويمي الجاري فقط', () {
    final rows = <JMap>[
      {'date': '2026-08-01', 'amount': 50},
      {'date': '2026-08-31', 'amount': 25},
      {'date': '2026-07-31', 'amount': 999}, // الشهر الماضي — خارج الإجمالي.
      {'date': '2025-08-09', 'amount': 999}, // سنة سابقة بنفس الشهر — خارجه.
    ];
    test('يبقي صفوف YYYY-MM الجاري وحدها ويجمع مبالغها', () {
      expect(currentMonthRows(rows, today: '2026-08-09').length, 2);
      expect(currentMonthTotal(rows, today: '2026-08-09'), 75);
    });
    test('مطلع شهرٍ جديد = الإجمالي يبدأ من الصفر ذاتياً', () {
      expect(currentMonthTotal(rows, today: '2026-09-01'), 0);
    });
  });

  // ═══ (ج) حارس الكاتب addAnalysisToVisit ═════════════════════════════════

  group('addAnalysisToVisit — حارس قاعدة التكرار في الكاتب', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m149_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    JMap config({num repeatMonths = 6}) => {
          'centerName': 'مركز الاختبار',
          'doctorPct': 50,
          'clinics': ['الصفوة'],
          'services': ['حشو'],
          'payments': ['كاش', 'تحويل'],
          kTriAnalysesCfgKey: {
            'enabled': true,
            'price': 50,
            'repeatMonths': repeatMonths,
          },
        };

    ProviderContainer container() => ProviderContainer(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
        );

    String seedVisit(ProviderContainer c) {
      final res = saveNewRecord(
        c.read(reposProvider),
        config(),
        SaveRecordInput(
          name: 'أحمد',
          date: getCurrentDate(),
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
        ),
      );
      return res.entryId;
    }

    int analCount(ProviderContainer c) => c
        .read(reposProvider)
        .records
        .getAll()
        .where((r) => jsTruthy(r['isAnalysis']))
        .length;

    test('تحليل ثانٍ لنفس المريض داخل المدة يُصَدّ (false، لا صف)', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      bool add() => addAnalysisToVisit(repos,
          analysisOf: entryId,
          patientName: 'أحمد',
          clinic: 'الصفوة',
          date: getCurrentDate(),
          cfg: config(),
          payment: 'كاش');
      expect(add(), isTrue);
      expect(add(), isFalse); // آخر تحليل = اليوم ⇒ محجوب 6 أشهر.
      expect(analCount(c), 1);
    });

    test('تحليل قديم انقضت مدته لا يمنع الجديد', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      // بذر تحليلٍ قديم (قبل 7 أشهر تقويمية) عبر الكاتب لا يمكن مباشرةً
      // لأن حارسه يقرأ تاريخ اليوم — نبذره كصفٍّ خام عبر المستودع نفسه
      // كما تفعل المزامنة الواردة تماماً.
      final old = addMonths(getCurrentDate(), -7);
      repos.records.upsertLocal({
        'id': 'anal-old-1',
        'date': old,
        'name': 'أحمد',
        'patient_name': 'أحمد',
        'amount': 50,
        'clinic': 'الصفوة',
        'clinic_id': 'الصفوة',
        'service': 'تحاليل',
        'payment': 'كاش',
        'isAnalysis': 1,
        'isDebt': 0,
        'isPros': 0,
        'isDebtPayment': 0,
        'analysisName': kTriAnalysesName,
        'analysisOf': entryId,
        '_t': 'r',
      });
      expect(
        addAnalysisToVisit(repos,
            analysisOf: entryId,
            patientName: 'أحمد',
            clinic: 'الصفوة',
            date: getCurrentDate(),
            cfg: config(),
            payment: 'تحويل'),
        isTrue,
      );
      expect(analCount(c), 2);
    });

    test('repeatMonths = 0 يسمح بالتكرار في اليوم نفسه', () {
      final c = container();
      addTearDown(c.dispose);
      final entryId = seedVisit(c);
      final repos = c.read(reposProvider);
      bool add() => addAnalysisToVisit(repos,
          analysisOf: entryId,
          patientName: 'أحمد',
          clinic: 'الصفوة',
          date: getCurrentDate(),
          cfg: config(repeatMonths: 0),
          payment: 'كاش');
      expect(add(), isTrue);
      expect(add(), isTrue);
      expect(analCount(c), 2);
    });

    test('حارس saveNewRecord: زيارة بعلامة تحليل لمريضٍ محجوب تنجو الزيارة '
        'وحدها بلا صف تحليل (صمام الأمان تحت حاجز الواجهة)', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      // زيارة أولى بتحليل — تُنشئ صف التحليل (لا سابق).
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'أحمد',
          date: getCurrentDate(),
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          analysis: triAnalysisFor(
            creating: true,
            checked: true,
            cfg: config(),
            payment: 'كاش',
          ),
        ),
      );
      expect(analCount(c), 1);
      // زيارة ثانية بعلامة تحليل في نفس اليوم — الواجهة توقف الحفظ كله،
      // وإن تجاوزها مسارٌ ما فالكاتب يكتب الزيارة ويُسقط صف التحليل فقط.
      //
      // 🔄 م187 — الحجب القاطع صار **للهوية المؤكَّدة** (هاتفٌ مشترك أو
      // معرّفٌ يحمل هاتفاً)؛ فمريضٌ بلا هاتف حالتُه تحذيرٌ تأخذ الواجهة
      // موافقةً عليه. فليكن الصمام مُختبراً بما يحرسه فعلاً: **نفس الهاتف**.
      SaveRecordResult second({required String phone}) => saveNewRecord(
            repos,
            config(),
            SaveRecordInput(
              name: 'أحمد',
              date: getCurrentDate(),
              amount: 300,
              clinic: 'الصفوة',
              service: 'حشو',
              payment: 'كاش',
              phone: phone,
              analysis: triAnalysisFor(
                creating: true,
                checked: true,
                cfg: config(),
                payment: 'كاش',
              ),
            ),
          );
      // نبذر هاتفاً على الأول ثم نكرّر به: هويةٌ مؤكَّدة ⇒ يُسقط التحليل.
      final withPhone = saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'خالد',
          date: getCurrentDate(),
          amount: 200,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          phone: '0911111111',
          analysis: triAnalysisFor(
            creating: true,
            checked: true,
            cfg: config(),
            payment: 'كاش',
          ),
        ),
      );
      expect(withPhone.entryId, isNotEmpty);
      expect(analCount(c), 2);
      final before = repos.records.getAll().length;
      final blockedVisit = saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'خالد',
          date: getCurrentDate(),
          amount: 300,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          phone: '0911111111',
          analysis: triAnalysisFor(
            creating: true,
            checked: true,
            cfg: config(),
            payment: 'كاش',
          ),
        ),
      );
      expect(blockedVisit.entryId, isNotEmpty,
          reason: 'الزيارة تنجو وحدها');
      expect(analCount(c), 2,
          reason: 'م187: الهوية المؤكَّدة ⇒ صف التحليل يُسقط');
      expect(repos.records.getAll().length, before + 1,
          reason: 'صفُّ الزيارة وحده أُضيف');
      // وبلا هاتف (تحذير) يمضي التحليل — الواجهة هي من تسأل الطبيب.
      second(phone: '');
      expect(analCount(c), 3,
          reason: 'م187: التحذير يمضي في الكاتب (الموافقة بالواجهة)');
    });
  });
}
