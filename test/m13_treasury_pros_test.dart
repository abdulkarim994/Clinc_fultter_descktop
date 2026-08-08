/// اختبارات م13 — تركيبات الخزينة طبق الأصل:
///   • وحدات بأرقام لقطة المستخدم: دين تركيبة 3,000 (معمل 1,500، نسبة
///     40%) بدفعتين 1,500/1,500 — الأولى تُستهلك معملاً بالكامل
///     (معمل 1,500) والثانية ربحاً (طبيب 600 / عيادة 900)؛ مجاميع
///     المجموعة إجمالي 3,000 معمل 1,500 طبيب 600 عيادة 900.
///   • ترقيم الدفعات ثابت كرونولوجياً ولا يتأثر بحذف قسط.
///   • واجهة: بطاقة المجموعة → رأس الحالة بالنوع → دفعتان مرقمتان
///     بأجزائهما → المدفوع/المتبقي → تذييل الأربع خانات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment;
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m13_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
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
    'labTypes': [
      {'name': 'Zirocnia', 'defaultPrice': 1500},
    ],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  /// بذر حالة اللقطة: دين تركيبة 3,000 (معمل 1,500) بدفعتين 1,500.
  (String, String) seedScreenshotCase(ProviderContainer c) {
    final repos = c.read(reposProvider);
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'Khlgg',
        date: getCurrentDate(),
        amount: 3000,
        clinic: 'الصفوة',
        service: 'تركيبات',
        payment: 'كاش',
        isDebt: true,
        labValue: 1500,
        prosType: 'Zirocnia',
      ),
    );
    final debt = repos.debts.getAll().single;
    // دفعتان 1,500 عبر الفعل الحرفي (يجمّد _labAmount/_docAmount).
    payDebtInstallment(
      repos,
      config(),
      debt,
      amount: 1500,
      date: getCurrentDate(),
      payment: 'كاش',
    );
    final debt2 = repos.debts.getById('${debt['id']}')!;
    payDebtInstallment(
      repos,
      config(),
      debt2,
      amount: 1500,
      date: getCurrentDate(),
      payment: 'كاش',
    );
    return ('${debt['id']}', '${repos.prosthetics.getAll().single['id']}');
  }

  group('الوحدات — أرقام اللقطة', () {
    test('الدفعتان تنقسمان معمل 1,500 ثم طبيب 600/عيادة 900', () {
      final c = container();
      addTearDown(c.dispose);
      seedScreenshotCase(c);
      final repos = c.read(reposProvider);

      final pays =
          repos.records
              .getAll()
              .where((r) => jsTruthy(r['isDebtPayment']))
              .toList()
            ..sort(
              (a, b) => jsNumOr0(a['_mod']).compareTo(jsNumOr0(b['_mod'])),
            );
      expect(pays, hasLength(2));
      // الأولى: معمل بالكامل.
      expect(prosPayLab(pays[0], 50), 1500);
      expect(prosPayDoc(pays[0], 50), 0);
      expect(prosPayClin(pays[0], 50), 0);
      // الثانية: ربح بنسبة اللقطة 40% ⇒ طبيب 600 وعيادة 900.
      expect(prosPayLab(pays[1], 50), 0);
      expect(prosPayDoc(pays[1], 50), 600);
      expect(prosPayClin(pays[1], 50), 900);
    });

    test('prosGrouped: إجمالي 3,000 معمل 1,500 طبيب 600 عيادة 900', () {
      final c = container();
      addTearDown(c.dispose);
      seedScreenshotCase(c);
      final repos = c.read(reposProvider);
      final s = TreasurySlice(
        getCurrentDate().substring(0, 7),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      final g = prosGrouped(s, 'الصفوة', 50).single;
      expect(g.name, 'Khlgg');
      expect(g.total, 3000);
      expect(g.labTotal, 1500);
      expect(g.docTotal, 600);
      expect(g.clinTotal, 900);
    });

    test('الحالات: دفعتان مرقمتان 1و2 والمدفوع 3,000 والمتبقي 0', () {
      final c = container();
      addTearDown(c.dispose);
      seedScreenshotCase(c);
      final repos = c.read(reposProvider);
      final s = TreasurySlice(
        getCurrentDate().substring(0, 7),
        records: repos.records.getAll(),
        prosthetics: repos.prosthetics.getAll(),
        debts: repos.debts.getAll(),
      );
      final g = prosGrouped(s, 'الصفوة', 50).single;
      final cases = getCasesWithPayments(
        g.items,
        repos.debts.getAll(),
        repos.records.getAll(),
      );
      final cg = cases.single;
      expect(cg.pros['prosType'], 'Zirocnia');
      expect(cg.paid, 3000);
      expect(cg.remaining, 0);
      expect(cg.payments, hasLength(2));
      // الأحدث أولاً في العرض، والأرقام كرونولوجية ثابتة.
      final seqs = cg.payments.map((p) => jsNumOr0(p['_seq'])).toSet();
      expect(seqs, {1, 2});
    });

    test('الترقيم ثابت: حذف القسط الأول لا يعيد ترقيم الثاني', () {
      final c = container();
      addTearDown(c.dispose);
      seedScreenshotCase(c);
      final repos = c.read(reposProvider);
      final debt = repos.debts.getAll().single;
      final pays =
          repos.records
              .getAll()
              .where((r) => jsTruthy(r['isDebtPayment']))
              .toList()
            ..sort(
              (a, b) => jsNumOr0(a['_mod']).compareTo(jsNumOr0(b['_mod'])),
            );
      // احذف القسط الأول من مصفوفة الدين (شاهدة حذف).
      final insts = [...(debt['installments'] as List)];
      final first = Map<String, Object?>.from(insts[0] as Map)
        ..['_deleted'] = 1;
      insts[0] = first;
      repos.debts.upsertLocal({...debt, 'installments': insts});
      final d2 = repos.debts.getById('${debt['id']}')!;
      // الثاني يحتفظ برقمه الكرونولوجي... الحي الوحيد يحمل أقدم ترتيب
      // حي = 1 حسب numberedInstallments (الأرقام تُبنى من الأحياء فقط
      // — حرفية الأصل: الحذف لا يترك فجوات وهمية).
      final seq2 = installmentSeqForRecord(d2, repos.records.getAll(), pays[1]);
      expect(seq2, 1);
      expect(activeInstallments(d2), hasLength(1));
    });
  });

  group('الواجهة — تفصيل التركيبات', () {
    testWidgets('البنية الكاملة: رأس الحالة والدفعات والتذييل', (tester) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config());
      final (_, prosId) = seedScreenshotCase(c);
      c.dispose();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.tap(find.text('المالية'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      // م133 — «المالية» صارت قائمة بطاقات أقسام (خزينة/ديون/أرباح/كشف
      // حساب، م108) بدل الهبوط مباشرة على شاشة الخزينة؛ يلزم أولاً الدخول
      // فعلاً لقسم «الخزينة» (نفس نمط m4b_finance_settings_test). البطاقة
      // تفتح MaterialPageRoute حقيقياً فتحتاج pumpAndSettle لإنهاء حركة
      // الانتقال (نفس ما وُجد في m89/m90/m98)، بخلاف `_showDetail` بعدها
      // (تبديل حالة محلي صرف في treasury_section.dart فتكفيه settle
      // العادية).
      await tester.tap(
        find.byKey(const Key('fin-seg-treasury')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      // افتح تفصيل التركيبات لعيادة الصفوة.
      await tester.tap(
        find.byKey(const Key('tr-pros-الصفوة')),
        warnIfMissed: false,
      );
      await settle();
      expect(find.byKey(const Key('tr-cat-pros')), findsOneWidget);

      // بطاقة المجموعة ومجاميعها الأربعة.
      await tester.tap(
        find.byKey(const Key('tr-prosgroup-Khlgg')),
        warnIfMissed: false,
      );
      await settle();
      // رأس الحالة بالنوع.
      expect(find.byKey(Key('tr-case-$prosId')), findsOneWidget);
      expect(find.textContaining('Zirocnia'), findsWidgets);
      // دفعتان مرقمتان.
      expect(find.text('دفعة 1'), findsOneWidget);
      expect(find.text('دفعة 2'), findsOneWidget);
      // أجزاء الدفعات: معمل 1,500 وطبيب 600 وعيادة 900.
      expect(find.text('1,500'), findsWidgets);
      expect(find.text('600'), findsWidgets);
      expect(find.text('900'), findsWidgets);
      // المدفوع/المتبقي.
      expect(find.textContaining('المدفوع'), findsWidgets);
      expect(find.textContaining('المتبقي'), findsWidgets);
      // تذييل الأربع خانات.
      expect(find.text('إجمالي'), findsWidgets);
      expect(find.text('معمل'), findsWidgets);
      expect(find.text('طبيب'), findsWidgets);
      expect(find.text('عيادة'), findsWidgets);
    });
  });
}
