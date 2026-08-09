/// م150 — انحدار بلاغ المالك (2026-08-09): «حذف سجل مريض من الكمبيوتر غير
/// فعال أبداً» — بعد تأكيد الحذف كانت قائمة الثلاث نقاط تبقى معلقة ولا
/// يُحذف شيء.
///
/// الجذر: على الكمبيوتر يعيش ملف المريض داخل ملاّح DetailHost المتداخل
/// بينما حوار الإجراءات على الملاّح الجذري؛ بنود القائمة كانت تُغلق
/// بـ Navigator.pop(context) بسياق **الشاشة** فيسقط ملف المريض من اللوح
/// (لا الحوار)، ثم يرتد _deletePatient على حارس !mounted بصمت.
///
/// الاختبار يحاكي المسار الحقيقي كاملاً على واجهة سطح المكتب: تبويب
/// السجلات ← اختيار المريض ← ⋮ ← حذف المريض ← عدّاد الحماية ← تأكيد —
/// ويثبت أن الحوار انغلق فور اختيار البند وأن الصفوف حُذفت من القاعدة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/staff/staff_session.dart'
    show kCurrentStaff;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m150_');
    kCurrentStaff = null;
  });
  tearDown(() {
    debugForceDesktopUi = null;
    kCurrentStaff = null;
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer container() => ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);

  Future<void> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = container();
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش', 'تحويل'],
    });
    // مريض بزيارة واحدة — توأم بذر m11 حرفياً.
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
    await tester.pump(const Duration(milliseconds: 250));

    // تبويب «السجلات» المكتبي (id: clinics).
    await tester.tap(find.byKey(const Key('desk-tab-clinics')));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
      'سطح المكتب: حذف المريض من ⋮ يغلق الحوار فوراً ويحذف الصفوف فعلاً',
      (tester) async {
    await boot(tester);

    // اختيار المريض من قائمة الأسماء ⇒ يفتح ملفه في لوح التفصيل (DetailHost).
    await tester.tap(find.text('أحمد').first, warnIfMissed: false);
    await settle(tester);
    expect(find.byKey(const Key('pp-actions')), findsOneWidget,
        reason: 'ملف المريض انفتح في لوح التفصيل');

    // فتح حوار الإجراءات (⋮) — نسخة الكمبيوتر حوار مركزي.
    await tester.tap(find.byKey(const Key('pp-actions')), warnIfMissed: false);
    await settle(tester);
    expect(find.byKey(const Key('pp-act-del')), findsOneWidget);

    // «حذف المريض» ⇒ الحوار ينغلق فوراً (كان يبقى معلقاً قبل الإصلاح)
    // ويظهر عدّاد حماية المرضى.
    await tester.tap(find.byKey(const Key('pp-act-del')), warnIfMissed: false);
    await settle(tester);
    expect(find.byKey(const Key('pp-act-wa')), findsNothing,
        reason: 'قائمة الإجراءات انغلقت بسياقها هي لا بسياق الشاشة');
    expect(find.byKey(const Key('dc-countdown')), findsOneWidget,
        reason: 'نافذة التأكيد بعدّادها ظهرت');

    // انقضاء العدّاد (الافتراضي 3 ثوانٍ) ثم التأكيد.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.byKey(const Key('dc-confirm')), warnIfMissed: false);
    await settle(tester);

    // نافذة التأكيد انغلقت ولا استثناءات معلقة.
    expect(find.byKey(const Key('dc-confirm')), findsNothing);
    expect(tester.takeException(), isNull);

    // الحذف نفذ فعلاً: لا صفوف للمريض في القاعدة.
    final chk = container();
    addTearDown(chk.dispose);
    expect(chk.read(reposProvider).records.getAll(), isEmpty,
        reason: 'صف الزيارة حُذف من القاعدة (كان يبقى قبل الإصلاح)');
  });
}
