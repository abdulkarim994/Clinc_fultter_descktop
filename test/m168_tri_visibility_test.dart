// م168 — اختبارات «الاختفاء الشامل» للتحاليل الثلاثية عند الإيقاف:
// القاعدة المركزية في analyses3.dart (تاريخ الإيقاف disabledOn ودوال
// الرؤية) + جدول إجمالي الخزينة بمعامل showAnal. نقيةٌ بلا قاعدة بيانات.
//
// الحالات المطلوبة (مواصفة المالك):
//   أ) القيمة 0/الغياب ⇒ الميزة مختفية من كل مكان (الافتراضي OFF).
//   ب) التفعيل من الإعدادات ⇒ تعود للظهور في جميع الأماكن.
//   ج) الإيقاف مجدداً ⇒ تختفي بالكامل (ويُختم تاريخ الإيقاف).
//   د) البيانات التاريخية (≤ تاريخ الإيقاف) تبقى ظاهرةً محفوظة، وما بعده
//      يختفي — بلا حذفٍ لأي بيانات.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dental_clinic_flutter/features/finance/treasury_tables.dart'
    show TreasuryTotalsTable;
import 'package:dental_clinic_flutter/features/settings/analyses3.dart'
    show
        kTriAnalysesCfgKey,
        triAnalysesEnabled,
        triCfgWrite,
        triDisabledOn,
        triHasVisibleHistory,
        triVisibleInMonth,
        triVisibleOnDate;
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  // ── أ) الافتراضي OFF: الغياب/القيمة 0 = اختفاء كلي ────────────────────────

  group('م168/أ — الافتراضي OFF يخفي كل شيء', () {
    test('غياب المفتاح كلياً ⇒ لا تفعيل ولا رؤية بأي تاريخ', () {
      const cfg = <String, Object?>{};
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triDisabledOn(cfg), '');
      expect(triVisibleOnDate(cfg, '2026-08-12'), isFalse);
      expect(triVisibleInMonth(cfg, '2026-08'), isFalse);
      expect(triHasVisibleHistory(cfg, const []), isFalse);
    });

    test('enabled: false (القيمة 0 سلوكاً) بلا تاريخ إيقاف ⇒ اختفاء كلي', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 100, 'enabled': false},
      };
      expect(triAnalysesEnabled(cfg), isFalse);
      expect(triVisibleOnDate(cfg, '2020-01-01'), isFalse,
          reason: 'بلا تاريخ إيقاف مسجل لا يوجد «تاريخٌ» يُعرض');
      // حتى مع صفوف تحاليل قديمة: بلا تاريخ إيقاف ⇒ لا مدخل تاريخ.
      expect(
        triHasVisibleHistory(cfg, const [
          {'isAnalysis': 1, 'date': '2020-01-01'},
        ]),
        isFalse,
      );
    });
  });

  // ── ب/ج) التفعيل يعيد الظهور والإيقاف يختم التاريخ ويخفي ─────────────────

  group('م168/ب+ج — دورة التفعيل والإيقاف عبر triCfgWrite', () {
    test('التفعيل ⇒ رؤية شاملة بلا شرط تاريخ', () {
      const cfg = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 50, 'enabled': true},
      };
      expect(triAnalysesEnabled(cfg), isTrue);
      expect(triVisibleOnDate(cfg, '2099-12-31'), isTrue);
      expect(triVisibleInMonth(cfg, '2099-12'), isTrue);
      expect(triHasVisibleHistory(cfg, const []), isTrue);
    });

    test('الانتقال مفعّل→متوقف يختم disabledOn بتاريخ اليوم', () {
      const before = <String, Object?>{
        kTriAnalysesCfgKey: {'price': 50, 'enabled': true, 'repeatMonths': 6},
      };
      final tri = triCfgWrite(before,
          price: 50, enabled: false, repeatMonths: 6, today: '2026-08-12');
      expect(tri['enabled'], isFalse);
      expect(tri['disabledOn'], '2026-08-12');
      // السعر والمدة محفوظان — لا فقدان حقول عند الإيقاف.
      expect(tri['price'], 50);
      expect(tri['repeatMonths'], 6);
    });

    test('كتابة السعر/المدة أثناء الإيقاف تحافظ على disabledOn كما هو', () {
      const off = <String, Object?>{
        kTriAnalysesCfgKey: {
          'price': 50,
          'enabled': false,
          'repeatMonths': 6,
          'disabledOn': '2026-08-12',
        },
      };
      final tri = triCfgWrite(off,
          price: 75, enabled: false, repeatMonths: 3, today: '2026-09-01');
      expect(tri['disabledOn'], '2026-08-12',
          reason: 'لا يُعاد الختم إلا عند انتقالٍ مفعّل→متوقف حقيقي');
      expect(tri['price'], 75);
      expect(tri['repeatMonths'], 3);
    });

    test('إعادة التفعيل تمحو disabledOn (تعود كل الأماكن للعمل)', () {
      const off = <String, Object?>{
        kTriAnalysesCfgKey: {
          'price': 50,
          'enabled': false,
          'disabledOn': '2026-08-12',
        },
      };
      final tri = triCfgWrite(off,
          price: 50, enabled: true, repeatMonths: 6, today: '2026-09-01');
      expect(tri['enabled'], isTrue);
      expect(tri.containsKey('disabledOn'), isFalse);
      final cfg = <String, Object?>{kTriAnalysesCfgKey: tri};
      expect(triVisibleOnDate(cfg, '2099-01-01'), isTrue);
    });

    test('الإيقاف بلا تفعيلٍ سابق (لم تُفعَّل قط) لا يختلق تاريخاً', () {
      const never = <String, Object?>{};
      final tri = triCfgWrite(never,
          price: 0, enabled: false, repeatMonths: 6, today: '2026-08-12');
      expect(tri.containsKey('disabledOn'), isFalse,
          reason: 'الغياب الأصلي = OFF بلا تاريخ — اختفاءٌ كلي');
    });
  });

  // ── د) البيانات التاريخية تبقى ظاهرة حتى تاريخ الإيقاف ───────────────────

  group('م168/د — الرؤية التاريخية بعد الإيقاف (disabledOn: 2026-08-12)', () {
    const cfg = <String, Object?>{
      kTriAnalysesCfgKey: {
        'price': 50,
        'enabled': false,
        'disabledOn': '2026-08-12',
      },
    };

    test('التواريخ ≤ تاريخ الإيقاف ظاهرة وما بعده مخفي', () {
      expect(triVisibleOnDate(cfg, '2026-08-11'), isTrue);
      expect(triVisibleOnDate(cfg, '2026-08-12'), isTrue,
          reason: 'يوم الإيقاف آخر يومٍ تاريخي — ما سُجل صباحه يبقى ظاهراً');
      expect(triVisibleOnDate(cfg, '2026-08-13'), isFalse);
      expect(triVisibleOnDate(cfg, '2027-01-01'), isFalse);
    });

    test('الأشهر: شهر الإيقاف وما قبله ظاهرة والتالية مخفية', () {
      expect(triVisibleInMonth(cfg, '2026-07'), isTrue);
      expect(triVisibleInMonth(cfg, '2026-08'), isTrue);
      expect(triVisibleInMonth(cfg, '2026-09'), isFalse);
    });

    test('مدخل السجل: يظهر بوجود صفٍّ تاريخي ويختفي بدونه', () {
      // صف تحليل قديم (قبل الإيقاف) ⇒ التاريخ الظاهر موجود.
      expect(
        triHasVisibleHistory(cfg, const [
          {'isAnalysis': 1, 'date': '2026-08-10'},
        ]),
        isTrue,
      );
      // لا صفوف تحاليل إطلاقاً ⇒ لا مدخل فارغ.
      expect(triHasVisibleHistory(cfg, const []), isFalse);
      // صفوف غير تحاليل لا تُحتسب.
      expect(
        triHasVisibleHistory(cfg, const [
          {'isAnalysis': 0, 'date': '2026-08-10'},
        ]),
        isFalse,
      );
    });
  });

  // ── جدول إجمالي الخزينة: صف التحاليل يُزال كلياً بمعامل showAnal ──────────

  group('م168 — TreasuryTotalsTable بمعامل showAnal', () {
    Widget host({required bool showAnal}) => ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: TreasuryTotalsTable(
                  month: '2026-08',
                  clinicsCash: 100,
                  clinicsXfer: 50,
                  prosCash: 30,
                  prosXfer: 20,
                  analCash: 0,
                  analXfer: 0,
                  expCash: 10,
                  expXfer: 5,
                  expTotal: 15,
                  showAnal: showAnal,
                ),
              ),
            ),
          ),
        );

    testWidgets('showAnal:false ⇒ لا صف تحاليل ولا عنوانه ولا فراغ', (t) async {
      await t.pumpWidget(host(showAnal: false));
      await t.pump();
      expect(find.byKey(const Key('tr2-tot-anal')), findsNothing);
      expect(find.textContaining('التحاليل'), findsNothing);
      // بقية الصفوف كما هي — الصافي حاضرٌ بقيمته الصحيحة.
      expect(find.byKey(const Key('tr2-tot-clinics')), findsOneWidget);
      expect(find.byKey(const Key('tr2-tot-exp')), findsOneWidget);
      expect(find.byKey(const Key('tr2-tot-net')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('showAnal:true ⇒ الصف حاضر (السلوك القائم كما هو)', (t) async {
      await t.pumpWidget(host(showAnal: true));
      await t.pump();
      expect(find.byKey(const Key('tr2-tot-anal')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
