/// اختبارات م4 — منطق الحفظ المالي المنقول من AddRecord + ملف المريض:
/// لقطات النسب المجمّدة، الديون المرتبطة بالدفعة الأولى (regular/prosthetic
/// بحسابات labPaid/doctorEarned)، سداد الأقساط عبر recompute، والخطة
/// العلاجية في config.treatmentPlans — من الواجهة حتى القاعدة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/rates/rate_snapshot.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart' show syncFlags;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/patients/treatment_plan_store.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  late ProviderContainer c;

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'doctorPct': 50,
    'clinicRates': {
      'clinics': {
        'ع1': {
          'treatments': {'حشو': 40},
          'prosthetics': 30,
        },
      },
    },
    'clinics': ['ع1'],
    'services': ['حشو', 'تركيبات'],
    'payments': ['كاش', 'تحويل'],
  };

  setUp(() {
    // م-عزل الهوية — يوثّق هذا الملف منطق الحفظ المالي (اللقطات/الديون/
    // الأقساط) وهو **مستقلٌّ عن علم الهوية**. يثبَّت العلم OFF صراحةً كي
    // يبقى صفُّ المرضى مفتاحُه الاسمَ (getById(name)) — السلوك القديم الذي
    // تفترضه تأكيداتُه؛ الافتراضي الإنتاجي صار ON (يفصل السميّين بمعرّف
    // p:هاتف:اسم، وتغطّيه اختبارات م90/م-عزل الهوية).
    syncFlags.resetForTest();
    tmp = Directory.systemTemp.createTempSync('m4_');
    c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
  });

  tearDown(() {
    syncFlags.resetForTest();
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('resolveDoctorPct / buildRateSnapshot', () {
    test('التسلسل: معالجة العيادة ← تركيبات العيادة ← العام ← 50', () {
      final cfg = config();
      expect(resolveDoctorPct(cfg, clinic: 'ع1', service: 'حشو'), 40);
      expect(resolveDoctorPct(cfg, clinic: 'ع1', isPros: true), 30);
      expect(resolveDoctorPct(cfg, clinic: 'غيرها', service: 'حشو'), 50);
      // م180 — إعدادات بلا أي نسب = ميزة النسب مطفأة ⇒ صفر (كان 50):
      // الاحتياطي 50 يخص الحسابات التي فعّلت الميزة أو ضبطت نسباً.
      expect(resolveDoctorPct(const {}, clinic: 'x', service: 'y'), 0);
      expect(
          resolveDoctorPct(const {'ratesEnabled': true},
              clinic: 'x', service: 'y'),
          50);

      final snap = buildRateSnapshot(cfg, clinic: 'ع1', service: 'حشو');
      expect(snap['doctorPct'], 40);
      expect(snap['clinicPct'], 60);
      expect(snap['treatmentId'], 'حشو');
      final pSnap = buildRateSnapshot(
        cfg,
        clinic: 'ع1',
        service: 'تركيبات',
        isPros: true,
      );
      expect(pSnap['treatmentId'], '__prosthetics__');
      expect(pSnap['doctorPct'], 30);
    });

    test('isProsthetic — نفس التعبير النمطي', () {
      for (final s in ['تركيبات', 'تركيب جسر', 'طقم كامل', 'Crown zirconia']) {
        expect(isProsthetic(s), isTrue, reason: s);
      }
      expect(isProsthetic('حشو ضوئي'), isFalse);
    });
  });

  group('saveNewRecord — سجل عادي', () {
    test('كاش: سجل بلقطة مجمّدة + ربط المريض بآخر زيارة', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: ' أحمد الطيّب ',
          date: '2026-07-26',
          amount: 250,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
          phone: '0911111111',
        ),
      );
      expect(r.message, 'تم حفظ السجل');

      final rec = repos.records.getById(r.entryId)!;
      expect(rec['name'], 'أحمد الطيّب'); // مشذّب
      expect(rec['payment'], 'كاش');
      expect((rec['_rateSnapshot'] as Map)['doctorPct'], 40); // نسبة العيادة
      final raw = c.read(localDbProvider).queryFirst(
        'SELECT _dirty FROM records WHERE id = ?',
        [r.entryId],
      )!;
      expect(raw['_dirty'], 1); // في طابور المزامنة

      final pat = repos.patients.getById('أحمد الطيّب')!;
      expect(pat['last_visit'], '2026-07-26');
      expect(pat['phone'], '0911111111');
    });

    test('دين بدفعة أولى: دين partial + قسط + سجل دفعة أولى isDebtPayment', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: 'خالد',
          date: '2026-07-26',
          amount: 300,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
          isDebt: true,
          firstPay: 100,
        ),
      );
      expect(r.message, contains('دين جديد مرتبط'));
      final debt = repos.debts.getById(r.debtId!)!;
      expect(debt['type'], 'regular');
      expect(debt['status'], 'partial');
      expect(jsNumOr0(debt['paidAmount']), 100);
      expect(jsNumOr0(debt['remaining']), 200);
      expect(debt['recordId'], r.entryId);
      final inst = debt['installments'] as List;
      expect(inst.length, 1);
      expect(jsNumOr0((inst.single as Map)['amount']), 100);

      // السجل الأصلي payment=دين + سجل الدفعة الأولى مرتبط
      expect(repos.records.getById(r.entryId)!['payment'], 'دين');
      final payRecs = repos.records
          .getAll()
          .where((x) => jsNumOr0(x['isDebtPayment']) == 1)
          .toList();
      expect(payRecs.length, 1);
      expect(payRecs.single['service'], 'دفعة أولى (دين)');
      expect(payRecs.single['debtId'], r.debtId);
    });

    test('دفعة أولى كاملة ⇒ الدين paid فوراً', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: 'سالم',
          date: '2026-07-26',
          amount: 150,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
          isDebt: true,
          firstPay: 150,
        ),
      );
      expect(repos.debts.getById(r.debtId!)!['status'], 'paid');
    });

    test('رسائل التحقق العربية', () {
      final repos = c.read(reposProvider);
      expect(
        () => saveNewRecord(
          repos,
          config(),
          const SaveRecordInput(
            name: '',
            date: '2026-07-26',
            amount: 1,
            clinic: 'ع1',
            service: 'حشو',
            payment: 'كاش',
          ),
        ),
        throwsA(predicate((e) => '$e'.contains('يرجى إدخال اسم المريض'))),
      );
      expect(
        () => saveNewRecord(
          repos,
          config(),
          const SaveRecordInput(
            name: 'x',
            date: '2026-07-26',
            amount: 0,
            clinic: 'ع1',
            service: 'حشو',
            payment: 'كاش',
          ),
        ),
        throwsA(predicate((e) => '$e'.contains('قيمة صحيحة أكبر من صفر'))),
      );
    });
  });

  group('saveNewRecord — تركيبة', () {
    test('حصص الطبيب/العيادة من صافي التركيبة بنسبة العيادة المجمّدة', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: 'مريم',
          date: '2026-07-26',
          amount: 500,
          clinic: 'ع1',
          service: 'تركيبات',
          payment: 'كاش',
          labValue: 200,
        ),
      );
      expect(r.isPros, isTrue);
      expect(r.message, 'تم حفظ التركيبة');
      final p = repos.prosthetics.getById(r.entryId)!;
      expect(jsNumOr0(p['total']), 500);
      expect(jsNumOr0(p['labValue']), 200);
      // net 300 × 30٪ = 90 طبيب، 210 عيادة
      expect(jsNumOr0(p['doctorShare']), 90);
      expect(jsNumOr0(p['clinicShare']), 210);
      expect((p['_rateSnapshot'] as Map)['treatmentId'], '__prosthetics__');
    });

    test('تركيبة دين بدفعة أولى: labPaid وdoctorEarned وسجل الدفعة بحصصه', () {
      final repos = c.read(reposProvider);
      final r = saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: 'نوري',
          date: '2026-07-26',
          amount: 500,
          clinic: 'ع1',
          service: 'تركيبات',
          payment: 'كاش',
          labValue: 200,
          isDebt: true,
          firstPay: 250,
        ),
      );
      final d = repos.debts.getById(r.debtId!)!;
      expect(d['type'], 'prosthetic');
      expect(d['prostheticId'], r.entryId);
      expect(jsNumOr0(d['labPaid']), 200); // min(250, lab 200)
      expect(jsNumOr0(d['paidAmount']), 250);
      expect(jsNumOr0(d['remaining']), 250);
      // الفائض عن المخبر 50 × 30٪ = 15 مكسب الطبيب
      expect(jsNumOr0(d['doctorEarned']), 15);

      final payRec = repos.records.getAll().firstWhere(
        (x) => jsNumOr0(x['isDebtPayment']) == 1,
      );
      expect(payRec['service'], 'تركيبات (دفعة أولى)');
      expect(jsNumOr0(payRec['_labAmount']), 200);
      expect(jsNumOr0(payRec['_docAmount']), 15);
    });
  });

  group('الواجهة (شاشة السجل + الملف الشامل)', () {
    Future<void> boot(WidgetTester tester) async {
      final seed = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final auth = seed.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      seed.read(reposProvider).settings.set('app.config', config());
      seed.dispose();

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
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // م133 — نموذج الإدخال rec-* لم يبق على تبويب الرئيسية (صار DailyIncomeScreen،
    // م121+)؛ انتقل لورقة سفلية تُفتح بالزر العائم Key('fab-add') (app_shell.dart).
    // كل مفاتيح rec-* المُختبرة هنا باقية بلا تغيير — فقط طريقة الوصول تغيّرت.
    testWidgets('حفظ سجل من التبويب الرئيسي ثم ظهوره في ملف المريض', (
      tester,
    ) async {
      await boot(tester);

      // نموذج الإدخال صار ورقة سفلية تُفتح بالزر العائم (لا تبويب الرئيسية).
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('rec-name')), 'أحمد الطيّب');
      await tester.enterText(find.byKey(const Key('rec-amount')), '250');
      await tester.ensureVisible(find.byKey(const Key('rec-save')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rec-save')), warnIfMissed: false);
      await settle(tester);
      expect(find.text('تم حفظ السجل'), findsOneWidget);

      // م179 — الشريط صار **أسفل** افتراضياً، والشعار السفلي يغطيه حتى
      // ينقضي: يُصرَّف أولاً وإلا التقط نقرةَ التبويب (فخ القسم 11).
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);

      // تبويب السجلات ← بطاقة المريض ← الملف
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('patient-search')), 'أحمد');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-أحمد الطيّب')),
        warnIfMissed: false,
      );
      await settle(tester);

      expect(find.text('حشو'), findsWidgets); // في قائمة السجلات
      expect(find.textContaining('السجلات (1)'), findsOneWidget);
    });

    testWidgets('الخطة العلاجية: إضافة مرحلة وإنجازها يبقيان بعد الإغلاق', (
      tester,
    ) async {
      await boot(tester);
      // ابذر مريضاً وافتح ملفه
      final seed = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      seed.read(reposProvider).records.upsertLocal({
        'id': 'rم',
        'name': 'مريم',
        'clinic': 'ع1',
        'date': '2026-07-25',
        'amount': 10,
        'payment': 'كاش',
      });
      seed.dispose();
      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(tester);
      // نبضة تحديث القائمة
      await tester.enterText(find.byKey(const Key('patient-search')), 'مريم');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-مريم')),
        warnIfMissed: false,
      );
      await settle(tester);
      // افتح تبويب خطة العلاج (الأقسام تبويبية الآن).
      await tester.tap(find.byKey(const Key('psec-plan')), warnIfMissed: false);
      await settle(tester);

      // أضف مرحلة
      await tester.tap(find.byKey(const Key('tp-add')), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('tp-desc')),
        'تنظيف وتقييم أولي',
      );
      await tester.tap(find.byKey(const Key('tp-save')), warnIfMissed: false);
      await settle(tester);
      expect(find.textContaining('وتقييم'), findsOneWidget);

      // أنجِزها
      await tester.tap(
        find.byKey(const Key('tp-stage-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.textContaining('أُنجز:'), findsOneWidget);

      // v29 — الحفظ وصل إلى **صف المرحلة المستقل** في القاعدة (لا إلى
      // كتلة الإعدادات): كل مرحلة تتزامن بنفسها.
      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final store = TreatmentPlanStore(chk.read(reposProvider).settings);
      final saved = store.read('مريم', 'ع1');
      expect(saved, hasLength(1));
      expect(saved.single.done, true);
      expect(saved.single.desc, contains('وتقييم'));
    });

    // م133 — البذرة كانت بمفتاح عارٍ بالاسم («سعاد») يعتمد على هجرة إقلاعٍ
    // مرّة واحدة للعملية كلّها (_medicalMigrationRan في app_shell.dart) لترقيته
    // إلى مفتاح العيادة قبل أن يقرأه TreatmentPlanStore.importLegacy — وتلك
    // الهجرة تُشعَل (بلا عمل) من أول إقلاع boot() في اختبار سابق بهذا الملف
    // (نفس العملية)، فلا تعود تُشغَّل هنا (علمٌ عامٌ لمرّة واحدة صراحةً، توثيقه
    // في app_shell.dart: «تحسينية...تُعاد بالإقلاع التالي» لا داخل نفس الإقلاع).
    // تأكّدتُ أن الاختبار يمرّ منفرداً بلا أي تغيير (نفس هذا الترتيب حرفياً)،
    // فالعلة تلوّثُ ترتيب اختبارات الملف لا صحة الاختبار. treatment_plan_store
    // .dart يوثّق «أُلغي الاستيراد من المدخل العاري بالاسم» (م97) — فمفتاح
    // العيادة «سعاد|ع1» هو الشكل الحالي القياسي بعد أي هجرة، فأبذره مباشرة
    // (لا فرق في الجوهر: نفس المرحلتين، نفس التوقّع، فقط بلا اعتماد على تلك
    // الهجرة أحادية التشغيل داخل عملية اختبارٍ واحدة تشغّل بيوتات متعددة).
    testWidgets('الخطة العلاجية: حذف مرحلة (توأم removeStage في الأصل)', (
      tester,
    ) async {
      // بذر «قبل الإقلاع»: الخطة داخل أول لقطة إعدادات يقرؤها التطبيق.
      final seed = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final auth = seed.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      seed.read(reposProvider).records.upsertLocal({
        'id': 'rس',
        'name': 'سعاد',
        'clinic': 'ع1',
        'date': '2026-07-25',
        'amount': 10,
        'payment': 'كاش',
      });
      seed.read(reposProvider).settings.set('app.config', {
        ...config(),
        'treatmentPlans': {
          'سعاد|ع1': [
            {'id': 't1', 'desc': 'قلع', 'done': false, 'doneDate': ''},
            {'id': 't2', 'desc': 'زرع', 'done': false, 'doneDate': ''},
          ],
        },
      });
      seed.dispose();
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

      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('patient-search')), 'سعاد');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-سعاد')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('psec-plan')), warnIfMissed: false);
      await settle(tester);

      // احذف المرحلة الأولى (قلع) — يبقى (زرع) وحده واجهةً وقاعدةً.
      await tester.tap(
        find.byKey(const Key('tp-remove-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('قلع'), findsNothing);
      expect(find.text('زرع'), findsOneWidget);

      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      // v29 — الحذف = شاهد قبر على صف المرحلة: تبقى «زرع» وحدها في
      // المخزن الجديد (والخطة القديمة في الإعدادات لم تعد مصدر قراءة).
      final store = TreatmentPlanStore(chk.read(reposProvider).settings);
      final stages = store.read('سعاد', 'ع1');
      expect(stages, hasLength(1));
      expect(stages.single.desc, 'زرع');
    });

    testWidgets('سداد قسط من الملف يحدّث المتبقي والحالة عبر recompute', (
      tester,
    ) async {
      await boot(tester);
      final seed = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      final repos = seed.read(reposProvider);
      repos.patients.upsertLocal({
        'id': 'نوري',
        'name': 'نوري',
        'last_visit': '2026-07-20',
      });
      saveNewRecord(
        repos,
        config(),
        const SaveRecordInput(
          name: 'نوري',
          date: '2026-07-26',
          amount: 300,
          clinic: 'ع1',
          service: 'حشو',
          payment: 'كاش',
          isDebt: true,
          firstPay: 100,
        ),
      );
      seed.dispose();

      await tester.tap(find.text('السجلات'), warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('patient-search')), 'نوري');
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('patient-card-نوري')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('psec-debts')),
        warnIfMissed: false,
      );
      await settle(tester);

      // م43/v55 — البطاقة المطوية: «المتبقي» بالرأس وزر «دفعة» المدمج.
      expect(find.text('المتبقي'), findsWidgets);
      expect(find.text('200'), findsWidgets);
      await tester.ensureVisible(find.text('دفعة').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('دفعة').first);
      await settle(tester);
      // v33 — النافذة الموحّدة (نفس نافذة قسم الديون بالمالية).
      await tester.enterText(find.byKey(const Key('inst-amount')), '200');
      await tester.tap(
        find.byKey(const Key('inst-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);

      // v55 — الدين المسدد يختفي تلقائياً من قسم دين الملف.
      expect(find.text('لا توجد ديون'), findsOneWidget);
      final chk = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(chk.dispose);
      final d = chk
          .read(reposProvider)
          .debts
          .getAll()
          .firstWhere((x) => '${x['name']}' == 'نوري');
      expect(d['status'], 'paid');
      expect(jsNumOr0(d['remaining']), 0);
      expect((d['installments'] as List).length, 2); // الأولى + السداد
    });
  });
}
