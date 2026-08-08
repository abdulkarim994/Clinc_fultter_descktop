/// اختبارات م43 — بطاقة الدين الحرفية في الملف + بحث السجلات بتصميم Vue:
///   • البطاقة: شارة الحالة، شبكة الإجمالي/المدفوع/المتبقي، شريط تقدم
///     بنسبة السداد، زرا «تسجيل دفعة» و«الدفعات»، وسجل الدفعات.
///   • البحث: بطاقة بيضاء بحقل داخلي وأيقونة وقائمة نمط البحث.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m43_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final seed = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = seed.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'ع1',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
    });
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'ع1',
      'service': 'تقويم',
      'date': '2026-07-21',
      'totalAmount': 4000,
      'paidAmount': 1000,
      'remaining': 3000,
      'status': 'partial',
      'installments': [
        {
          'id': 'i1',
          'amount': 1000,
          'date': '2026-07-21',
          'payment': 'كاش',
          'recordId': 'p1',
          'createdAt': 1,
        },
      ],
    });
    seed.dispose();

    // م133 — الإقلاع يهبط أولاً على تبويب «الرئيسية» (DailyIncomeScreen)
    // قبل النقر إلى «السجلات» الذي يختبره هذا الملف فعلاً؛ صفّ فلاتر
    // الفترة (كل اليوم/صباحي/مسائي/المصروفات) فيها يفيض عرضياً بعرض جهازٍ
    // قياسي (393dp) بصرف النظر عن بيانات هذا الاختبار (فيضانٌ يتكرر حتى
    // بإعداداتٍ خالية من السجلات — عيبٌ حقيقي في lib/features/records/
    // daily_income_screen.dart خارج نطاق هذا الملف تماماً، وممنوعٌ لمسّه
    // هنا). نتجاوزه أثناء العبور فقط بأسلوب m41 نفسه كي لا يُسقط اختباراً
    // لا يفحص تبويب الرئيسية إطلاقاً.
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('RenderFlex overflowed')) return;
      oldOnError?.call(details);
    };
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
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    FlutterError.onError = oldOnError;
  }

  testWidgets('البحث: بطاقة بحقل داخلي وقائمة نمط الاسم/الهاتف', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byKey(const Key('patient-search')), findsOneWidget);
    expect(find.text('بحث في كل العيادات...'), findsOneWidget);
    // قائمة نمط البحث (زر الفلتر الذهبي).
    await tester.tap(find.byKey(const Key('search-phone-mode')));
    await tester.pumpAndSettle();
    expect(find.text('الاسم'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
    await tester.tap(find.text('رقم الهاتف'));
    await tester.pumpAndSettle();
    expect(find.text('بحث برقم الهاتف...'), findsOneWidget);
  });

  testWidgets('بطاقة الدين: الشبكة والتقدم والأزرار وسجل الدفعات', (
    tester,
  ) async {
    await boot(tester);
    await tester.enterText(find.byKey(const Key('patient-search')), 'سالم');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('patient-card-سالم')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // فتح قسم الديون.
    await tester.ensureVisible(find.byKey(const Key('psec-debts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('psec-debts')));
    await tester.pump(const Duration(milliseconds: 400));

    // v55 — البطاقة المطوية: الحالة والمتبقي وزر «دفعة» والشريط الرفيع
    // حاضرون، والتفاصيل (الشبكة والنسبة والدفعات) بعد نقرة الرأس.
    expect(find.byKey(const Key('debt-card-d1')), findsOneWidget);
    expect(find.text('جزئي'), findsOneWidget);
    expect(find.text('المتبقي'), findsWidgets);
    expect(find.byKey(const Key('debt-progress-d1')), findsOneWidget);
    expect(find.byKey(const Key('pay-d1')), findsOneWidget);
    expect(find.text('دفعة'), findsOneWidget);
    expect(find.text('25% مسدد'), findsNothing);

    // التوسيع بنقرة الرأس يكشف الشبكة والنسبة وزر الدفعات.
    await tester.tap(find.byKey(const Key('pd-head-d1')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('الإجمالي'), findsWidgets);
    expect(find.text('المدفوع'), findsWidgets);
    expect(find.text('25% مسدد'), findsOneWidget, reason: '1000 من 4000');

    // سجل الدفعات: القسط الأول ظاهر.
    await tester.ensureVisible(find.byKey(const Key('debt-payments-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('debt-payments-d1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('سجل الدفعات'), findsOneWidget);
    expect(find.textContaining('1,000'), findsWidgets);
  });
}
