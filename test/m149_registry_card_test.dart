/// م149 — اختبارات بطاقة «سجلات التحاليل الثلاثية» المستقلة + لقطاتها.
///
/// (أ) وظيفية (تعمل دائماً): البطاقة تعرض تحاليل الشهر الجاري وحدها
///     بالأعمدة الأربعة، الفلاتر الثلاثة تتركب (بحث/طريقة/عيادة)، تذييل
///     إجمالي الشهر يتبع الفلاتر، والحذف يزيل الصف من القاعدة.
/// (ب) لقطات (GOLDENS=1 محلياً فقط): نموذج سطح المكتب (جدول) ونموذج
///     الهاتف (قائمة مكثفة) بخطوط التطبيق الحقيقية لمراجعة المالك.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate, jsTruthy;
import 'package:dental_clinic_flutter/features/finance/analyses_registry.dart';
import 'package:dental_clinic_flutter/features/records/analysis_actions.dart'
    show showTriRepeatBlockedDialog;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show addMonths, kTriAnalysesCfgKey, kTriAnalysesName;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
// م133 — `Override` تُصدَّر من `misc.dart` في Riverpod 3 لا من الجذر.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

typedef JMap = Map<String, Object?>;

final _goldens = Platform.environment.containsKey('GOLDENS');

