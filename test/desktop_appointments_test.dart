/// اختبارات نسخة سطح المكتب — شاشة «الحجوزات/المواعيد» (Split Layout)
/// وميزة «الموعد الدوري» الإضافية غير الكاسرة:
///   • فتح تبويب الحجوزات: الحالة الفارغة تظهر (رسالة اختيار موعد + قائمة
///     فارغة).
///   • إنشاء موعد عادي من نموذج سطح المكتب: يظهر بالقائمة، واختياره يعرض
///     التفاصيل.
///   • إنشاء موعد دوري أسبوعي بعدد 4: تتولّد 4 صفوف بتواريخ متباعدة 7 أيام
///     في المستودع (تحقّق مباشر عبر reposProvider.appointments.getAll)،
///     وكلها تحمل repeatGroup واحداً، وتفاصيل أحدها تعرض شارة الدورية
///     وقائمة السلسلة.
///   • «إلغاء بقية السلسلة»: المواعيد القادمة تصير status=cancelled.
///
/// الإقلاع كنمط desktop_shell_smoke_test: جلسة إدارة + dbDirProvider +
/// debugForceDesktopUi=true + مقاس 1600×1000. حاوية مزوّدات واحدة مشتركة
/// بين شجرة الودجت والتأكيدات (UncontrolledProviderScope) كي تُقرأ كتابات
/// الواجهة مباشرةً من المستودع.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('desk_appt_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  /// يُقلع التطبيق داخل صدفة سطح المكتب على تبويب الحجوزات، ويعيد حاوية
  /// شجرة الودجت (عبر ProviderScope.containerOf) كي تُقرأ كتابات الواجهة
  /// مباشرةً من المستودع.
  ///
  /// نستعمل ProviderScope مملوكاً للودجت (لا UncontrolledProviderScope)
  /// كنمط desktop_shell_smoke_test: فيتكفّل بتصريف الحاوية عند تفكيك
  /// الشجرة في نهاية جسم الاختبار — فتُلغى مؤقتات التطبيق (نبضة الشبكة)
  /// قبل تدقيق «لا مؤقتات معلّقة». الدخول يُبذر على حاوية مؤقتة ويُقرأ من
  /// القرص في حاوية الشجرة (remember: true).
  Future<ProviderContainer> boot(WidgetTester tester) async {
    debugForceDesktopUi = true;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // بذر التسجيل/الدخول والإعدادات على حاوية مؤقتة تُصرَّف فوراً.
    final seed = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    seed.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': ['حشو', 'قلع'],
      'payments': ['كاش', 'تحويل'],
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

    // إغلاق حوار تذكير المواعيد إن ظهر (لا يظهر عند غياب مواعيد اليوم/الغد).
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await tester.tap(ok);
      await tester.pump(const Duration(milliseconds: 200));
    }

    // الانتقال لتبويب الحجوزات.
    await tester.tap(find.byKey(const Key('desk-tab-calendar')));
    await tester.pump(const Duration(milliseconds: 300));

    // م: العرض الافتراضي صار الجدولة الأسبوعية (appt.view='week'). هذه
    // الاختبارات تخصّ عرض القائمة (master/detail) فنبدّل إليه صراحةً عبر
    // مبدّل العرض (زر «قائمة»)، فيبقى منطق القائمة والدورية مُختبَراً كما هو.
    await tester.tap(find.text('قائمة'));
    await tester.pump(const Duration(milliseconds: 300));

    // حاوية شجرة الودجت — الكتابات من الواجهة تصلها.
    return ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
  }

  /// يملأ نموذج الموعد بالحقول الأساسية (يفترض أن الحوار مفتوح).
  Future<void> fillBasics(
    WidgetTester tester, {
    required String name,
    String service = 'حشو',
  }) async {
    await tester.enterText(find.byKey(const Key('appt-form-name')), name);
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('appt-form-service')), service);
    await tester.pump();
    // التاريخ يبدأ باليوم افتراضياً — لا حاجة لفتح المنتقي.
  }

  testWidgets('فتح تبويب الحجوزات: الحالة الفارغة تظهر', (tester) async {
    await boot(tester);
    // رسالة القسم الأيسر الفارغ.
    expect(find.text('اختر موعداً لعرض التفاصيل'), findsOneWidget);
    // القائمة اليمنى فارغة (فلتر «القادمة» الافتراضي، لا مواعيد بعد).
    expect(find.byKey(const Key('appt-desk-empty-list')), findsOneWidget);
  });

  testWidgets('إنشاء موعد عادي: يظهر بالقائمة واختياره يعرض التفاصيل',
      (tester) async {
    final container = await boot(tester);

    // فتح النموذج.
    await tester.tap(find.byKey(const Key('appt-desk-add')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('appt-form-name')), findsOneWidget);

    await fillBasics(tester, name: 'سعاد عادية', service: 'كشف');
    // حفظ (موعد عادي — التكرار «بلا» افتراضاً).
    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    // صفٌّ واحد في المستودع، بلا حقول تكرار.
    final rows = container.read(reposProvider).appointments.getAll();
    expect(rows.length, 1);
    expect('${rows.first['name']}', 'سعاد عادية');
    expect(rows.first['repeatGroup'], isNull,
        reason: 'الموعد العادي بلا معرّف سلسلة');

    // يظهر في القائمة اليمنى.
    final id = '${rows.first['id']}';
    expect(find.byKey(Key('appt-desk-tile-$id')), findsOneWidget);

    // اختياره يعرض التفاصيل. (نبضتان: انتقال AnimatedSwitcher في
    // DesktopSplitView ~180ملّي ثانية يُبقي الحالة الفارغة مركّبةً أثناء
    // التلاشي، فننتظر اكتماله قبل تأكيد اختفائها.)
    await tester.tap(find.byKey(Key('appt-desk-tile-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('appt-desk-detail')), findsOneWidget);
    expect(find.text('اختر موعداً لعرض التفاصيل'), findsNothing);
  });

  testWidgets(
      'إنشاء موعد دوري أسبوعي بعدد 4: 4 صفوف متباعدة 7 أيام بمجموعة واحدة',
      (tester) async {
    final container = await boot(tester);

    await tester.tap(find.byKey(const Key('appt-desk-add')));
    await tester.pump(const Duration(milliseconds: 300));
    await fillBasics(tester, name: 'خالد الدوري', service: 'تنظيف');

    // اختيار النمط الأسبوعي.
    await tester.tap(find.byKey(const Key('appt-form-repeat-weekly')));
    await tester.pump(const Duration(milliseconds: 150));
    // العدد الافتراضي 4 (نتحقق من الملصق) — نُبقيه 4.
    expect(find.byKey(const Key('appt-form-count')), findsOneWidget);
    expect(
        (tester.widget<Text>(find.byKey(const Key('appt-form-count'))).data),
        '4');

    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    // تحقّق مباشر من المستودع: 4 صفوف.
    final rows = container.read(reposProvider).appointments.getAll()
      ..sort((a, b) =>
          '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
    expect(rows.length, 4, reason: 'تولّد 4 مواعيد فعلية');

    // كلها بمجموعة تكرار واحدة، ونمط أسبوعي، وعدّ 4، وترتيب 1..4.
    final groups =
        rows.map((r) => '${r['repeatGroup'] ?? ''}').toSet();
    expect(groups.length, 1, reason: 'repeatGroup واحد للسلسلة كلها');
    expect(groups.first.isNotEmpty, isTrue);
    for (final r in rows) {
      expect('${r['repeat']}', 'weekly');
      expect((r['repeatCount'] as num).toInt(), 4);
      // كل موعد مولّد موعد عادي 100% (نفس حقول مسار الإضافة).
      expect('${r['status']}', 'pending');
      expect('${r['_t']}', 'a');
      expect('${r['name']}', 'خالد الدوري');
      expect('${r['service']}', 'تنظيف');
    }
    final indices =
        (rows.map((r) => (r['repeatIndex'] as num).toInt()).toList()
          ..sort());
    expect(indices, [1, 2, 3, 4]);

    // التواريخ متباعدة 7 أيام بالضبط.
    for (var i = 1; i < rows.length; i++) {
      final prev = DateTime.parse('${rows[i - 1]['date']}');
      final cur = DateTime.parse('${rows[i]['date']}');
      expect(cur.difference(prev).inDays, 7,
          reason: 'التباعد بين مواعيد السلسلة 7 أيام');
    }

    // تفاصيل أحدها تعرض شارة الدورية وقائمة السلسلة.
    final firstId = '${rows.first['id']}';
    expect(find.byKey(Key('appt-desk-recur-icon-$firstId')), findsOneWidget,
        reason: 'أيقونة التكرار على البطاقة الدورية');
    await tester.tap(find.byKey(Key('appt-desk-tile-$firstId')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('appt-desk-recur-badge')), findsOneWidget);
    expect(find.byKey(const Key('appt-desk-series')), findsOneWidget);
    // كل صفوف السلسلة الأربعة ظاهرة في قسم السلسلة.
    for (final r in rows) {
      expect(find.byKey(Key('appt-desk-series-row-${r['id']}')),
          findsOneWidget);
    }
  });

  testWidgets('إلغاء بقية السلسلة: المواعيد القادمة تصير cancelled',
      (tester) async {
    final container = await boot(tester);

    await tester.tap(find.byKey(const Key('appt-desk-add')));
    await tester.pump(const Duration(milliseconds: 300));
    await fillBasics(tester, name: 'ليلى السلسلة', service: 'متابعة');
    await tester.tap(find.byKey(const Key('appt-form-repeat-weekly')));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(find.byKey(const Key('appt-form-save')));
    await tester.pump(const Duration(milliseconds: 300));

    final rows = container.read(reposProvider).appointments.getAll()
      ..sort((a, b) =>
          '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
    expect(rows.length, 4);
    // كلها قادمة (تبدأ اليوم) فلا شيء منقضٍ — الإلغاء يشمل الأربعة.

    // فتح تفاصيل أول موعد ثم «إلغاء بقية السلسلة».
    final firstId = '${rows.first['id']}';
    await tester.tap(find.byKey(Key('appt-desk-tile-$firstId')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('appt-desk-cancel-rest')));
    await tester.pump(const Duration(milliseconds: 300));

    // كل مواعيد السلسلة القادمة صارت ملغاة (تصميمنا: القادم فصاعداً يُلغى؛
    // لا منقضي هنا، فالأربعة كلها cancelled). الصفوف تبقى (لا حذف).
    final after = container.read(reposProvider).appointments.getAll();
    expect(after.length, 4, reason: 'الإلغاء لا يحذف الصفوف');
    final cancelled =
        after.where((r) => '${r['status']}' == 'cancelled').length;
    expect(cancelled, 4,
        reason: 'كل مواعيد السلسلة القادمة أصبحت cancelled');
  });
}
