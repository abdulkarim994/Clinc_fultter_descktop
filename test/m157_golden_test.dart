/// م157 — لقطاتٌ للمراجعة (GOLDENS=1 محلياً فقط): جدول التركيبات الجديد
/// بأعمدته الثمانية وصف الإجمالي الشامل وشارة «دفعة دين» وإشارة التعجب —
/// على الكمبيوتر والهاتف.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart'
    show debugForceDesktopUi;
import 'package:dental_clinic_flutter/features/finance/treasury_section.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter/services.dart'
    show EventChannel, FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  setUp(() => tmp = Directory.systemTemp.createTempSync('m157_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'عيادة الصفوة',
        'doctorPct': 50,
        'clinics': ['الصفوة'],
        'services': ['حشو', 'تركيبات'],
        'payments': ['كاش', 'تحويل'],
        'clinicRates': {
          'clinics': {
            'الصفوة': {'treatments': {}, 'prosthetics': 40},
          },
        },
      };

  List<Override> ov() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  /// بذر مباشر: حالتان هذا الشهر (غير دين + دين بدفعة الشهر الماضي ⇒
  /// إشارة تعجب) + دفعة هذا الشهر لدين تركيبات من الشهر الماضي ⇒ صف
  /// «دفعة دين» مستقل.
  void seed(ProviderContainer c) {
    final repos = c.read(reposProvider);
    final today = getCurrentDate(); // YYYY-MM-DD
    final prevMonthDate = () {
      final d = DateTime.parse(today);
      final pm = DateTime(d.year, d.month - 1, 15);
      return '${pm.year.toString().padLeft(4, '0')}-'
          '${pm.month.toString().padLeft(2, '0')}-15';
    }();

    // ① غير دين — زيركون 3 وحدات في معمل النور.
    repos.prosthetics.upsert({
      'id': 'p-full',
      'date': today,
      'name': 'محمد علي',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'service': 'تركيبات',
      'total': 1500,
      'labValue': 300,
      'doctorShare': 480,
      'clinicShare': 720,
      'labName': 'معمل النور',
      'prosType': 'زيركون',
      'prosUnits': 3,
      'payment': 'كاش',
      'isDebt': 0,
      '_t': 'p',
    });

    // ② دين هذا الشهر — دفعة سابقة خارج الشهر ⇒ إشارة التعجب.
    repos.prosthetics.upsert({
      'id': 'p-debt',
      'date': today,
      'name': 'خالد يوسف',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'service': 'تركيبات',
      'total': 2000,
      'labValue': 500,
      'labName': 'معمل الفجر',
      'prosType': 'ببك',
      'prosUnits': 2,
      'payment': 'دين',
      'isDebt': 1,
      '_t': 'p',
    });
    repos.debts.upsert({
      'id': 'd-new',
      'type': 'prosthetic',
      'prostheticId': 'p-debt',
      'date': today,
      'name': 'خالد يوسف',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'status': 'partial',
      'total': 2000,
      'totalAmount': 2000,
      'paidAmount': 800,
      'remaining': 1200,
      'labValue': 500,
      'service': 'تركيبات',
      'installments': [
        {'date': today, 'amount': 500, 'payment': 'كاش'},
        {'date': prevMonthDate, 'amount': 300, 'payment': 'كاش'},
      ],
    });

    // ③ حالة الشهر الماضي وديْنها — ودفعة هذا الشهر ⇒ صف «دفعة دين».
    repos.prosthetics.upsert({
      'id': 'p-old',
      'date': prevMonthDate,
      'name': 'محمد علي',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'service': 'تركيبات',
      'total': 3000,
      'labValue': 700,
      'labName': 'معمل النور',
      'prosType': 'Zirocnia',
      'prosUnits': 4,
      'payment': 'دين',
      'isDebt': 1,
      '_t': 'p',
    });
    repos.debts.upsert({
      'id': 'd-old',
      'type': 'prosthetic',
      'prostheticId': 'p-old',
      'date': prevMonthDate,
      'name': 'محمد علي',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'status': 'partial',
      'total': 3000,
      'totalAmount': 3000,
      'paidAmount': 1400,
      'remaining': 1600,
      'labValue': 700,
      'service': 'تركيبات',
      'installments': [
        {'date': prevMonthDate, 'amount': 1000, 'payment': 'كاش'},
        {'date': today, 'amount': 400, 'payment': 'كاش'},
      ],
    });
    repos.records.upsertLocal({
      'id': 'pay-n1',
      'date': today,
      'name': 'خالد يوسف',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'amount': 500,
      '_fullAmount': 500,
      '_labAmount': 250,
      '_docAmount': 125,
      'payment': 'كاش',
      'isDebtPayment': 1,
      'isPros': 0,
      'isDebt': 0,
      'debtId': 'd-new',
      'service': 'دفعة تركيبات',
    });
    repos.records.upsertLocal({
      'id': 'pay-n2',
      'date': prevMonthDate,
      'name': 'خالد يوسف',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'amount': 300,
      '_fullAmount': 300,
      '_labAmount': 150,
      '_docAmount': 75,
      'payment': 'كاش',
      'isDebtPayment': 1,
      'isPros': 0,
      'isDebt': 0,
      'debtId': 'd-new',
      'service': 'دفعة تركيبات',
    });
    repos.records.upsertLocal({
      'id': 'pay-1',
      'date': today,
      'name': 'محمد علي',
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'amount': 400,
      '_fullAmount': 400,
      '_labAmount': 200,
      '_docAmount': 100,
      'payment': 'كاش',
      'isDebtPayment': 1,
      'isPros': 0,
      'isDebt': 0,
      'debtId': 'd-old',
      'service': 'دفعة تركيبات',
    });
  }

  Future<ProviderContainer> boot(WidgetTester t,
      {required Size size, required bool desktop}) async {
    debugForceDesktopUi = desktop;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: ov());
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', config());
    seed(c);
    c.dispose();
    return ProviderContainer(overrides: ov());
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  group('لقطات م157', () {
    testWidgets('جدول التركيبات — الكمبيوتر', (t) async {
      await boot(t, size: const Size(1600, 1000), desktop: true);
      await t.pumpWidget(ProviderScope(
          overrides: ov(), child: const DentalApp()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('desk-tab-treasury')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const Key('tr2-row-الصفوة')));
      await t.pumpAndSettle();
      await t.tap(find.text('التركيبات'));
      await t.pumpAndSettle();
      await shot(t, 'm157_desktop_pros_table');
      // م158 — تفاصيل الحالة الدَّينية: كل دفعات دينها عبر الشهور.
      await t.tap(find.byKey(const Key('tr2-pros-g-خالد يوسف')));
      await t.pumpAndSettle();
      await shot(t, 'm158_desktop_case_detail');
      await t.tap(find.byKey(const Key('tr2-pros-back')));
      await t.pumpAndSettle();
      // م158 — تفاصيل صف «دفعة دين» المستقل: سجل دفعته وحده.
      await t.tap(find.textContaining('دفعة دين').first);
      await t.pumpAndSettle();
      await shot(t, 'm158_desktop_paydetail');
    }, skip: !_goldens);

    testWidgets('جدول التركيبات — الهاتف', (t) async {
      await boot(t, size: const Size(420, 900), desktop: false);
      await t.pumpWidget(ProviderScope(
        overrides: ov(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: TreasurySection()),
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('tr2-row-الصفوة')));
      await t.pumpAndSettle();
      await t.tap(find.text('التركيبات'));
      await t.pumpAndSettle();
      await shot(t, 'm157_mobile_pros_table');
      // م158 — تفاصيل الحالة على الهاتف.
      await t.tap(find.byKey(const Key('tr2-pros-g-خالد يوسف')));
      await t.pumpAndSettle();
      await shot(t, 'm158_mobile_case_detail');
    }, skip: !_goldens);
  });
}
