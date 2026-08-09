/// م151 — اختبارات عرض وحساب التحاليل في «إدخال اليوم» (مواصفة المالك).
///
/// (أ) dayAnalysesTotals: الحساب من الصفوف المالية المستقلة حصراً — منع
///     التكرار بالمعرّف الفريد، نطاق يوم الاحتساب، وفلاتر العيادة/الطريقة/
///     الفترة/الموظف/البحث بالاسم.
/// (ب) totalsWithAnalyses / analysesOnlyTotals: تركيب خانات المال بأوضاع
///     «الكل» و«تحاليل كاش/تحويل/إجمالي التحاليل» — بأمثلة المواصفة رقمياً.
/// (ج) analysisRowMarks: ✓ واحدة لكل تحليل — على الصف المرتبط حصراً،
///     والقديم بلا ربطٍ على أقدم صفوف مريضه فقط (مثال المواصفة ٩ حرفياً).
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/records/home_logic.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

void main() {
  final today = getCurrentDate();

  JMap anal({
    required String id,
    num amount = 25,
    String pay = 'كاش',
    String clinic = 'الصفوة',
    String? date,
    String? incomeDate,
    String? analysisOf,
    String name = 'أحمد',
    String by = '',
    num? createdAt,
  }) => {
        'id': id,
        'isAnalysis': 1,
        'name': name,
        'patient_name': name,
        'amount': amount,
        'payment': pay,
        'clinic': clinic,
        'clinic_id': clinic,
        'date': date ?? today,
        if (incomeDate != null) 'incomeDate': incomeDate,
        if (analysisOf != null) 'analysisOf': analysisOf,
        if (by.isNotEmpty) 'createdBy': by,
        if (createdAt != null) 'createdAt': createdAt,
        'analysisName': 'التحاليل الثلاثية',
      };

  LedgerRow row({
    required String id,
    String name = 'أحمد',
    num timeMs = 0,
    bool expense = false,
    num paid = 0,
    String method = 'كاش',
  }) => LedgerRow(
        isExpense: expense,
        name: name,
        clinic: 'الصفوة',
        service: 'حشو',
        payment: method,
        method: method,
        id: id,
        kind: 'r',
        by: '',
        timeMs: timeMs,
        value: paid,
        paid: paid,
        remaining: 0,
      );

  group('dayAnalysesTotals — الحساب من الصفوف المستقلة حصراً', () {
    test('مثال المواصفة: كاش 25 + تحويل 50 من اليوم فقط', () {
      final t = dayAnalysesTotals([
        anal(id: 'a1', amount: 25, pay: 'كاش'),
        anal(id: 'a2', amount: 50, pay: 'تحويل'),
        anal(id: 'a3', amount: 999, date: '2020-01-01'), // يوم آخر — خارج.
        {'id': 'r1', 'isAnalysis': 0, 'amount': 777, 'date': today}, // ليس تحليلاً.
      ], day: today);
      expect(t.cash, 25);
      expect(t.transfer, 50);
    });

    test('منع التكرار: نفس المعرّف يُحتسب مرة واحدة مهما تكرر الصف', () {
      final dup = anal(id: 'a1', amount: 25);
      final t = dayAnalysesTotals([dup, dup, Map.of(dup)], day: today);
      expect(t.cash, 25, reason: 'UUID واحد = عملية واحدة');
    });

    test('يوم الاحتساب: incomeDate يتقدم على date', () {
      final t = dayAnalysesTotals([
        anal(id: 'a1', amount: 25, date: '2020-01-01', incomeDate: today),
        anal(id: 'a2', amount: 50, incomeDate: '2020-01-01'),
      ], day: today);
      expect(t.cash, 25, reason: 'الأول يُحسب اليوم والثاني لا');
    });

    test('فلاتر العيادة والطريقة والموظف والبحث بالاسم تتركب', () {
      final rows = [
        anal(id: 'a1', amount: 25, clinic: 'الصفوة', by: 'sara'),
        anal(id: 'a2', amount: 50, clinic: 'النخبة', pay: 'تحويل', name: 'خالد'),
      ];
      expect(dayAnalysesTotals(rows, day: today, clinics: {'الصفوة'}).cash, 25);
      expect(
        dayAnalysesTotals(rows, day: today, clinics: {'الصفوة'}).transfer,
        0,
      );
      expect(dayAnalysesTotals(rows, day: today, payments: {'تحويل'}).transfer,
          50);
      expect(dayAnalysesTotals(rows, day: today, by: 'sara').cash, 25);
      expect(dayAnalysesTotals(rows, day: today, by: 'sara').transfer, 0);
      expect(dayAnalysesTotals(rows, day: today, nameQuery: 'خالد').transfer,
          50);
      expect(dayAnalysesTotals(rows, day: today, nameQuery: 'خالد').cash, 0);
    });

    test('فلتر الفترة (صباحية/مسائية) بوقت التسجيل', () {
      final morning =
          DateTime.now().copyWith(hour: 8).millisecondsSinceEpoch;
      final evening =
          DateTime.now().copyWith(hour: 20).millisecondsSinceEpoch;
      final rows = [
        anal(id: 'a1', amount: 25, createdAt: morning),
        anal(id: 'a2', amount: 50, pay: 'تحويل', createdAt: evening),
      ];
      final m = dayAnalysesTotals(rows,
          day: today, period: LedgerPeriod.morning, cutoffHour: 12);
      expect(m.cash, 25);
      expect(m.transfer, 0);
      final e = dayAnalysesTotals(rows,
          day: today, period: LedgerPeriod.evening, cutoffHour: 12);
      expect(e.transfer, 50);
    });
  });

  group('تركيب خانات المال — أمثلة المواصفة رقمياً', () {
    // إيراد عادي: كاش 100 + تحويل 200.
    final base = ledgerTotals([
      row(id: 'r1', paid: 100, method: 'كاش'),
      row(id: 'r2', name: 'سالم', paid: 200, method: 'تحويل'),
    ]);

    test('«الكل»: 100/200 + تحاليل 25/50 ⇒ 125/250/375', () {
      final t = totalsWithAnalyses(base, (cash: 25, transfer: 50));
      expect(t.paidBy['كاش'], 125);
      expect(t.paidBy['تحويل'], 250);
      expect(t.paid, 375);
      expect(t.net, 375, reason: 'لا مصروفات — الصافي = المدفوع');
    });

    test('«تحاليل كاش» = 75 ⇒ 75/0/75 بلا أي إيراد عادي', () {
      final t = analysesOnlyTotals(base, (cash: 75, transfer: 0));
      expect(t.paidBy['كاش'], 75);
      expect(t.paidBy['تحويل'] ?? 0, 0);
      expect(t.paid, 75);
    });

    test('«تحاليل تحويل» = 120 ⇒ 0/120/120', () {
      final t = analysesOnlyTotals(base, (cash: 0, transfer: 120));
      expect(t.paidBy['كاش'] ?? 0, 0);
      expect(t.paidBy['تحويل'], 120);
      expect(t.paid, 120);
    });

    test('«إجمالي التحاليل»: 75 + 120 ⇒ 75/120/195', () {
      final t = analysesOnlyTotals(base, (cash: 75, transfer: 120));
      expect(t.paidBy['كاش'], 75);
      expect(t.paidBy['تحويل'], 120);
      expect(t.paid, 195);
    });

    test('مثال المواصفة ٩: عيادة 180/100 + تحليل 25 كاش ⇒ 205/100/305', () {
      final b = ledgerTotals([
        row(id: 'r1', paid: 180, method: 'كاش'),
        row(id: 'r2', name: 'سالم', paid: 100, method: 'تحويل'),
      ]);
      final t = totalsWithAnalyses(b, (cash: 25, transfer: 0));
      expect(t.paidBy['كاش'], 205);
      expect(t.paidBy['تحويل'], 100);
      expect(t.paid, 305);
    });

    test('تحاليل صفرية = الإجماليات كما هي (نفس الكائن)', () {
      expect(
        identical(totalsWithAnalyses(base, (cash: 0, transfer: 0)), base),
        isTrue,
      );
    });
  });

  group('analysisRowMarks — ✓ واحدة لكل تحليل (مثال المواصفة ٩)', () {
    test('ثلاثة صفوف لمريضٍ وتحليل مرتبط بالثاني ⇒ العلامة عليه وحده', () {
      final rows = [
        row(id: 'r1', timeMs: 1),
        row(id: 'r2', timeMs: 2),
        row(id: 'r3', timeMs: 3),
      ];
      final idx = buildAnalysisIndex([
        anal(id: 'a1', amount: 25, analysisOf: 'r2'),
      ]);
      final marks = analysisRowMarks(rows, idx, today);
      expect(marks.keys, ['r2'], reason: '✓ على الصف المرتبط حصراً');
      expect(marks['r2']!.single.amount, 25);
    });

    test('تحليل قديم بلا ربط ⇒ على أقدم صفوف المريض فقط', () {
      final rows = [
        row(id: 'r2', timeMs: 5),
        row(id: 'r1', timeMs: 1), // الأقدم — يحمل العلامة.
        row(id: 'r3', timeMs: 9),
      ];
      final idx = buildAnalysisIndex([anal(id: 'a1')]); // بلا analysisOf.
      final marks = analysisRowMarks(rows, idx, today);
      expect(marks.keys, ['r1']);
    });

    test('مريضان بتحليلين ⇒ علامتان (واحدة لكل مريض) لا أكثر', () {
      final rows = [
        row(id: 'r1', timeMs: 1),
        row(id: 'r2', timeMs: 2),
        row(id: 'r3', name: 'خالد', timeMs: 3),
      ];
      final idx = buildAnalysisIndex([
        anal(id: 'a1', analysisOf: 'r1'),
        anal(id: 'a2', name: 'خالد', analysisOf: 'r3', pay: 'تحويل'),
      ]);
      final marks = analysisRowMarks(rows, idx, today);
      expect(marks.length, 2);
      expect(marks.containsKey('r2'), isFalse,
          reason: 'صف أحمد الثاني بلا علامة');
    });

    test('الربط لزيارةٍ غير ظاهرة اليوم لا يسرّب العلامة لصفوف أخرى', () {
      // تحليل يومٍ آخر (تاريخه قديم): لا يظهر في صفوف اليوم إطلاقاً.
      final rows = [row(id: 'r1', timeMs: 1)];
      final idx = buildAnalysisIndex([
        anal(id: 'a1', date: '2020-01-01', analysisOf: 'زيارة-قديمة'),
      ]);
      expect(analysisRowMarks(rows, idx, today), isEmpty);
    });

    test('صفوف المصروف لا تحمل علامة أبداً', () {
      final rows = [
        row(id: 'e1', expense: true, timeMs: 1),
        row(id: 'r1', timeMs: 2),
      ];
      final idx = buildAnalysisIndex([anal(id: 'a1')]);
      final marks = analysisRowMarks(rows, idx, today);
      expect(marks.keys, ['r1']);
    });
  });
}
