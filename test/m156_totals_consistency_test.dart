/// م156 — اتساق جدول «إجمالي الخزينة»: كل صفٍّ يجمع عمودَيه حرفياً
/// (كاش + تحويل = الإجمالي)، والتركيبات المدفوعة صفٌّ مستقل موزعٌ
/// بطريقة الدفع بنفس مقادير prosTotalPaid (بلاغ المالك:
/// 90,715 ≠ 23,200 + 40,215 — الفرق كان مدفوعات التركيبات).
library;

import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart';
import 'package:dental_clinic_flutter/features/finance/treasury_tables.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م156 — prosPaidByMethod', () {
    test('التوزيع كاش/تحويل يطابق prosTotalPaid دائماً', () {
      final cp = <Map<String, Object?>>[
        // غير دين — تدخل بكامل قيمتها بطريقتها.
        {'total': 1000, 'payment': 'كاش'},
        {'total': 500, 'payment': 'تحويل'},
        // دين — لا تدخل ككل؛ دفعاتها في pdPays.
        {'total': 700, 'isDebt': 1, 'payment': 'كاش'},
      ];
      final pd = <Map<String, Object?>>[
        {'amount': 300, 'payment': 'تحويل'},
        // _fullAmount يتقدم على amount (اصطلاح دفعات ديون التركيبات).
        {'_fullAmount': 200, 'amount': 120, 'payment': 'كاش'},
      ];
      final m = prosPaidByMethod(cp, pd);
      expect(m.cash, 1200); // 1000 + 200
      expect(m.xfer, 800); // 500 + 300
      expect(m.cash + m.xfer, prosTotalPaid(cp, pd),
          reason: 'cash + xfer == المدفوع الكلي حرفياً');
    });

    test('طريقة غير معروفة تُحسب تحويلاً (اصطلاح المستودع)', () {
      final m = prosPaidByMethod(
        [
          {'total': 100, 'payment': ''},
          {'total': 50}, // بلا حقل payment إطلاقاً
        ],
        const [],
      );
      expect(m.cash, 0);
      expect(m.xfer, 150);
    });
  });

  group('م156 — جدول الإجمالي', () {
    testWidgets('كل صف يجمع عمودَيه: العيادات والتركيبات والصافي',
        (t) async {
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(children: const [
                TreasuryTotalsTable(
                  month: '2026-08',
                  clinicsCash: 100,
                  clinicsXfer: 200,
                  prosCash: 40,
                  prosXfer: 60,
                  analCash: 7,
                  analXfer: 3,
                  expCash: 5,
                  expXfer: 15,
                  expTotal: 20,
                ),
              ]),
            ),
          ),
        ),
      ));
      await t.pump();

      // صف التركيبات المستقل حاضر بمفتاحه.
      expect(find.byKey(const Key('tr2-tot-pros')), findsOneWidget);
      // إجمالي العيادات = 100 + 200 (لا يتضمن التركيبات بعد الآن).
      expect(
        find.descendant(
            of: find.byKey(const Key('tr2-tot-clinics')),
            matching: find.text('300')),
        findsOneWidget,
        reason: 'إجمالي العيادات يساوي كاشها + تحويلها حرفياً',
      );
      // إجمالي التركيبات = 40 + 60.
      expect(
        find.descendant(
            of: find.byKey(const Key('tr2-tot-pros')),
            matching: find.text('100')),
        findsOneWidget,
      );
      // الصافي: كاش 100+40+7-5=142 • تحويل 200+60+3-15=248 • إجمالي 390.
      final net = find.byKey(const Key('tr2-tot-net'));
      expect(find.descendant(of: net, matching: find.text('142')),
          findsOneWidget);
      expect(find.descendant(of: net, matching: find.text('248')),
          findsOneWidget);
      expect(find.descendant(of: net, matching: find.text('390')),
          findsOneWidget,
          reason: 'إجمالي الصافي = مجموع عمودَيه (اتساق م156)');
    });
  });
}
