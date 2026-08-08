/// اختبارات م89 — القفز لبطاقة المريض الصحيحة عند تشابه الأسماء بين عيادتين.
///
///  العطل الذي أبلغ عنه المالك: مريضان بنفس الاسم والكنية في عيادتين. النقر
///  على الاسم من تبويب الديون في المالية كان يفتح بطاقة المريض في العيادة
///  الخطأ، لأن حلّ العيادة كان يمسح كل الديون ويتوقف عند أول تطابق بالاسم —
///  فيخطف صفٌّ لسميٍّ في عيادة أخرى الوجهةَ.
///
///  الإصلاح: النقر يحمل عيادة صفّ الدين نفسه (الظاهرة أمام المستخدم) بدل
///  إعادة استنتاجها بالاسم. هذه الاختبارات تُثبت العطل ثم تحرسه.
///
///  لماذا نستدعي `onTap` مباشرةً بدل `tester.tap`: زرّ الاسم `InkWell`
///  متداخلٌ داخل `InkWell` رأس البطاقة (فتح/طيّ)، وفي بيئة الاختبار تذهب
///  النقرةُ الاصطناعية أحياناً للأب. استدعاء المُعالِج مباشرةً يختبر
///  **التوصيلة الفعلية** (المُعالِج ⇒ الوجهة الصحيحة) بلا هشاشة ساحة
///  الإيماءات، وهو جوهر ما نتحقّق منه.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/patients/patient_profile_screen.dart'
    show PatientProfileScreen;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m89_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// يبذر عيادتين ومريضاً بنفس الاسم في كلٍّ منهما، لكلٍّ دينُه في عيادته.
  /// دين ع1 يُدرَج **أولاً** كي يكون أوّل تطابقٍ بالاسم في مسح getAll —
  /// فيصير العطل حتمياً عند النقر على دين ع2.
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
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
      'clinics': ['ع1', 'ع2'],
      'services': ['تقويم'],
      'payments': ['كاش'],
    });
    repos.records.upsertLocal({
      'id': 'ra',
      'name': 'محمد علي',
      'patient_name': 'محمد علي',
      'clinic': 'ع1',
      'service': 'تقويم',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
    });
    repos.records.upsertLocal({
      'id': 'rb',
      'name': 'محمد علي',
      'patient_name': 'محمد علي',
      'clinic': 'ع2',
      'service': 'تقويم',
      'date': '2026-07-20',
      'amount': 100,
      'payment': 'كاش',
    });
    // دين ع1 أولاً (أوّل تطابق بالاسم في المسح) ثم دين ع2.
    repos.debts.upsertLocal({
      'id': 'da',
      'name': 'محمد علي',
      'patient_name': 'محمد علي',
      'clinic': 'ع1',
      'service': 'تقويم',
      'date': '2026-07-21',
      'totalAmount': 4000,
      'paidAmount': 1000,
      'remaining': 3000,
      'status': 'partial',
    });
    repos.debts.upsertLocal({
      'id': 'db',
      'name': 'محمد علي',
      'patient_name': 'محمد علي',
      'clinic': 'ع2',
      'service': 'تقويم',
      'date': '2026-07-22',
      'totalAmount': 5000,
      'paidAmount': 2000,
      'remaining': 3000,
      'status': 'partial',
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
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('المالية'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    // م133 — بطاقة القسم تفتح `MaterialPageRoute` حقيقياً (م108) لا مجرّد
    // تبديل حالة؛ نبضة ثابتة واحدة لا تكفي لإنهاء حركة الانتقال (~300ms)
    // فتبقى شاشة القسم خارج الشجرة عند القراءة. pumpAndSettle هنا آمنة (لا
    // مؤقّتات حيّة في قسم الديون نفسه)، بخلاف شاشة الملف بعدها التي تتجنّبها
    // tapNameAndReadClinic عمداً كما يوثّق تعليقها.
    await tester.tap(
      find.byKey(const Key('fin-seg-debts')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  /// يستدعي مُعالِج نقر اسم الدين ثم يمهّد لظهور شاشة الملف (بمؤقّتات ثابتة
  /// لا pumpAndSettle — شاشة الملف قد تحمل مؤقّتات حيّة).
  Future<String> tapNameAndReadClinic(
    WidgetTester tester,
    String debtId,
  ) async {
    final ink = tester.widget<InkWell>(find.byKey(Key('debt-name-$debtId')));
    ink.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PatientProfileScreen), findsOneWidget);
    return tester
        .widget<PatientProfileScreen>(find.byType(PatientProfileScreen))
        .clinic;
  }

  testWidgets('النقر على دين ع2 يفتح بطاقة المريض في ع2 لا في ع1', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byKey(const Key('debt-card-da')), findsOneWidget);
    expect(find.byKey(const Key('debt-card-db')), findsOneWidget);

    expect(
      await tapNameAndReadClinic(tester, 'db'),
      'ع2',
      reason: 'م89: تُفتح عيادة صفّ الدين المنقور لا أوّل تطابق بالاسم',
    );
  });

  testWidgets('النقر على دين ع1 يفتح بطاقة المريض في ع1', (tester) async {
    await boot(tester);
    expect(
      await tapNameAndReadClinic(tester, 'da'),
      'ع1',
      reason: 'م89: العيادة الأولى تبقى صحيحة أيضاً',
    );
  });
}
