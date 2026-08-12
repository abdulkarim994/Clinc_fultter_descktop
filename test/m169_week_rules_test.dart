/// م169 — قواعد جدول الأسبوع الجديدة + ترتيب نموذج الهاتف:
///   • الأسبوع متدحرجٌ يبدأ من اليوم (اليوم أول عمود، لا أمس فيه).
///   • الأيام السابقة للعرض فقط: النقر على خانةٍ فارغة فيها يُظهر رسالةً
///     ولا يفتح النموذج.
///   • تبويب «الكل» متاحٌ مع عيادتين بالضبط، ويُزال مع ثلاثٍ فصاعداً
///     (الفلتر الفعلي يؤول لأول عيادة).
///   • «الكل» (عيادتان) عرضٌ فقط: الإضافة محجوبة برسالةٍ حتى تُختار عيادة.
///   • الإضافة من تبويب عيادةٍ محددة تقفل حقل العيادة في النموذج.
///   • نموذج الهاتف: «الدفعة الأولى» فوراً أسفل مفتاح «دين»، و«طريقة دفع
///     التحاليل» فوراً أسفل مربع التحاليل (قبل صف تحديد الأسنان).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_tab.dart'
    show apptRevProvider;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m169_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DateTime day0() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// إقلاعٌ مكتبي على تبويب الحجوزات بقائمة عيادات معطاة (نمط
  /// desktop_appointments_week_test حرفياً).
  Future<void> bootDesk(WidgetTester tester,
      {required List<String> clinics}) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': clinics,
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
      'workdayStart': '09:00',
      'workdayEnd': '21:00',
    });
    s.dispose();

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

    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await tester.tap(ok);
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(find.byKey(const Key('desk-tab-calendar')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('م169 — الأسبوع المتدحرج وقفل الماضي', () {
    testWidgets('اليوم أول أعمدة الأسبوع ولا وجود للأمس', (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      final today = day0();
      expect(find.byKey(Key('appt-week-empty-${ymd(today)}')), findsOneWidget);
      expect(
          find.byKey(Key(
              'appt-week-empty-${ymd(today.add(const Duration(days: 6)))}')),
          findsOneWidget);
      expect(
          find.byKey(Key(
              'appt-week-empty-${ymd(today.subtract(const Duration(days: 1)))}')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('النقر على يومٍ سابق يُظهر رسالة القفل ولا يفتح النموذج',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      // أسبوعٌ للخلف — الأمس صار ضمن الأعمدة المعروضة.
      await tester.tap(find.byKey(const Key('appt-week-prev')));
      await tester.pump(const Duration(milliseconds: 200));
      final yesterday = ymd(day0().subtract(const Duration(days: 1)));
      expect(find.byKey(Key('appt-week-empty-$yesterday')), findsOneWidget);
      await tester.tap(find.byKey(Key('appt-week-empty-$yesterday')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('الأيام السابقة للعرض فقط'), findsOneWidget);
      expect(find.text('موعد جديد'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('م169 — قاعدة «الكل» وقفل العيادة', () {
    testWidgets('عيادتان ⇒ تبويب «الكل» حاضر، والإضافة معه محجوبة برسالة',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1', 'ع2']);
      expect(find.byKey(const Key('appt-desk-clinic-all')), findsOneWidget);
      // الافتراضي «الكل» — النقر على خانة اليوم لا يفتح النموذج بل رسالة.
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('للعرض فقط — اختر عيادةً'), findsOneWidget);
      expect(find.text('موعد جديد'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ثلاث عيادات ⇒ لا تبويب «الكل» والفلتر يؤول لأول عيادة',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1', 'ع2', 'ع3']);
      expect(find.byKey(const Key('appt-desk-clinic-all')), findsNothing);
      expect(find.byKey(const Key('appt-desk-clinic-ع1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الإضافة من تبويب عيادةٍ محددة تقفل حقل العيادة بالنموذج',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1', 'ع2', 'ع3']);
      // الفلتر الفعلي = ع1 (لا «الكل» مع ثلاث عيادات) — نضيف من خانة اليوم.
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('موعد جديد'), findsOneWidget);
      // الحقل المقفول حاضرٌ بنص العيادة، والقائمة المنسدلة غائبة.
      expect(find.byKey(const Key('appt-form-clinic-locked')), findsOneWidget);
      expect(find.text('العيادة: ع1'), findsOneWidget);
      expect(find.byKey(const Key('appt-form-clinic')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('اختيار ع2 من التبويبات يقفل النموذج على ع2', (tester) async {
      await bootDesk(tester, clinics: ['ع1', 'ع2', 'ع3']);
      await tester.tap(find.byKey(const Key('appt-desk-clinic-ع2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('العيادة: ع2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('م169/ب — كشف التعارض والاستراحة في نموذج الكمبيوتر', () {
    /// بذر صفٍّ في مواعيد الشجرة بعد الإقلاع (نمط الاختبار الأسبوعي).
    void seedRow(WidgetTester tester, Map<String, Object?> row) {
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      c.read(reposProvider).appointments.upsertLocal(row);
    }

    int apptCount(WidgetTester tester) {
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      return c.read(reposProvider).appointments.getAll().length;
    }

    testWidgets('الحجز فوق استراحة ⇒ منعٌ قاطع برسالة (لا كتابة)',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      // استراحة تغطي كامل الدوام اليوم — أي وقتٍ يتعارض معها.
      seedRow(tester, {
        'id': 'brk-all',
        'name': 'استراحة',
        'date': ymd(day0()),
        'time': '09:00',
        'clinic': 'ع1',
        'status': 'pending',
        'isBreak': 1,
        'durationMin': 720,
        '_t': 'a',
      });
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('appt-form-name')), 'مريض جديد');
      final before = apptCount(tester);
      await tester.tap(find.byKey(const Key('appt-form-save')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('لا يمكن الحجز فوق استراحة'), findsOneWidget);
      expect(apptCount(tester), before, reason: 'المنع قاطع — لا صف جديد');
      expect(tester.takeException(), isNull);
    });

    testWidgets('تعارض موعد مريضٍ آخر ⇒ حوارٌ بالاسم، والإلغاء لا يكتب',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      // موعدٌ يغطي كامل الدوام اليوم — أي وقتٍ يتعارض معه.
      seedRow(tester, {
        'id': 'busy-all',
        'name': 'فلان المشغول',
        'date': ymd(day0()),
        'time': '09:00',
        'clinic': 'ع1',
        'status': 'pending',
        'durationMin': 720,
        '_t': 'a',
      });
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
          find.byKey(const Key('appt-form-name')), 'مريض جديد');
      final before = apptCount(tester);
      await tester.tap(find.byKey(const Key('appt-form-save')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      // حوار التعارض باسم صاحب الموعد — توأم معالج الهاتف.
      expect(find.text('تعارض بالوقت'), findsOneWidget);
      expect(find.textContaining('فلان المشغول'), findsWidgets);
      // «تغيير الوقت» يلغي — لا كتابة.
      await tester.tap(find.byKey(const Key('appt-conflict-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(apptCount(tester), before);
      // إعادة الحفظ ثم «حفظ رغم التعارض» ⇒ تُكتب.
      await tester.tap(find.byKey(const Key('appt-form-save')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('appt-conflict-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(apptCount(tester), before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('حجز استراحة من الجدول: مفتاح ☕ يكتب isBreak: 1',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      await tester.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      // تفعيل وضع الاستراحة — الهاتف/الخدمة/التكرار تختفي.
      await tester.tap(find.byKey(const Key('appt-form-break')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('appt-form-phone')), findsNothing);
      expect(find.byKey(const Key('appt-form-service')), findsNothing);
      await tester.tap(find.byKey(const Key('appt-form-save')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      final rows = c.read(reposProvider).appointments.getAll();
      expect(rows.length, 1);
      expect('${rows.first['isBreak']}', '1', reason: 'علم رقمي لا bool');
      expect('${rows.first['name']}', 'استراحة',
          reason: 'الاسم الافتراضي عند تركه فارغاً');
      expect(tester.takeException(), isNull);
    });
  });

  group('م169/ج — الجدول والقائمة أساسٌ واحد', () {
    testWidgets('حجزٌ مشتق من سجل زيارة (appointment) يظهر في جدول الأسبوع',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      // سجل زيارةٍ يحمل حقل appointment لغدٍ — كما تعرضه القائمة تماماً.
      c.read(reposProvider).records.upsertLocal({
        'id': 'r-appt-1',
        'name': 'موعد من السجل',
        'date': ymd(day0()),
        'appointment': ymd(day0().add(const Duration(days: 1))),
        'clinic': 'ع1',
        'amount': 100,
        'paid': 100,
        'payment': 'كاش',
        '_t': 'r',
      });
      c.read(apptRevProvider.notifier).state++;
      await tester.pump(const Duration(milliseconds: 300));
      // يظهر في شريط «بلا وقت» بالجدول (لا وقت له — تاريخٌ فقط).
      expect(find.byKey(const Key('appt-week-notime')), findsOneWidget);
      expect(find.textContaining('موعد من السجل'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الإضافة من الجدول ثم الحذف يزيل البطاقة فوراً (مصدر واحد)',
        (tester) async {
      await bootDesk(tester, clinics: ['ع1']);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      );
      // إضافة موعدٍ حقيقي غداً 10:00 (كما تكتبه القائمة الهاتفية تماماً).
      c.read(reposProvider).appointments.upsertLocal({
        'id': 'sync-1',
        'name': 'مزامنة العرضين',
        'date': ymd(day0().add(const Duration(days: 1))),
        'time': '10:00',
        'clinic': 'ع1',
        'status': 'pending',
        'durationMin': 60,
        '_t': 'a',
      });
      c.read(apptRevProvider.notifier).state++;
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.byKey(const Key('appt-week-card-sync-1')), findsOneWidget);
      // الحذف من المستودع (مسار القائمة نفسه) يزيل بطاقة الجدول.
      c.read(reposProvider).appointments.delete('sync-1');
      c.read(apptRevProvider.notifier).state++;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('appt-week-card-sync-1')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('م169 — ترتيب نموذج الهاتف', () {
    Future<void> bootPhoneForm(WidgetTester tester) async {
      debugForceDesktopUi = false;
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = ProviderContainer(overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ]);
      final auth = s.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      s.read(reposProvider).settings.set('app.config', {
        'centerName': 'م',
        'clinics': ['ع1'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'analyses3': {'enabled': true, 'price': 50, 'repeatMonths': 6},
      });
      s.dispose();
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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    testWidgets('«الدفعة الأولى» فوراً أسفل مفتاح «دين» (قبل صف الأسنان)',
        (tester) async {
      await bootPhoneForm(tester);
      // تفعيل الدين — الحقل يظهر تحت الصف مباشرة لا في ذيل النموذج.
      await tester.tap(find.byKey(const Key('rec-debt')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      final firstPayY =
          tester.getTopLeft(find.byKey(const Key('rec-firstpay'))).dy;
      final teethY =
          tester.getTopLeft(find.byKey(const Key('rec-report-tgl'))).dy;
      final debtY = tester.getTopLeft(find.byKey(const Key('rec-debt'))).dy;
      expect(firstPayY, greaterThan(debtY),
          reason: 'الدفعة الأولى تحت مفتاح الدين');
      expect(firstPayY, lessThan(teethY),
          reason: 'الدفعة الأولى قبل صف تحديد الأسنان (لا في ذيل النموذج)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('مع «تركيبات»: مربع التحاليل وطريقته أسفل مربعات المختبر',
        (tester) async {
      await bootPhoneForm(tester);
      // اختيار معالجة «تركيبات» يظهر مربعات المختبر.
      await tester.tap(find.byKey(const Key('rec-service')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تركيبات').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rec-analysis-toggle')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      final labY =
          tester.getTopLeft(find.byKey(const Key('rec-labname'))).dy;
      final triY = tester
          .getTopLeft(find.byKey(const Key('rec-analysis-toggle')))
          .dy;
      final payY =
          tester.getTopLeft(find.byKey(const Key('rec-analysis-pay'))).dy;
      expect(triY, greaterThan(labY),
          reason: 'مربع التحاليل أسفل مربعات المختبر (م169/ب)');
      expect(payY, greaterThan(triY),
          reason: 'طريقة الدفع أسفل مربع التحاليل مباشرة');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«طريقة دفع التحاليل» فوراً أسفل مربع التحاليل',
        (tester) async {
      await bootPhoneForm(tester);
      await tester.tap(find.byKey(const Key('rec-analysis-toggle')),
          warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      final payY =
          tester.getTopLeft(find.byKey(const Key('rec-analysis-pay'))).dy;
      final toggleY =
          tester.getTopLeft(find.byKey(const Key('rec-analysis-toggle'))).dy;
      final teethY =
          tester.getTopLeft(find.byKey(const Key('rec-report-tgl'))).dy;
      expect(payY, greaterThan(toggleY),
          reason: 'طريقة الدفع تحت مربع التحاليل مباشرة');
      expect(payY, lessThan(teethY),
          reason: 'طريقة الدفع قبل صف تحديد الأسنان (لا في ذيل النموذج)');
      expect(tester.takeException(), isNull);
    });
  });
}
