/// اختبارات المرحلة 3 — الرواتب والمصروفات: حساب المتبقّي شهرياً، منع السحب
/// فوق راتب الشهر، ومجاميع الفئات. منطقٌ نقيّ + استعلامات المستودع على قاعدة
/// مؤقّتة (بلا واجهة ولا تشفير — تعمل على مكتبة sqlite النظام في هذه البيئة).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/core/utils/uid.dart' show genId;
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/features/expenses/salaries_logic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late LocalDb db;
  late Repositories repos;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('salaries_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    db.setOwnerUid('u1');
    repos = Repositories(db);
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  String addEmployee(String name, double salary) {
    final id = genId();
    repos.employees.upsert({
      'id': id,
      'name': name,
      'role': 'تمريض',
      'base_salary': salary,
      'active': 1,
    });
    return id;
  }

  void addWithdrawal(String empId, double amount, String date) {
    repos.expenses.upsert({
      'id': genId(),
      'category': 'salary_withdrawal',
      'employee_id': empId,
      'amount': amount,
      'date': date,
    });
  }

  group('منطق المتبقّي', () {
    test('المتبقّي = الراتب − مسحوبات الشهر، ويصفّر مطلع الشهر التالي', () {
      final e = addEmployee('سعاد', 1000);
      addWithdrawal(e, 300, '2026-08-05');
      addWithdrawal(e, 200, '2026-08-20');
      // سحب في شهر آخر لا يؤثّر على أغسطس.
      addWithdrawal(e, 150, '2026-09-02');

      expect(repos.expenses.salaryWithdrawn('2026-08', e), closeTo(500, 1e-9));
      final remaining = salaryRemaining(
          baseSalary: 1000,
          withdrawnThisMonth: repos.expenses.salaryWithdrawn('2026-08', e));
      expect(remaining, closeTo(500, 1e-9));

      // سبتمبر يبدأ من جديد: مسحوبه 150 فقط.
      expect(repos.expenses.salaryWithdrawn('2026-09', e), closeTo(150, 1e-9));
      // أكتوبر بلا سحوبات ⇒ المتبقّي كامل الراتب.
      expect(repos.expenses.salaryWithdrawn('2026-10', e), closeTo(0, 1e-9));
    });
  });

  group('منع السحب فوق راتب الشهر', () {
    test('يُسمح بما لا يتجاوز المتبقّي، ويُمنع ما يتجاوزه أو غير الموجب', () {
      expect(validateWithdrawal(amount: 500, remaining: 500).ok, isTrue);
      expect(validateWithdrawal(amount: 200, remaining: 500).ok, isTrue);
      expect(validateWithdrawal(amount: 500.01, remaining: 500).ok, isFalse);
      expect(validateWithdrawal(amount: 0, remaining: 500).ok, isFalse);
      expect(validateWithdrawal(amount: -50, remaining: 500).ok, isFalse);
    });

    test('عدّة سحوبات ضمن الراتب مسموحة حتى نفاد المتبقّي', () {
      final e = addEmployee('خالد', 800);
      addWithdrawal(e, 500, '2026-08-03');
      final rem1 = salaryRemaining(
          baseSalary: 800,
          withdrawnThisMonth: repos.expenses.salaryWithdrawn('2026-08', e));
      expect(rem1, closeTo(300, 1e-9));
      // سحب 300 آخر مسموح (يساوي المتبقّي بالضبط)، و301 ممنوع.
      expect(validateWithdrawal(amount: 300, remaining: rem1).ok, isTrue);
      expect(validateWithdrawal(amount: 301, remaining: rem1).ok, isFalse);
    });
  });

  group('مجاميع الفئات', () {
    test('categoryTotal يجمع فئةً واحدة في الشهر', () {
      repos.expenses.upsert({
        'id': genId(),
        'category': 'cleaning',
        'amount': 40,
        'date': '2026-08-03'
      });
      repos.expenses.upsert({
        'id': genId(),
        'category': 'cleaning',
        'amount': 60,
        'date': '2026-08-09'
      });
      repos.expenses.upsert({
        'id': genId(),
        'category': 'dental',
        'amount': 100,
        'date': '2026-08-09'
      });
      expect(repos.expenses.categoryTotal('2026-08', 'cleaning'),
          closeTo(100, 1e-9));
      expect(
          repos.expenses.categoryTotal('2026-08', 'dental'), closeTo(100, 1e-9));
      expect(repos.expenses.categoryTotal('2026-09', 'cleaning'),
          closeTo(0, 1e-9));
    });
  });

  group('استهلاك اليوم (getByDay)', () {
    test('يجمع بنود يومٍ واحد بكل الفئات (شاملاً سحب الراتب)', () {
      final e = addEmployee('نور', 1000);
      addWithdrawal(e, 100, '2026-08-02');
      repos.expenses.upsert({
        'id': genId(),
        'category': 'cleaning',
        'amount': 30,
        'date': '2026-08-02'
      });
      // يومٌ آخر — يجب ألا يُحتسب.
      repos.expenses.upsert({
        'id': genId(),
        'category': 'dental',
        'amount': 20,
        'date': '2026-08-03'
      });
      final day = repos.expenses.getByDay('2026-08-02');
      expect(day.length, 2);
      final total =
          day.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
      expect(total, closeTo(130, 1e-9));
    });
  });

  group('سياسة ترحيل الرواتب', () {
    test('monthsInclusive: أشهر شاملة بحدٍّ أدنى 1', () {
      expect(monthsInclusive('2026-08', '2026-08'), 1);
      expect(monthsInclusive('2026-06', '2026-08'), 3);
      expect(monthsInclusive('2025-11', '2026-02'), 4);
      expect(monthsInclusive('2026-09', '2026-08'), 1); // النهاية قبل البداية
    });

    test('salaryRemainingPolicy: تصفير شهري مقابل ترحيل', () {
      expect(
          salaryRemainingPolicy(
              carryover: false,
              baseSalary: 1000,
              withdrawnThisMonth: 300,
              monthsElapsed: 3,
              cumulativeWithdrawn: 900),
          closeTo(700, 1e-9)); // 1000 − 300
      expect(
          salaryRemainingPolicy(
              carryover: true,
              baseSalary: 1000,
              withdrawnThisMonth: 300,
              monthsElapsed: 3,
              cumulativeWithdrawn: 900),
          closeTo(2100, 1e-9)); // 3000 − 900
    });

    test('salaryWithdrawnThrough تراكمي حتى نهاية الشهر شاملاً', () {
      final e = addEmployee('ليان', 1000);
      addWithdrawal(e, 200, '2026-06-10');
      addWithdrawal(e, 300, '2026-07-05');
      addWithdrawal(e, 100, '2026-08-20');
      expect(repos.expenses.salaryWithdrawnThrough('2026-07', e),
          closeTo(500, 1e-9)); // يونيو+يوليو
      expect(repos.expenses.salaryWithdrawnThrough('2026-08', e),
          closeTo(600, 1e-9)); // +أغسطس
    });
  });

  group('إجماليات مصروفات الشهر حسب الدفع', () {
    test('monthExpenseTotals يقسم كاش/تحويل والغياب يُعامَل كاش', () {
      repos.expenses.upsert({
        'id': genId(),
        'category': 'cleaning',
        'amount': 100,
        'date': '2026-08-02',
        'payment': 'كاش'
      });
      repos.expenses.upsert({
        'id': genId(),
        'category': 'dental',
        'amount': 40,
        'date': '2026-08-03',
        'payment': 'تحويل'
      });
      repos.expenses.upsert({
        'id': genId(),
        'category': 'other',
        'amount': 10,
        'date': '2026-08-04'
      }); // بلا payment → كاش
      // سحب راتب كاش يدخل الإجمالي أيضاً.
      final emp = addEmployee('راتب', 500);
      repos.expenses.upsert({
        'id': genId(),
        'category': 'salary_withdrawal',
        'employee_id': emp,
        'amount': 50,
        'date': '2026-08-05',
        'payment': 'كاش'
      });
      final t = repos.expenses.monthExpenseTotals('2026-08');
      expect(t.total, closeTo(200, 1e-9));
      expect(t.cash, closeTo(160, 1e-9)); // 100+10+50
      expect(t.xfer, closeTo(40, 1e-9));
    });
  });
}
