/// م169 — لقطاتٌ للمراجعة (GOLDENS=1 محلياً فقط): قواعد جدول الأسبوع
/// الجديدة + ترتيب نموذج الهاتف:
///   • الأسبوع المتدحرج: اليوم أول عمودٍ على اليمين (مع موعدٍ غداً).
///   • أسبوعٌ سابق: الأيام الماضية مبهتة (عرضٌ فقط).
///   • ثلاث عيادات: لا تبويب «الكل»، ونموذج الإضافة بعيادةٍ مقفلة.
///   • نموذج الهاتف: الدفعة الأولى تحت «دين» وطريقة دفع التحاليل تحت
///     مربعها مباشرة. عدة الخطوط من م154.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

final _goldens = Platform.environment.containsKey('GOLDENS');

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Qomra',
      ['Qomra-Regular.ttf', 'Qomra-Medium.ttf', 'Qomra-Bold.ttf']);
  await load(
      'Cairo', ['Cairo-Regular.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final l = FontLoader('MaterialIcons');
      l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await l.load();
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(() async {
    await _loadAppFonts();
    binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (args, events) => events.success(const ['wifi']),
      ),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => const ['wifi'],
    );
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('m169g_'));
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

  Future<void> boot(
    WidgetTester t, {
    required Size size,
    required bool desktop,
    required List<String> clinics,
    bool withTri = false,
    void Function(ProviderContainer c)? seed,
  }) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final s = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = s.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    s.read(reposProvider).settings.set('app.config', {
      'centerName': 'عيادة الصفوة',
      'clinics': clinics,
      'services': ['حشو', 'قلع', 'تركيبات'],
      'payments': ['كاش', 'تحويل'],
      'workdayStart': '09:00',
      'workdayEnd': '21:00',
      if (withTri)
        'analyses3': {'enabled': true, 'price': 50, 'repeatMonths': 6},
    });
    if (seed != null) seed(s);
    s.dispose();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: const DentalApp(),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final ok = find.byKey(const Key('appt-notif-ok'));
    if (ok.evaluate().isNotEmpty) {
      await t.tap(ok);
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  void seedAppts(ProviderContainer c) {
    final repos = c.read(reposProvider);
    // موعدان: غداً 10:00 على ع1 + بعد غدٍ 12:30 على ع2 — يوضحان الأعمدة.
    repos.appointments.upsertLocal({
      'id': 'g1',
      'name': 'سالم المتدحرج',
      'phone': '0912345678',
      'date': ymd(day0().add(const Duration(days: 1))),
      'time': '10:00',
      'clinic': 'ع1',
      'status': 'pending',
      'durationMin': 60,
    });
    repos.appointments.upsertLocal({
      'id': 'g2',
      'name': 'هدى الغد',
      'phone': '0923456789',
      'date': ymd(day0().add(const Duration(days: 2))),
      'time': '12:30',
      'clinic': 'ع2',
      'status': 'pending',
      'durationMin': 45,
    });
    // موعدٌ في الأمس — يظهر مبهتاً عند العودة أسبوعاً للخلف.
    repos.appointments.upsertLocal({
      'id': 'g3',
      'name': 'ماضي الأمس',
      'phone': '0934567890',
      'date': ymd(day0().subtract(const Duration(days: 1))),
      'time': '11:00',
      'clinic': 'ع1',
      'status': 'pending',
      'durationMin': 60,
    });
  }

  group('لقطات م169', () {
    testWidgets('الأسبوع المتدحرج — اليوم أول عمود (ثلاث عيادات بلا «الكل»)',
        (t) async {
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          clinics: ['ع1', 'ع2', 'ع3'],
          seed: seedAppts);
      await t.tap(find.byKey(const Key('desk-tab-calendar')));
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, 'm169_week_rolling_today_first');
    }, skip: !_goldens);

    testWidgets('أسبوعٌ سابق — الأيام الماضية مبهتة للعرض فقط', (t) async {
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          clinics: ['ع1', 'ع2', 'ع3'],
          seed: seedAppts);
      await t.tap(find.byKey(const Key('desk-tab-calendar')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const Key('appt-week-prev')));
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm169_week_past_dimmed');
    }, skip: !_goldens);

    testWidgets('نموذج الإضافة — العيادة مقفلة من التبويب العلوي', (t) async {
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          clinics: ['ع1', 'ع2', 'ع3'],
          seed: seedAppts);
      await t.tap(find.byKey(const Key('desk-tab-calendar')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      // تأكيدٌ أن الحوار فُتح فعلاً قبل التقاط اللقطة.
      expect(find.byKey(const Key('appt-form-clinic-locked')), findsOneWidget);
      await shot(t, 'm169_form_clinic_locked');
    }, skip: !_goldens);

    testWidgets('نموذج الإضافة بوضع الاستراحة ☕ من الجدول', (t) async {
      await boot(t,
          size: const Size(1600, 1000),
          desktop: true,
          clinics: ['ع1', 'ع2', 'ع3']);
      await t.tap(find.byKey(const Key('desk-tab-calendar')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(Key('appt-week-empty-${ymd(day0())}')),
          warnIfMissed: false);
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const Key('appt-form-break')),
          warnIfMissed: false);
      await t.pumpAndSettle(const Duration(milliseconds: 300));
      await shot(t, 'm169_break_form');
    }, skip: !_goldens);

    testWidgets('نموذج الهاتف — الحقلان الشرطيان أسفل مفتاحيهما مباشرة',
        (t) async {
      await boot(t,
          size: const Size(420, 1400),
          desktop: false,
          clinics: ['ع1'],
          withTri: true);
      await t.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await t.pumpAndSettle();
      // م169/ب — سيناريو لقطة المالك: «تركيبات» تظهر مربعات المختبر،
      // والتحاليل وطريقتها أسفلها، والدفعة الأولى تحت مفتاح الدين.
      await t.tap(find.byKey(const Key('rec-service')), warnIfMissed: false);
      await t.pumpAndSettle();
      await t.tap(find.text('تركيبات').last, warnIfMissed: false);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rec-debt')), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.byKey(const Key('rec-analysis-toggle')),
          warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 300));
      await shot(t, 'm169_phone_form_inline_fields');
    }, skip: !_goldens);
  });
}
