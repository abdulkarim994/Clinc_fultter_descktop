/// اختبارات م66/دفعة صفر-أ — دفعة الدين لا تُدمّر دفعةً بعيدة وصلت أثناء
/// فتح النافذة.
///
/// العيب الأصلي (SYNC-1): `payDebtInstallment` تعمل على لقطة قديمة التقطتها
/// البطاقة وقت البناء، ثم تكتب بـ upsertLocal بلا `base:`. دفعة من جهاز آخر
/// تصل أثناء فتح النافذة كانت تُدهَس نهائياً (أُثبت: 400 تختفي، المدفوع 300
/// بدل 700). الإصلاح: إعادة قراءة طازجة + إلحاق بالقائمة الطازجة + اشتقاق
/// عبر recomputeDebts + تمرير base للدمج بالمعرّف.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m66_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز',
        'doctorPct': 50,
        'clinics': ['الصفوة'],
        'services': ['حشو'],
        'payments': ['كاش'],
      };

  ({ProviderContainer c, dynamic repos, String id}) newDebt(num total) {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    final repos = c.read(reposProvider);
    saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'سالم', date: getCurrentDate(), amount: total,
          clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
          isDebt: true, firstPay: 0,
        ));
    return (c: c, repos: repos, id: repos.debts.getAll().single['id'] as String);
  }

  List<String> instIds(dynamic repos, String id) => [
        for (final e
            in ((repos.debts.getById(id)!['installments'] as List?) ?? const []))
          '${(e as Map)['id']}'
      ];

  test('REPRO: دفعة بعيدة وصلت أثناء النافذة لا تُدمَّر', () {
    final d = newDebt(1000);
    addTearDown(d.c.dispose);
    final repos = d.repos;

    // 1) البطاقة تلتقط اللقطة القديمة (لا أقساط بعد).
    final staleSnapshot = Map<String, Object?>.from(repos.debts.getById(d.id)!);

    // 2) أثناء فتح النافذة تصل دفعة 400 من جهاز آخر وتُدمج محلياً.
    final incoming = Map<String, Object?>.from(repos.debts.getById(d.id)!);
    incoming['installments'] = [
      {
        'id': 'remote-1', 'amount': 400, 'date': getCurrentDate(),
        'payment': 'كاش', 'recordId': 'remote-rec-1', 'createdAt': jsNow(),
      }
    ];
    repos.debts.upsertLocal(incoming);
    expect(instIds(repos, d.id), contains('remote-1'));

    // 3) المستخدم يؤكد 300 على اللقطة القديمة.
    payDebtInstallment(repos, config(), staleSnapshot,
        amount: 300, date: getCurrentDate(), payment: 'كاش');

    final ids = instIds(repos, d.id);
    final view = repos.debts.getById(d.id)!;
    expect(ids, contains('remote-1'),
        reason: 'الدفعة البعيدة 400 يجب أن تنجو');
    expect(ids.length, 2, reason: 'دفعتان: البعيدة والمحلية');
    expect(jsNumOr0(view['paidAmount']), 700, reason: '400 + 300');
    expect(jsNumOr0(view['remaining']), 300, reason: '1000 - 700');
  });

  test('CONTROL: دفعتان متتاليتان بلا تزامن تُجمعان', () {
    final d = newDebt(1000);
    addTearDown(d.c.dispose);
    final repos = d.repos;
    payDebtInstallment(repos, config(), repos.debts.getById(d.id)!,
        amount: 200, date: getCurrentDate(), payment: 'كاش');
    payDebtInstallment(repos, config(), repos.debts.getById(d.id)!,
        amount: 300, date: getCurrentDate(), payment: 'كاش');
    final view = repos.debts.getById(d.id)!;
    expect(jsNumOr0(view['paidAmount']), 500);
    expect(jsNumOr0(view['remaining']), 500);
    expect(view['status'], 'partial');
  });

  test('السداد الكامل يضبط الحالة مسدَّداً والمتبقي صفراً', () {
    final d = newDebt(1000);
    addTearDown(d.c.dispose);
    final repos = d.repos;
    final r = payDebtInstallment(repos, config(), repos.debts.getById(d.id)!,
        amount: 1000, date: getCurrentDate(), payment: 'كاش');
    expect(r.isFull, isTrue);
    final view = repos.debts.getById(d.id)!;
    expect(view['status'], 'paid');
    expect(jsNumOr0(view['remaining']), 0);
  });
}