/// تحميل خطوط التطبيق الحقيقية للقطات (توأم عدة m146 المختصرة).
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Qomra', [
    'Qomra-Regular.ttf',
    'Qomra-Medium.ttf',
    'Qomra-Bold.ttf',
  ]);
  await load('Cairo', [
    'Cairo-Regular.ttf',
    'Cairo-SemiBold.ttf',
    'Cairo-Bold.ttf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final iconsFile = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconsFile.existsSync()) {
      final iconsLoader = FontLoader('MaterialIcons');
      final iconBytes = iconsFile.readAsBytesSync();
      iconsLoader.addFont(Future.value(ByteData.view(iconBytes.buffer)));
      await iconsLoader.load();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(_loadAppFonts);
  setUp(() => tmp = Directory.systemTemp.createTempSync('m149_card_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  JMap config() => {
        'centerName': 'مركز الاختبار',
        'doctorPct': 50,
        'clinics': ['الصفوة', 'النخبة'],
        'services': ['حشو'],
        'payments': ['كاش', 'تحويل'],
        kTriAnalysesCfgKey: {'enabled': true, 'price': 50, 'repeatMonths': 6},
      };

  List<Override> overrides() => [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ];

  /// يبذر: زيارتين بتحليلين هذا الشهر (أحمد|الصفوة|كاش، سارة|النخبة|تحويل)
  /// + تحليلاً قديماً (قبل شهرين — يظهر في الأرشيف خارج إجمالي الشهر).
  void seed() {
    final c = ProviderContainer(overrides: overrides());
    final repos = c.read(reposProvider);
    final today = getCurrentDate();
    repos.settings.set('app.config', config());

    String visit(String name, String clinic, String pay) => saveNewRecord(
          repos,
          config(),
          SaveRecordInput(
            name: name,
            date: today,
            amount: 200,
            clinic: clinic,
            service: 'حشو',
            payment: pay,
          ),
        ).entryId;

    addAnalysisToVisit(repos,
        analysisOf: visit('أحمد', 'الصفوة', 'كاش'),
        patientName: 'أحمد',
        clinic: 'الصفوة',
        date: today,
        cfg: config(),
        payment: 'كاش');
    addAnalysisToVisit(repos,
        analysisOf: visit('سارة', 'النخبة', 'تحويل'),
        patientName: 'سارة',
        clinic: 'النخبة',
        date: today,
        cfg: config(),
        payment: 'تحويل');
    // تحليل شهرٍ سابق — خارج نطاق «الشهر الجاري» فلا يظهر في البطاقة.
    repos.records.upsertLocal({
      'id': 'anal-old-m149',
      'date': addMonths(today, -2),
      'name': 'خالد',
      'patient_name': 'خالد',
      'amount': 75,
      'clinic': 'الصفوة',
      'clinic_id': 'الصفوة',
      'service': 'تحاليل',
      'payment': 'كاش',
      'isAnalysis': 1,
      'isDebt': 0,
      'isPros': 0,
      'isDebtPayment': 0,
      'analysisName': kTriAnalysesName,
      'analysisOf': 'x',
      '_t': 'r',
    });
    c.dispose();
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool dense,
    Size size = const Size(1100, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: const Color(0xFFF3F0E8),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: AnalysesRegistryCard(dense: dense),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('البطاقة — الوظائف (تعمل دائماً)', () {
    testWidgets('تعرض تحاليل الشهر الجاري وحدها وتذييلَ الإجمالي', (t) async {
      seed();
      await pumpCard(t, dense: false);
      expect(find.byKey(const Key('anal-reg-card')), findsOneWidget);
      // صفّا الشهر الجاري ظاهران والقديم غائب.
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('سارة'), findsOneWidget);
      // م154 — السجل أرشيف كامل: القديم يظهر أيضاً، والتذييل شهري فقط.
      expect(find.text('خالد'), findsOneWidget);
      // التذييل: 50 + 50 = 100.
      final total = t.widget<Text>(find.byKey(const Key('anal-reg-total')));
      expect(total.data, contains('100'));
    });

    testWidgets('فلتر العيادة يقصر الصفوف ويحدّث الإجمالي', (t) async {
      seed();
      await pumpCard(t, dense: false);
      await t.tap(find.byKey(const Key('anal-reg-clinic')));
      await t.pumpAndSettle();
      await t.tap(find.text('النخبة').last);
      await t.pumpAndSettle();
      expect(find.text('سارة'), findsOneWidget);
      expect(find.text('أحمد'), findsNothing);
      final total = t.widget<Text>(find.byKey(const Key('anal-reg-total')));
      expect(total.data, contains('50'));
    });

    testWidgets('فلتر الطريقة والبحث المطبَّع يتركبان', (t) async {
      seed();
      await pumpCard(t, dense: false);
      // كاش فقط ⇒ أحمد وحده.
      await t.tap(find.descendant(
          of: find.byKey(const Key('anal-reg-filter')),
          matching: find.text('كاش')));
      await t.pumpAndSettle();
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('سارة'), findsNothing);
      // بحث «ساره» (تاء مربوطة بهاء) مع «الكل» ⇒ سارة بالتطبيع العربي.
      await t.tap(find.descendant(
          of: find.byKey(const Key('anal-reg-filter')),
          matching: find.text('الكل')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('anal-reg-search')), 'ساره');
      await t.pumpAndSettle();
      expect(find.text('سارة'), findsOneWidget);
      expect(find.text('أحمد'), findsNothing);
    });

    testWidgets('حذف بندٍ من البطاقة يزيله من القاعدة', (t) async {
      seed();
      await pumpCard(t, dense: false);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      final target = c
          .read(reposProvider)
          .records
          .getAll()
          .firstWhere((r) =>
              jsTruthy(r['isAnalysis']) && r['patient_name'] == 'أحمد');
      // م187 — التعديل والحذف صارا في قائمة الصف المضغوطة (⋮) بهوية
      // جدول الحركات: نفتحها ثم نختار «حذف» — نفس المفاتيح القائمة.
      await t.tap(find.byKey(Key('anal-reg-menu-${target['id']}')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('anal-reg-del-${target['id']}')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('anal-reg-del-confirm')));
      await t.pumpAndSettle();
      expect(find.text('أحمد'), findsNothing);
      final left = c
          .read(reposProvider)
          .records
          .getAll()
          .where((r) =>
              jsTruthy(r['isAnalysis']) && r['patient_name'] == 'أحمد');
      expect(left, isEmpty, reason: 'الصف حُذف من القاعدة (records.delete)');
    });

    testWidgets('النموذج المكثف (الهاتف) يعرض الصفوف والفلاتر نفسها',
        (t) async {
      seed();
      await pumpCard(t, dense: true, size: const Size(420, 900));
      expect(find.byKey(const Key('anal-reg-card')), findsOneWidget);
      expect(find.byKey(const Key('anal-reg-search')), findsOneWidget);
      expect(find.byKey(const Key('anal-reg-filter')), findsOneWidget);
      expect(find.byKey(const Key('anal-reg-clinic')), findsOneWidget);
      expect(find.text('أحمد'), findsOneWidget);
      expect(find.text('سارة'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('اللقطات الذهبية (GOLDENS=1 محلياً)', () {
    testWidgets('نموذج سطح المكتب — جدول كامل', (t) async {
      seed();
      await pumpCard(t, dense: false);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/m149_registry_desktop.png'),
      );
    }, skip: !_goldens);

    testWidgets('نموذج الهاتف — قائمة مكثفة', (t) async {
      seed();
      await pumpCard(t, dense: true, size: const Size(420, 900));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/m149_registry_mobile.png'),
      );
    }, skip: !_goldens);

    testWidgets('حوار حجب قاعدة التكرار — نص المواصفة', (t) async {
      t.view.physicalSize = const Size(560, 420);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (ctx) => Scaffold(
              backgroundColor: const Color(0xFFF3F0E8),
              body: Center(
                child: FilledButton(
                  onPressed: () => showTriRepeatBlockedDialog(
                    ctx,
                    'لا يمكن إجراء تحليل ثلاثي جديد لهذا المريض. '
                    'آخر تحليل تم بتاريخ 2026-05-20. '
                    'يجب مرور 6 أشهر على الأقل.',
                  ),
                  child: const Text('فتح'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('فتح'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/m149_repeat_blocked_dialog.png'),
      );
    }, skip: !_goldens);
  });
}
