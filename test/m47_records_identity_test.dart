/// اختبار م47 (v25) — هوية تبويب السجلات وتناسقه الهندسي:
///   • البوابة: الفجوة بين بطاقة البحث وأول بطاقة عيادة صغيرة (≤ 18).
///   • بطاقة العيادة مضغوطة بلا فراغ ميت: العنوان قرب قمتها والتذييل
///     قرب قاعها وارتفاعها على قدر محتواها.
///   • داخل العيادة: اسم العيادة وحقل البحث في **نفس الصف** داخل
///     بطاقة بيضاء واحدة بهوية التطبيق (حد شعري + زوايا 16)، مع زري
///     نمط البحث والفرز الذهبيين في الصف نفسه.
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m47_'));
  tearDown(() => tmp.deleteSync(recursive: true));

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
    final repos = seed.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['الصفوة', 'كاريزما'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'الصفوة',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
    });
    // دين في «الصفوة» فقط: البطاقتان تبقيان بحجم واحد رغم اختلاف
    // المحتوى (مساحة الشارة محجوزة في البطاقتين).
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'سالم',
      'patient_name': 'سالم',
      'clinic': 'الصفوة',
      'service': 'حشو',
      'date': '2026-07-20',
      'amount': 500,
      'paid': 0,
      'remaining': 500,
      'status': 'unpaid',
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
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('البوابة: البحث الموحد فوق الشبكة (v56)', (tester) async {
    await boot(tester);

    // v56 — الترتيب الجديد بطلب المالك: شريط البحث الموحد (هوية بحث
    // الديون) أولاً ثم شبكة العيادات تحته بفجوة مضبوطة.
    final searchCard = tester.getRect(
      find.byKey(const Key('landing-search-card')),
    );
    final clinicCard = tester.getRect(
      find.byKey(const Key('clinic-card-الصفوة')),
    );
    expect(
      clinicCard.top - searchCard.bottom,
      greaterThan(0),
      reason: 'البحث فوق الشبكة (الهوية الموحدة v56)',
    );
    expect(
      clinicCard.top - searchCard.bottom,
      lessThanOrEqualTo(24),
      reason: 'فجوة مضبوطة لا أكثر',
    );

    // م155 — البطاقة صفّية صغيرة بهوية الخزينة: ارتفاع مضغوط بلا فراغ.
    expect(
      clinicCard.height,
      lessThan(72),
      reason: 'بطاقة صفّية مضغوطة (هوية الخزينة م155)',
    );

    // م155 — البطاقات مرصوصة عمودياً بعرضٍ كامل موحد (بدل شبكة العمودين):
    // الثانية تحت الأولى بفجوة صغيرة وبنفس العرض والارتفاع.
    final other = tester.getRect(find.byKey(const Key('clinic-card-كاريزما')));
    expect(
      other.height,
      closeTo(clinicCard.height, 0.5),
      reason: 'بطاقات العيادات بحجم واحد',
    );
    expect(other.width, closeTo(clinicCard.width, 0.5));
    expect(
      other.top,
      greaterThan(clinicCard.bottom),
      reason: 'البطاقات صفوف متراصة عمودياً (م155)',
    );
    expect(
      other.top - clinicCard.bottom,
      lessThanOrEqualTo(12),
      reason: 'فجوة صغيرة مضبوطة بين الصفوف',
    );

    // م57 — الإحصاءات المدمجة كالأصل: «N مريض» و«N د.ل» داخل كل بطاقة.
    for (final name in ['الصفوة', 'كاريزما']) {
      final card = find.byKey(Key('clinic-card-$name'));
      expect(
        find.descendant(of: card, matching: find.textContaining('مريض')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('د.ل')),
        findsOneWidget,
      );
    }

    // العنوان قرب القمة والتذييل قرب القاع.
    final title = tester.getRect(
      find
          .descendant(
            of: find.byKey(const Key('clinic-card-الصفوة')),
            matching: find.text('الصفوة'),
          )
          .first,
    );
    expect(title.top - clinicCard.top, lessThan(32));
    final footer = tester.getRect(
      find
          .descendant(
            of: find.byKey(const Key('clinic-card-الصفوة')),
            matching: find.textContaining('زيارة هذا الشهر'),
          )
          .first,
    );
    expect(
      clinicCard.bottom - footer.bottom,
      lessThan(22),
      reason: 'التذييل ملاصق لقاع البطاقة (margin-top:auto)',
    );
  });

  testWidgets('داخل العيادة: صف واحد مدمج بقمع أدوات واحد (v59)', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(
      find.byKey(const Key('clinic-card-الصفوة')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));

    // v59 — لا بطاقة بيضاء حاضنة: صف واحد على خلفية الصفحة يجمع
    // [الرجوع | الاسم+العدد | الحقل الممتد | قمع أدوات واحد].
    expect(
      find.byKey(const Key('cp-header-card')),
      findsNothing,
      reason: 'بطاقة الهوية البيضاء أُزيلت — صف مباشر على الخلفية',
    );
    expect(find.byKey(const Key('clinic-back')), findsOneWidget);
    expect(find.text('الصفوة'), findsOneWidget);
    expect(find.text('1 مريض'), findsOneWidget);
    expect(find.byKey(const Key('cp-search')), findsOneWidget);
    expect(find.byKey(const Key('cp-tools')), findsOneWidget);
    // الأزرار الثلاثة القديمة اندمجت في القمع الواحد.
    expect(find.byKey(const Key('cp-phone-mode')), findsNothing);
    expect(find.byKey(const Key('cp-sort')), findsNothing);

    // صف واحد هندسياً: مدى الاسم العمودي يتقاطع مع الحقل والقمع.
    final nameRect = tester.getRect(find.text('الصفوة'));
    final searchRect = tester.getRect(find.byKey(const Key('cp-search')));
    final toolsRect = tester.getRect(find.byKey(const Key('cp-tools')));
    expect(nameRect.top, lessThan(searchRect.bottom));
    expect(
      nameRect.bottom,
      greaterThan(searchRect.top),
      reason: 'الاسم والحقل في صف واحد',
    );
    expect(toolsRect.top, lessThan(searchRect.bottom));
    expect(
      toolsRect.bottom,
      greaterThan(searchRect.top),
      reason: 'القمع في الصف نفسه',
    );

    // قائمة القمع تجمع الأدوات الثلاث بعناصر مؤشَّرة.
    await tester.tap(find.byKey(const Key('cp-tools')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('cp-mode-name')), findsOneWidget);
    expect(find.byKey(const Key('cp-mode-phone')), findsOneWidget);
    expect(find.byKey(const Key('cp-filter-debt')), findsOneWidget);
    expect(find.text('بحث بالاسم'), findsOneWidget);
    expect(find.text('عليه دين/متبقٍ فقط'), findsOneWidget);
    // إغلاق القائمة (نقر خارجها).
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 300));

    // البحث داخل الصف يعمل: كتابة اسم تصفي القائمة.
    await tester.enterText(find.byKey(const Key('cp-search')), 'سالم');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('سالم'), findsWidgets);
  });
}
