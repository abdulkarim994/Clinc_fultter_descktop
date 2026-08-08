/// اختبارات م28 — هندسة بطاقة السجل (عقد v48 الموحّد):
///   • اسم المعالجة هو البطل (خط 15) مرتسياً يميناً بنقطة موحدة عبر
///     البطاقات (v49) بمسافة بسيطة عن الحافة.
///   • ⋮ قرب الحافة **اليسرى** بمسافة بسيطة، متوسطة عمودياً على المحور.
///   • عمود رقاقات الأسنان بإحداثي X ثابت عبر بطاقات مختلفة (قرار
///     المالك: عمود لحاله دائم الموضع).
///   • المبلغ في يسار البطاقة والتاريخ أسفله.
///   • v48: البطاقة تشغل ~95% من عرض الشاشة، كل البطاقات بارتفاع
///     واحد مهما اختلف المحتوى، وشارة «معدل» مصغّرة (~70% — خط 8)
///     ساكنة الزاوية العلوية اليمنى.
/// المواضع تُقاس بالإحداثيات لا بالوجود فقط — فلا يتكرر انتكاس v8.
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

  setUp(() => tmp = Directory.systemTemp.createTempSync('m28_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester) async {
    // نافذة بطول هاتف حقيقي كي تظهر البطاقتان معاً للقياس الهندسي.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
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
    // حساب مُعَدّ كي تعبر بوابة الإعداد إلى الرئيسية مباشرة.
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
    });
    // بطاقة 0: دفعة جزئية بأسنان + معدل — كل الأعمدة عامرة.
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'وليد',
      'patient_name': 'وليد',
      'clinic': 'ع1',
      'service': 'حشو عصب',
      'date': '2026-07-15',
      'totalAmount': 5000,
      'paidAmount': 1500,
      'remaining': 3500,
      'status': 'partial',
      'installments': [
        {'id': 'i1', 'recordId': 'p1', 'amount': 1500, 'createdAt': 1000},
      ],
    });
    repos.records.upsertLocal({
      'id': 'p1',
      'name': 'وليد',
      'patient_name': 'وليد',
      'clinic': 'ع1',
      'service': 'دفعة دين — حشو عصب',
      'date': '2026-07-15',
      'amount': 1500,
      'payment': 'تحويل',
      'isDebtPayment': true,
      'debtId': 'd1',
      'debtPaymentType': 'partial',
      '_edited': true,
      'report': [
        {
          'teeth': [
            {'q': 'UR', 'n': 6},
            {'q': 'UR', 'n': 7},
          ],
        },
      ],
    });
    // بطاقة 1: سجل عادي بلا شارات وبلا أسنان — التناظر يبقى.
    repos.records.upsertLocal({
      'id': 'r2',
      'name': 'وليد',
      'patient_name': 'وليد',
      'clinic': 'ع1',
      'service': 'حشو',
      'date': '2026-07-27',
      'amount': 1000,
      'payment': 'كاش',
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
    await tester.pump(const Duration(milliseconds: 150));
    // إلى السجلات ← بطاقة المريض ← الملف.
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('patient-search')), 'وليد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('patient-card-وليد')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    // ظهور البطاقة الثانية للقياس.
    await tester.ensureVisible(find.byKey(const Key('rr-kebab-1')));
    await tester.pumpAndSettle();
  }

  testWidgets('هندسة البطاقة: الاسم بطل اليمين والكبب قرب الحافة اليسرى', (
    tester,
  ) async {
    await boot(tester);
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    // v49 — اسم المعالجة هو البطل: خط 15، مرتسٍ يميناً بنقطة موحدة
    // عبر البطاقات (تتراص الأسماء تحت بعض بتناظر).
    final svc = tester.getCenter(find.byKey(const Key('rr-service-1')));
    expect(
      svc.dx,
      greaterThan(screenW / 2),
      reason: 'اسم المعالجة في يمين البطاقة',
    );
    final svcText = tester.widget<Text>(find.byKey(const Key('rr-service-1')));
    expect(
      svcText.style!.fontSize,
      15,
      reason: 'اسم المعالجة أبرز عنصر (خط 15)',
    );
    final s0 = tester.getRect(find.byKey(const Key('rr-service-0')));
    final s1 = tester.getRect(find.byKey(const Key('rr-service-1')));
    expect(
      (s0.right - s1.right).abs(),
      lessThan(1),
      reason: 'الأسماء مرتسية يميناً بنقطة واحدة عبر البطاقات',
    );
    expect(
      s1.right,
      lessThan(screenW - 9),
      reason: 'الاسم لا يلاصق حافة البطاقة (مسافة بسيطة)',
    );

    // ⋮ قرب الحافة اليسرى بمسافة بسيطة ومتوسطة عمودياً على محورها.
    final kebab = tester.getCenter(find.byKey(const Key('rr-kebab-1')));
    expect(
      kebab.dx,
      lessThan(screenW * .12),
      reason: 'الكبب قرب الحافة اليسرى لا في الوسط',
    );
    final cardRect = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const Key('rr-kebab-1')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      kebab.dx,
      greaterThan(cardRect.left + 4),
      reason: 'الكبب لا يلاصق حافة البطاقة (فجوة بسيطة)',
    );
    expect(
      (kebab.dy - cardRect.center.dy).abs(),
      lessThan(12),
      reason: 'الكبب متوسط عمودياً على محور البطاقة',
    );

    // المبلغ يسار الوسط ويمين الكبب.
    final amount = tester.getCenter(find.byKey(const Key('rr-amount-1')));
    expect(amount.dx, lessThan(screenW / 2));
    expect(amount.dx, greaterThan(kebab.dx));
  });

  testWidgets('عمود الأسنان ثابت الموضع عبر البطاقات (قرار المالك)', (
    tester,
  ) async {
    await boot(tester);
    // رقاقات بطاقة الدفعة موجودة بعمودها.
    final teeth = tester.getRect(find.byKey(const Key('rr-teeth-1')));
    // العمود الفارغ للبطاقة الأخرى يحجز الموضع نفسه: قارن حواف
    // عمودي الأسنان (المملوء والفارغ) — إحداثي البداية متطابق.
    final empty = tester.getRect(find.byKey(const Key('rr-teeth-empty')));
    expect(
      (teeth.left - empty.left).abs(),
      lessThan(30),
      reason: 'عمود الأسنان بموضع ثابت بين البطاقات',
    );
    // الكبب في البطاقتين على نفس الإحداثي أيضاً (تناسق عام).
    final k0 = tester.getCenter(find.byKey(const Key('rr-kebab-0')));
    final k1 = tester.getCenter(find.byKey(const Key('rr-kebab-1')));
    expect((k0.dx - k1.dx).abs(), lessThan(1));
  });

  testWidgets('v48: عرض ~95%، ارتفاع موحد، وشارة «معدل» مصغرة بالزاوية', (
    tester,
  ) async {
    await boot(tester);
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    Rect cardOf(String key) => tester.getRect(
      find
          .ancestor(of: find.byKey(Key(key)), matching: find.byType(Container))
          .first,
    );
    final c0 = cardOf('rr-kebab-0');
    final c1 = cardOf('rr-kebab-1');

    // البطاقة تستغل الشاشة (~95% من عرضها بعد تقليص الهوامش).
    expect(
      c1.width,
      greaterThan(screenW * .93),
      reason: 'البطاقة بعرض ~95% من الشاشة',
    );

    // كل البطاقات بارتفاع واحد رغم اختلاف المحتوى (بطاقة 0 بلا
    // شارات ولا أسنان؛ بطاقة 1 عامرة بهما).
    expect(
      (c0.height - c1.height).abs(),
      lessThan(.5),
      reason: 'ارتفاع موحد لكل البطاقات',
    );

    // شارة «معدل» ساكنة الزاوية العلوية اليمنى وبحجم مصغر (~70%).
    final badge = tester.getCenter(find.byKey(const Key('rr-modified-1')));
    expect(
      badge.dx,
      greaterThan(screenW * .72),
      reason: 'الشارة في يمين البطاقة (الزاوية)',
    );
    expect(
      badge.dy - c1.top,
      lessThan(24),
      reason: 'الشارة ملتصقة بأعلى البطاقة (بإزاحة بسيطة)',
    );
    expect(badge.dx, lessThan(c1.right - 2), reason: 'الشارة لا تلاصق الحافة');
    final badgeText = tester.widget<Text>(find.text('معدل'));
    expect(
      badgeText.style!.fontSize,
      8,
      reason: 'حجم الشارة ~70% من السابق (خط 8)',
    );
  });
}
