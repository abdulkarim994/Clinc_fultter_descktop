/// اختبارات م11 — المطابقة البصرية:
///   • هيدر الملف: زر الاتصال يظهر عند وجود هاتف، لوحة ⋮ بإجراءات الأصل،
///     حذف المريض يمسح كل صفوفه وكتله المسماة بعداد حماية المرضى.
///   • بطاقة الزيارة: شارة «معدل» بعد التعديل، قائمة ⋮ بنافذة التعديل
///     الكاملة (تاريخ/دفع/قيمة) والحارس عند وجود دين، وزر إضافة الزيارة
///     الأخضر يقفز للرئيسية مربوطاً.
///   • طباعة ملف المريض: القالب يبني PDF صالحاً ويشمل شعار الإعدادات.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/print/reports.dart';
import 'package:dental_clinic_flutter/features/records/tooth_summary.dart'
    show ToothGroupLabel, ToothCrossModel;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m11_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  Future<void> boot(
    WidgetTester tester, {
    void Function(ProviderContainer c)? seed,
  }) async {
    final c = container();
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع', 'تركيبات'],
      'payments': ['كاش', 'تحويل'],
      'clinicRates': {
        'clinics': {
          'ع1': {
            'treatments': {'حشو': 40},
            'prosthetics': 30,
          },
        },
      },
    });
    seed?.call(c);
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
    // م36 — الافتراضي صار «الرئيسية»: اختبارات هذا الملف تبدأ من السجلات.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openProfile(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('patient-search')), name);
    await settle(tester);
    await tester.tap(
      find.byKey(Key('patient-card-$name')),
      warnIfMissed: false,
    );
    await settle(tester);
  }

  void seedAhmad(ProviderContainer c) {
    c.read(reposProvider).records.upsertLocal({
      'id': 'r1',
      'name': 'أحمد',
      'patient_name': 'أحمد',
      'clinic': 'ع1',
      'amount': 100,
      'date': '2026-07-01',
      'service': 'حشو',
      'payment': 'كاش',
      'phone': '0911111111',
    });
  }

  group('م11 — هيدر الملف ولوحة الإجراءات', () {
    testWidgets('زر الاتصال يظهر مع الهاتف ولوحة ⋮ بأفعال الأصل', (
      tester,
    ) async {
      await boot(tester, seed: seedAhmad);
      await openProfile(tester, 'أحمد');
      expect(find.byKey(const Key('pp-back')), findsOneWidget);
      expect(find.byKey(const Key('pp-call')), findsOneWidget);
      expect(find.byKey(const Key('pp-medical')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('pp-actions')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('pp-act-wa')), findsOneWidget);
      expect(find.byKey(const Key('pp-act-print')), findsOneWidget);
      expect(find.byKey(const Key('pp-act-edit')), findsOneWidget);
      expect(find.byKey(const Key('pp-act-del')), findsOneWidget);
    });

    testWidgets('حذف المريض من اللوحة يمسح صفوفه وكتله المسماة', (
      tester,
    ) async {
      await boot(
        tester,
        seed: (c) {
          seedAhmad(c);
          final repos = c.read(reposProvider);
          repos.debts.upsertLocal({
            'id': 'd1',
            'name': 'أحمد',
            'patient_name': 'أحمد',
            'clinic': 'ع1',
            'totalAmount': 50,
            'remaining': 50,
            'status': 'unpaid',
            'date': '2026-07-01',
          });
          repos.appointments.upsertLocal({
            'id': 'a1',
            'name': 'أحمد',
            'date': '2026-08-01',
          });
          final cfg = Map<String, Object?>.from(
            repos.settings.get('app.config') as Map,
          );
          repos.settings.set('app.config', {
            ...cfg,
            'patientMedical': {
              'أحمد': {'gender': 'ذكر'},
            },
            'treatmentPlans': {
              'أحمد': [
                {'id': 't1', 'desc': 'مرحلة', 'done': false},
              ],
            },
          });
        },
      );
      await openProfile(tester, 'أحمد');
      await tester.tap(
        find.byKey(const Key('pp-actions')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(
        find.byKey(const Key('pp-act-del')),
        warnIfMissed: false,
      );
      await settle(tester);
      // عدّاد حماية المرضى (الافتراضي 3 ثوانٍ).
      expect(find.byKey(const Key('dc-countdown')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(
        find.byKey(const Key('dc-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);

      final chk = container();
      addTearDown(chk.dispose);
      final repos = chk.read(reposProvider);
      expect(repos.records.getAll(), isEmpty);
      expect(repos.debts.getAll(), isEmpty);
      expect(repos.appointments.getAll(), isEmpty);
      final cfg = repos.settings.get('app.config') as Map;
      expect((cfg['patientMedical'] as Map).containsKey('أحمد'), isFalse);
      expect((cfg['treatmentPlans'] as Map).containsKey('أحمد'), isFalse);
    });
  });

  group('م11 — بطاقة الزيارة وقائمتها', () {
    testWidgets('تعديل عبر ⋮ يبدّل التاريخ والدفع والقيمة ويعلّم «معدل»', (
      tester,
    ) async {
      await boot(tester, seed: seedAhmad);
      await openProfile(tester, 'أحمد');
      expect(find.byKey(const Key('rr-modified-0')), findsNothing);

      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('rr-edit-0')), warnIfMissed: false);
      await settle(tester);
      // نافذة التعديل الكاملة: النوع قابل للتغيير (لا دين مرتبط).
      expect(find.byKey(const Key('edit-date-btn')), findsOneWidget);
      expect(find.byKey(const Key('edit-service')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('edit-payment')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('تحويل').last, warnIfMissed: false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('edit-amount-input')), '250');
      await tester.tap(
        find.byKey(const Key('edit-amount-save')),
        warnIfMissed: false,
      );
      await settle(tester);

      final chk = container();
      addTearDown(chk.dispose);
      final r = chk.read(reposProvider).records.getById('r1')!;
      expect(jsNumOr0(r['amount']), 250);
      expect(r['payment'], 'تحويل');
      expect(jsTruthy(r['_edited']), isTrue);
      // شارة «معدل» ظهرت.
      expect(find.byKey(const Key('rr-modified-0')), findsOneWidget);
      // م64 — قيد _audit كُتب (القيمة 100 ← 250، الدفع كاش ← تحويل).
      final audit = r['_audit'];
      expect(
        audit is List && audit.isNotEmpty,
        isTrue,
        reason: 'قيود التعديل مكتوبة على الصف',
      );
      // النقر على «معدل» يفتح سجل التعديلات (توأم Vue).
      await tester.tap(
        find.byKey(const Key('rr-modified-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.text('سجل التعديلات'), findsOneWidget);
    });

    testWidgets('الحارس: سجل بدين مرتبط لا يسمح بتغيير النوع', (tester) async {
      await boot(
        tester,
        seed: (c) {
          final repos = c.read(reposProvider);
          // م27 (تكافؤ Vue): أصل الدين (isDebt) يُخفى من الزيارات، فنختبر
          // الحارس على سجلٍ ظاهرٍ (isDebt=false) لكن له دين مرتبط عبر
          // recordId — نفس شرط hasFinancialLink في الأصل (يمنع تغيير النوع).
          repos.records.upsertLocal({
            'id': 'r1',
            'name': 'سعاد',
            'patient_name': 'سعاد',
            'clinic': 'ع1',
            'amount': 300,
            'date': '2026-07-01',
            'service': 'حشو',
            'payment': 'كاش',
          });
          repos.debts.upsertLocal({
            'id': 'd1',
            'name': 'سعاد',
            'patient_name': 'سعاد',
            'clinic': 'ع1',
            'recordId': 'r1',
            'totalAmount': 300,
            'paidAmount': 100,
            'remaining': 200,
            'status': 'partial',
            'date': '2026-07-01',
          });
        },
      );
      await openProfile(tester, 'سعاد');
      await tester.tap(
        find.byKey(const Key('rr-kebab-0')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('rr-edit-0')), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('edit-service')), findsNothing);
      expect(find.textContaining('لا يمكن تغيير نوع المعالجة'), findsOneWidget);
    });

    testWidgets(
      'م58: الدائرة العائمة تفتح ورقة الزيارة، والخيارات الكاملة تقفز للرئيسية',
      (tester) async {
        await boot(tester, seed: seedAhmad);
        await openProfile(tester, 'أحمد');
        // م58 — الزر العريض صار دائرة عائمة (FloatingActionButton).
        await tester.tap(
          find.byKey(const Key('pp-add-visit')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.text('زيارة جديدة — أحمد'), findsOneWidget);
        expect(find.byKey(const Key('qv-save')), findsOneWidget);
        // «الخيارات الكاملة» تسلك المسار القديم للرئيسية مربوطاً.
        await tester.tap(
          find.byKey(const Key('qv-full-options')),
          warnIfMissed: false,
        );
        await settle(tester);
        expect(find.byKey(const Key('rec-save')), findsOneWidget);
        final nameField = tester.widget<TextField>(
          find.byKey(const Key('rec-name')),
        );
        expect(nameField.controller!.text, 'أحمد');
      },
    );
  });

  group('م11 — طباعة ملف المريض', () {
    test('patientFilePdf يبني PDF صالحاً بالشعار', () async {
      final fonts = PdfFonts(
        regular: await rootBundle.load('assets/fonts/Cairo-Regular.ttf'),
        bold: await rootBundle.load('assets/fonts/Cairo-Bold.ttf'),
      );
      // شعار من الإعدادات (PNG 1×1) — يُحقن كما يفعل loadPdfBrand.
      pdfLogoBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      addTearDown(() => pdfLogoBytes = null);
      final bytes = await patientFilePdf(
        fonts,
        centerName: 'مركز الاختبار',
        patientName: 'أحمد',
        phone: '0911111111',
        visitCount: 2,
        currency: 'د.ل',
        reportDate: '2026-07-27',
        rows: [
          (
            date: '2026-07-15',
            service: 'تقويم',
            // م104 — الخلية صارت مجموعات ملخصة: مدى Palmer بإطار الربع.
            teeth: const [ToothGroupLabel('5-7', 'UR', palmerBorder: true)],
            cross: null,
            payment: 'كاش',
            paid: 1500,
            debt: 0,
          ),
          (
            date: '2026-07-20',
            service: 'حشو',
            teeth: const <ToothGroupLabel>[],
            cross: const ToothCrossModel(
              upperRight: '8-6',
              upperLeft: '1-3',
              lowerRight: '',
              lowerLeft: '',
            ),
            payment: 'دين',
            paid: 100,
            debt: 200,
          ),
        ],
        totalServices: 1800,
        totalPaid: 1600,
        totalRemaining: 200,
        // v50 — القسم الطبي فوق جدول المعالجات: يمرّن فرع hasMedical
        // كاملاً (جنس/عمر/حالات/تشخيص/ملاحظات) فيُكشف أي انهيار تخطيط.
        medical: {
          'gender': 'ذكر',
          'age': '45',
          'conditions': ['ضغط', 'سكري'],
          'diagnosis': 'التهاب لثة\nتسوس عميق',
          'notes': 'حساسية بنسلين',
        },
      );
      // PDF صالح وغير فارغ.
      expect(bytes.length, greaterThan(2000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('م12 — الرئيسية طبق الأصل', () {
    // م133 — نموذج الإدخال rec-* لم يبق على تبويب الرئيسية (صار DailyIncomeScreen،
    // م121+)؛ انتقل لورقة سفلية تُفتح بالزر العائم Key('fab-add') (app_shell.dart).
    // كل مفاتيح rec-* المُختبرة هنا باقية بلا تغيير — فقط طريقة الوصول تغيّرت.
    testWidgets('السويتشات الثلاثة والتاريخ الهندي وزر الحفظ الأخضر وزر +', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);

      // المفاتيح الثلاثة مفاتيح تبديل (Switch) لا رقاقات.
      expect(
        tester.widget<Switch>(find.byKey(const Key('rec-debt'))),
        isA<Switch>(),
      );
      expect(
        tester.widget<Switch>(find.byKey(const Key('rec-report-tgl'))),
        isA<Switch>(),
      );
      expect(
        tester.widget<Switch>(find.byKey(const Key('rec-medical-tgl'))),
        isA<Switch>(),
      );

      // التاريخ معروض بأرقام هندية شرقية بصيغة سنة/شهر/يوم.
      final today = getCurrentDate();
      const east = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
      final arToday = today.split('').map((ch) {
        final d = int.tryParse(ch);
        return d != null ? east[d] : (ch == '-' ? '/' : ch);
      }).join();
      expect(find.text(arToday), findsOneWidget);

      // زر الرقم الثاني مربع مستقل، والنقر يظهر حقل الرقم الثاني.
      await tester.tap(
        find.byKey(const Key('rec-phone2-add')),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(find.byKey(const Key('rec-phone2')), findsOneWidget);

      // زر الحفظ أخضر داكن (لون العلامة) لا ذهبي.
      final save = tester.widget<FilledButton>(
        find.byKey(const Key('rec-save')),
      );
      final bg = save.style?.backgroundColor?.resolve({});
      expect(bg, isNotNull);
      expect(bg!.g > bg.r, isTrue); // أخضر: القناة الخضراء تغلب

      // تفعيل سويتش الدين يعمل.
      await tester.ensureVisible(find.byKey(const Key('rec-debt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rec-debt')), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(const Key('rec-firstpay')), findsOneWidget);
    });
  });
}
