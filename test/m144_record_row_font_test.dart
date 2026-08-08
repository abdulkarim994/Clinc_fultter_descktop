/// اختبارات م144 — بروز المبلغ والتاريخ في بطاقة السجل على عرض هاتف حقيقي:
///   • الجذر المعالَج: عمود المبلغ/التاريخ كان Flexible بحصة 1 من 9 فيهبط
///     لـ~20ن على 360ن، وFittedBox يعيد تصغير النص ليطابقها — فبدا المبلغ
///     ضئيلاً مهما رُفع حجم الخط (شكوى المالك مرتين: قبل م142 وبعدها).
///   • العلاج: فتحة ثابتة amountColWidth (نمط عمود الأسنان) ترسم 17/13/12
///     بحجمها الكامل، وFittedBox داخلها صمّامُ «لا فيضان أبداً» فقط.
///   • القياس بالأبعاد المرسومة (getRect عابرة التحويلات) لا بوجود الودجت —
///     على عرض هاتفٍ حقيقي (360×800) حيث كان التقزّم يظهر، لا على عرض
///     الاختبار الافتراضي (800) حيث لم يكن ليُلتقط.
///   • بطاقة ثقيلة (أسنان + قسط + مبلغ كبير) تمرّ بلا أي فيضان (عقد م133).
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m144_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> boot(WidgetTester tester) async {
    // عرض هاتف حقيقي — هنا كان يظهر التقزّم (لا يظهر على 800 الافتراضي).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
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
    });
    // بطاقة خفيفة — توأم لقطة المالك: كاش 500 بلا أسنان.
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'وليد',
      'patient_name': 'وليد',
      'clinic': 'ع1',
      'service': 'حشو عصب',
      'date': '2026-08-05',
      'amount': 500,
      'payment': 'كاش',
    });
    // بطاقة ثقيلة — كل الأعمدة عامرة: دفعة دين بأسنان + قسط + مبلغ كبير.
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'وليد',
      'patient_name': 'وليد',
      'clinic': 'ع1',
      'service': 'حشو عصب',
      'date': '2026-07-15',
      'totalAmount': 10000,
      'paidAmount': 1500,
      'remaining': 8500,
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
    await tester.pumpAndSettle();
  }

  testWidgets('المبلغ والتاريخ بارزان على عرض هاتف (لا تقزّم Flexible)', (
    tester,
  ) async {
    await boot(tester);

    // المبلغ المرسوم كبير فعلاً: قبل م144 كان ارتفاعه المرسوم ~4ن
    // (تصغير 0.28×)؛ بعد الفتحة الثابتة ~16ن. العتبة 12 تلتقط أي عودة
    // للتقزّم مهما تغيّرت مقاييس خط الاختبار قليلاً.
    for (final i in [0, 1]) {
      final amount = tester.getRect(find.byKey(Key('rr-amount-$i')));
      expect(
        amount.height,
        greaterThan(12),
        reason: 'مبلغ البطاقة $i مرسوم بارزاً لا مقزَّماً (كان ~4ن)',
      );
    }
    // التاريخ تحت المبلغ بارز أيضاً (كان ~2.7ن).
    final date = tester.getRect(find.text('05/08/2026').first);
    expect(
      date.height,
      greaterThan(8),
      reason: 'التاريخ مقروء لا مقزَّماً (كان ~2.7ن)',
    );

    // عقد م28 محفوظ على عرض الهاتف: الكبب قرب الحافة اليسرى، المبلغ
    // يساره عن منتصف الشاشة ويمين الكبب، والاسم مرتسٍ يميناً بلا لصق.
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final kebab = tester.getCenter(find.byKey(const Key('rr-kebab-0')));
    expect(kebab.dx, lessThan(screenW * .12), reason: 'الكبب قرب الحافة');
    final amount0 = tester.getCenter(find.byKey(const Key('rr-amount-0')));
    expect(amount0.dx, lessThan(screenW / 2));
    expect(amount0.dx, greaterThan(kebab.dx));
    final svc = tester.getRect(find.byKey(const Key('rr-service-0')));
    expect(svc.right, lessThan(screenW - 9), reason: 'الاسم لا يلاصق الحافة');
    expect(
      svc.left,
      greaterThan(screenW / 2),
      reason: 'الاسم بطلُ يمين البطاقة',
    );

    // أحجام الخط المصمَّمة نفسها (17 للمبلغ) لم تُمس — الفتحة الثابتة
    // ترسمها كاملةً بدل أن يعيد FittedBox تصغيرها.
    final amountText = tester.widget<Text>(
      find.byKey(const Key('rr-amount-0')),
    );
    expect(amountText.style!.fontSize, 17);

    // البطاقة الثقيلة (أسنان + قسط + 1,500) رُسمت بلا أي فيضان: وصولنا
    // هنا بلا استثناء = عقد «لا فيضان أبداً» (م133) محفوظ مع الفتحة
    // الثابتة، وFittedBox الداخلية صمّامه.
    expect(find.byKey(const Key('rr-teeth-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
