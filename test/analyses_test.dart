/// اختبارات نظام «التحاليل» — دخلٌ مخبري خاص بالعيادة، **معزولٌ مالياً**
/// عن كل شيء (الأرباح، الخزينة، الأرشيف، عدّادات المريض، الديون).
///
/// التغطية:
///   (أ) الحفظ من النموذج (saveNewRecord مع AnalysisInput) ينشئ صفَّ
///       isAnalysis واحداً بـ analysisOf == معرّف سجل الزيارة، وحرّاسه
///       isDebt/isPros/isDebtPayment صفراً وservice='تحاليل'، ولا ينشئ ديناً.
///   (ب) العزل المالي التام: todayLedgerRows بلا صف التحليل، ledgerTotals
///       بلا قيمته، getMonthRecs/treasuryTotals.grand/yearTotals/
///       clinicCards.income/buildPatientMap(visitCount,total) كلها بلا التحليل.
///   (ج) analysesTotals/clinicAnalyses تجمع التحاليل بدقة (كاش/تحويل).
///   (د) الإعدادات: إضافة تحليلٍ بمعرّف ثابت، وتعديل سعره **بنفس المعرّف**
///       لا يولّد قبراً ولا يكرّر العنصر، والحذف حتمي.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/archive/month_stats.dart'
    show getMonthRecs, monthData;
import 'package:dental_clinic_flutter/features/finance/profits_logic.dart'
    show yearTotals;
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart';
import 'package:dental_clinic_flutter/features/patients/patients_logic.dart'
    show buildPatientMap, clinicCards;
