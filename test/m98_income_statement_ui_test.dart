/// اختبارات م98 (واجهة) — كشف الحساب: الفتح بالعناصر الجديدة، وفلتر
/// العيادة يعيد حساب الإجمالي حيّاً (سلكُ StatefulBuilder). منطقُ المدى
/// والفرز مغطّى في m98_income_statement_test (وحدات) — هنا سلكُ الواجهة.
///
/// م133 — ورقة «دخل اليوم» القديمة (`today-income`/`sheet-income`/
/// `income-range-*`/`income-filter-*` في add_record_screen.dart) صارت
/// كوداً ميتاً حقاً: خليّتها مبنيةٌ فقط حين `!compact`
/// (`if (!widget.compact) ...` مع تعليقٍ صريح فوقها: «شريط ملخص اليوم —
/// يُخفى داخل ورقة الإدخال المضغوطة، دخل اليوم صار له تبويب الرئيسية»)،
/// وورقة الإدخال الوحيدة المتبقية `openAddRecordSheet` تبني الشاشة
/// بـ`compact: true` دوماً — فلا مسار وصولٍ متبقٍ إطلاقاً لتلك الورقة،
/// لا مجرّد نقلةٍ لمفتاحٍ جديد. البديل الفعلي (م99/م109) قسم «كشف
/// الحساب» في المالية (`StatementSection`): مدى تاريخي + بحثٌ بالاسم +
/// فلتر عيادة/فئة (تشمل طرق الدفع) بورقةٍ سفلية + إجمالي حيّ — يغطّي
/// المدى والفلترة والإجمالي الحيّ نفسها بعينها فنُعيد توجيه الاختبارات
/// الثلاثة إليه محافظين على جوهر كل تأكيد (500 ثم 400 بفلتر العيادة أو
/// طريقة الدفع) لا استبدال المضمون.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m98ui_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
    'centerName': 'مركز الاختبار',
    'clinics': ['ع1', 'ع2'],
    'services': ['حشو'],
    'payments': ['كاش', 'بطاقة'],
  };

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  Future<void> boot(WidgetTester tester) async {
    final c = container();
    await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
    await c
        .read(authProvider.notifier)
        .login('doc@clinic.ly', 'secret12', true);
    final repos = c.read(reposProvider);
    repos.settings.set('app.config', config());
    final today = getCurrentDate();
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'أحمد',
        date: today,
        amount: 100,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    saveNewRecord(
      repos,
      config(),
      SaveRecordInput(
        name: 'هدى',
        date: today,
        amount: 400,
        clinic: 'ع2',
        service: 'حشو',
        payment: 'بطاقة',
      ),
    );
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
    // م133 — «كشف الحساب» صار قسماً في تبويب «المالية» (م99) بدل ورقة
    // «دخل اليوم» على الرئيسية. البطاقة تفتح MaterialPageRoute حقيقياً
    // (م108) فتحتاج pumpAndSettle لإنهاء حركة الانتقال (نفس ما وُجد في
    // m89/m90).
    await tester.tap(find.text('المالية'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byKey(const Key('fin-seg-statement')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  // م133 — مفتاح الإجمالي الحيّ في القسم الجديد `st-total` بدل
  // `sheet-income-total` القديم.
  String totalText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('st-total'))).data!;

  testWidgets('الكشف يفتح بحقول المدى والفلاتر، والإجمالي 500', (tester) async {
    await boot(tester);

    // م133 — رأس القسم الموحّد (م109): بحثٌ بالاسم، وزرّ مدى واحد بدل
    // حقلي من/إلى، وزرّ فلاتر واحد يفتح ورقة العيادة/الفئة معاً بدل
    // منسدلتَين مستقلتين — الوظائف (مدى + فلترة) قائمة بعينها بمكانٍ
    // موحّد.
    expect(find.byKey(const Key('st-search')), findsOneWidget);
    expect(find.byKey(const Key('st-range')), findsOneWidget);
    expect(find.byKey(const Key('st-filters')), findsOneWidget);
    expect(totalText(tester), contains('500'));
  });

  testWidgets('فلتر العيادة يعيد حساب الإجمالي حيّاً', (tester) async {
    await boot(tester);
    expect(totalText(tester), contains('500'));

    // اختر العيادة ع2 من ورقة الفلاتر ⇒ الإجمالي يصير 400.
    await tester.tap(find.byKey(const Key('st-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('st-clinic-ع2')));
    await tester.pumpAndSettle();
    // إغلاق الورقة السفلية بالرجوع لقراءة الإجمالي المحدَّث في القسم.
    Navigator.of(tester.element(find.byKey(const Key('st-clinic-ع2')))).pop();
    await tester.pumpAndSettle();
    expect(
      totalText(tester),
      contains('400'),
      reason: 'م98: الفلتر يعيد الحساب حيّاً',
    );
  });

  testWidgets('فلتر الدفع «بطاقة» يُبقي 400 فقط', (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('st-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('st-cat-بطاقة')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('st-cat-بطاقة')))).pop();
    await tester.pumpAndSettle();
    expect(totalText(tester), contains('400'));
  });
}