import 'package:dental_clinic_flutter/features/records/home_logic.dart'
    show
        buildAnalysisIndex,
        ledgerTotals,
        todayLedgerRows,
        todayPatientsByClinic;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/features/settings/settings_screen.dart'
    show analysesList, enabledAnalyses;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('analyses_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  JMap config() => {
        'centerName': 'مركز الاختبار',
        'doctorPct': 50,
        'clinicRates': {
          'clinics': {
            'الصفوة': {'treatments': {}, 'prosthetics': 40},
          },
        },
        'clinics': ['الصفوة'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
      };

  ProviderContainer container() => ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );

  String today() => getCurrentDate();
  String month() => getCurrentDate().substring(0, 7);
  String year() => getCurrentDate().substring(0, 4);

  /// يحفظ زيارةً نقديةً 200 (حشو) مع تحليلٍ 150 كاش، ويعيد نتيجة الحفظ.
  SaveRecordResult seedVisitWithAnalysis(
    ProviderContainer c, {
    num visitAmount = 200,
    String visitPay = 'كاش',
    String analName = 'صورة دم',
    num analPrice = 150,
    String analPay = 'كاش',
  }) {
    final repos = c.read(reposProvider);
    return saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: today(),
        amount: visitAmount,
        clinic: 'الصفوة',
        service: 'حشو',
        payment: visitPay,
        analysis: AnalysisInput(
          name: analName,
          price: analPrice,
          payment: analPay,
        ),
      ),
    );
  }

  // ── (أ) الحفظ ينشئ صف التحليل مربوطاً بالزيارة ──────────────────────────

  group('الحفظ — صف isAnalysis مربوط بالزيارة', () {
    test('صفٌّ واحد isAnalysis:1 بـ analysisOf==entryId وحرّاسه صفر', () {
      final c = container();
      addTearDown(c.dispose);
      final res = seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final all = repos.records.getAll();

      final analyses =
          all.where((r) => jsTruthy(r['isAnalysis'])).toList();
      expect(analyses, hasLength(1), reason: 'تحليلٌ واحد لا أكثر');
      final a = analyses.single;
      expect(a['analysisOf'], res.entryId, reason: 'مربوطٌ بسجل الزيارة');
      expect(a['analysisName'], 'صورة دم');
      expect(jsNumOr0(a['amount']), 150);
      expect(a['payment'], 'كاش');
      expect(a['service'], 'تحاليل');
      // حرّاس العزل عدداً لا منطقياً.
      expect(a['isAnalysis'], 1);
      expect(jsTruthy(a['isDebt']), isFalse);
      expect(jsTruthy(a['isPros']), isFalse);
      expect(jsTruthy(a['isDebtPayment']), isFalse);
      expect(a['_t'], 'r');
      // سجل الزيارة نفسه موجود وليس تحليلاً.
      final visit = all.firstWhere((r) => '${r['id']}' == res.entryId);
      expect(jsTruthy(visit['isAnalysis']), isFalse);
    });

    test('لا ديناً ينشأ من التحليل', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      expect(c.read(reposProvider).debts.getAll(), isEmpty);
    });

    test('التحليل يرث incomeDate يوم احتساب الزيارة', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      // زيارةٌ بيوم احتسابٍ مختلف (أمس تاريخاً، اليوم احتساباً).
      final yday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'سارة',
          date: yday,
          incomeDate: today(),
          amount: 100,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          analysis: const AnalysisInput(
              name: 'تحليل', price: 80, payment: 'تحويل'),
        ),
      );
      final a = repos.records
          .getAll()
          .firstWhere((r) => jsTruthy(r['isAnalysis']));
      expect(a['incomeDate'], today());
      expect(a['date'], yday);
    });

    test('price<=0 لا يكتب صف تحليل', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'خالد',
          date: today(),
          amount: 100,
          clinic: 'الصفوة',
          service: 'حشو',
          payment: 'كاش',
          analysis: const AnalysisInput(name: 'تحليل', price: 0, payment: 'كاش'),
        ),
      );
      expect(
          repos.records.getAll().where((r) => jsTruthy(r['isAnalysis'])),
          isEmpty);
    });
  });

  // ── (ب) العزل المالي التام ──────────────────────────────────────────────

  group('العزل المالي', () {
    test('todayLedgerRows بلا صف التحليل + ledgerTotals بلا قيمته', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c); // زيارة 200 + تحليل 150
      final repos = c.read(reposProvider);
      final rows = todayLedgerRows(
        repos.records.getAll(),
        repos.prosthetics.getAll(),
        repos.debts.getAll(),
      );
      // صفٌّ واحد فقط (الزيارة) — لا صفَّ للتحليل.
      expect(rows, hasLength(1));
      expect(rows.single.service, 'حشو');
      final tot = ledgerTotals(rows);
      expect(tot.paid, 200, reason: 'قيمة التحليل 150 خارج المدفوع');
      expect(tot.value, 200);
      expect(tot.paidBy['كاش'], 200);
    });

    test('getMonthRecs/monthData بلا التحليل', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final recs = getMonthRecs(
          repos.records.getAll(), repos.debts.getAll(), month());
      expect(recs, hasLength(1));
      expect(jsTruthy(recs.single['isAnalysis']), isFalse);
      final md = monthData(
        month(),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      expect(md.cash, 200, reason: 'التحليل 150 لا يدخل نقد الشهر');
      expect(md.total, 200);
    });

    test('treasuryTotals.grand بلا التحليل، والتحليل في analyses', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final s = TreasurySlice(
        month(),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      final t = treasuryTotals(s);
      expect(t.grand, 200, reason: 'grand = كاش الزيارة فقط، بلا التحليل');
      expect(t.cash, 200);
      // صفوف recs لا تحمل التحليل، وصفوف analyses تحمله وحده.
      expect(s.recs.any((r) => jsTruthy(r['isAnalysis'])), isFalse);
      expect(s.analyses, hasLength(1));
    });

    test('yearTotals بلا التحليل', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final y = yearTotals(
        year(),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      expect(y.cash, 200);
      expect(y.grand, 200);
    });

    test('clinicCards.income وعدّاد الزيارات بلا التحليل', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final cards = clinicCards(
        clinics: const ['الصفوة'],
        month: month(),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      final card = cards.single;
      expect(card.income, 200, reason: 'دخل البطاقة بلا التحليل');
      expect(card.visitCount, 1, reason: 'زيارةٌ واحدة (التحليل ليس زيارة)');
      expect(card.patientCount, 1);
    });

    test('buildPatientMap: التحليل لا يزيد visitCount ولا total', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final map = buildPatientMap(
        repos.records.getAll(),
        repos.prosthetics.getAll(),
        repos.debts.getAll(),
      );
      // تجميعة واحدة (أحمد|الصفوة).
      expect(map.values, hasLength(1));
      final agg = map.values.single;
      expect(agg.visitCount, 1, reason: 'الزيارة وحدها تُعدّ');
      expect(agg.total, 200, reason: 'إجمالي المريض بلا قيمة التحليل');
      // الصف موجود في entries (للعرض) لكن بلا أثرٍ مالي.
      expect(agg.entries.any((e) => jsTruthy(e['isAnalysis'])), isTrue);
    });

    test('todayPatientsByClinic لا يحسب التحليل زيارةً', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final groups = todayPatientsByClinic(
          repos.records.getAll(), repos.prosthetics.getAll());
      final g = groups.single;
      final p = g.patients.single;
      expect(p.visits, 1, reason: 'زيارةٌ واحدة رغم وجود صف التحليل');
    });

    test('getMonthlyTotals (CTE) بلا التحليل احترازاً', () {
      final c = container();
      addTearDown(c.dispose);
      seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final mt = repos.records.getMonthlyTotals(month(), 50)!;
      expect(mt.total, 200, reason: 'مجموع CTE بلا التحليل');
      expect(mt.cash, 200);
      expect(mt.count, 1);
    });
  });

  // ── (ج) مجاميع التحاليل ─────────────────────────────────────────────────

  group('مجاميع التحاليل', () {
    test('analysesTotals/clinicAnalyses كاش/تحويل صحيحة', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      // تحليلان: 150 كاش، 90 تحويل (على زيارتين).
      seedVisitWithAnalysis(c, analName: 'دم', analPrice: 150, analPay: 'كاش');
      seedVisitWithAnalysis(c,
          analName: 'أشعة', analPrice: 90, analPay: 'تحويل');
      final s = TreasurySlice(
        month(),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      final tot = analysesTotals(s);
      expect(tot.total, 240);
      expect(tot.cash, 150);
      expect(tot.transfer, 90);
      final cli = clinicAnalyses(s, 'الصفوة');
      expect(cli.total, 240);
      expect(cli.cash, 150);
      expect(cli.transfer, 90);
      // فئة التفصيل 'anal' تعيد صفَّي التحليل.
      expect(detailItems(s, 'anal', 'الصفوة'), hasLength(2));
    });

    test('buildAnalysisIndex يربط بالمعرّف وبالاسم+اليوم', () {
      final c = container();
      addTearDown(c.dispose);
      final res = seedVisitWithAnalysis(c);
      final repos = c.read(reposProvider);
      final idx = buildAnalysisIndex(repos.records.getAll());
      // الربط بمعرّف الزيارة.
      final byId = idx.byRecord[res.entryId];
      expect(byId, isNotNull);
      expect(byId!.single.name, 'صورة دم');
      expect(byId.single.amount, 150);
      expect(byId.single.isCash, isTrue);
      // forRow يجد التحليل عبر المعرّف.
      final found = idx.forRow(res.entryId, 'أحمد', today());
      expect(found, hasLength(1));
      // الربط بالاسم+اليوم موجود أيضاً.
      expect(idx.byPatDay['أحمد|${today()}'], isNotNull);
    });
  });

  // ── (د) الإعدادات — معرّف ثابت بلا قبور ─────────────────────────────────

  group('الإعدادات — قائمة analyses بمعرّف ثابت', () {
    test('إضافة تحليل ثم تعديل سعره بنفس المعرّف لا يكرّر ولا يترك قبراً', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      // إضافة تحليلٍ بمعرّف ثابت.
      const id = 'anal-fixed-1';
      repos.settings.configAddItem(['analyses'], {
        'id': id,
        'name': 'صورة دم',
        'price': 100,
        'enabled': true,
      });
      var cfg = repos.settings.get('app.config') as JMap;
      var list = analysesList(cfg);
      expect(list, hasLength(1));
      expect(jsNumOr0(list.single['price']), 100);

      // تعديل السعر بنفس المعرّف (يدهس صفَّه).
      repos.settings.configAddItem(['analyses'], {
        'id': id,
        'name': 'صورة دم',
        'price': 250,
        'enabled': true,
      });
      cfg = repos.settings.get('app.config') as JMap;
      list = analysesList(cfg);
      expect(list, hasLength(1), reason: 'لا عنصرٌ مكرَّر (نفس المعرّف)');
      expect(jsNumOr0(list.single['price']), 250, reason: 'السعر دُهس');

      // تعطيل التحليل يُخفيه عن enabledAnalyses بلا حذف.
      repos.settings.configAddItem(['analyses'], {
        'id': id,
        'name': 'صورة دم',
        'price': 250,
        'enabled': false,
      });
      cfg = repos.settings.get('app.config') as JMap;
      expect(analysesList(cfg), hasLength(1));
      expect(enabledAnalyses(cfg), isEmpty, reason: 'المعطّل خارج المفعّلة');
    });

    test('الحذف يزيل التحليل (حتمي)', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      const item = {
        'id': 'anal-del-1',
        'name': 'أشعة',
        'price': 50,
        'enabled': true,
      };
      repos.settings.configAddItem(['analyses'], item);
      final withItem = repos.settings.get('app.config');
      expect(analysesList(withItem is Map ? JMap.from(withItem) : {}),
          hasLength(1));
      repos.settings.configRemoveItem(['analyses'], item);
      // بعد حذف آخر عنصرٍ قد تعود القائمة/الإعدادات فارغةً (null) — آمنٌ.
      final after = repos.settings.get('app.config');
      expect(analysesList(after is Map ? JMap.from(after) : {}), isEmpty);
    });
  });
}
