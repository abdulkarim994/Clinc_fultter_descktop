/// م173 — شاشة مراجعة لقطات الكاميرا الداخلية: الكل محددٌ افتراضياً،
/// النقر يبدل تحديد اللقطة، «تحديد/إلغاء الكل»، وزر التأكيد يعيد
/// **المحدَّد فقط** (الباقي يُحذف)، والرجوع بلا نتيجة (يعود للتصوير).
library;

import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:dental_clinic_flutter/features/xrays/xray_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG شفاف 1×1 (لا نحتاج صورة حقيقية — Image.memory يفكه بلا شبكة).
final Uint8List kPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOoaOr5'
  'DwAFggKGrvU4EwAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<(String, Uint8List)> shots(int n) =>
      [for (var i = 0; i < n; i++) ('shot_$i.jpg', kPng)];

  /// يضخ مضيفاً ويفتح شاشة المراجعة، ويعيد مستقبل نتيجتها (نتيجة pop).
  Future<Future<List<(String, Uint8List)>?>> openReview(
      WidgetTester t, int n) async {
    late Future<List<(String, Uint8List)>?> result;
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(builder: (ctx) {
          return Center(
            child: ElevatedButton(
              key: const Key('open-review'),
              onPressed: () {
                result = Navigator.of(ctx).push<List<(String, Uint8List)>>(
                  MaterialPageRoute(
                    builder: (_) => XrayReviewScreen(
                        patientName: 'سالم', shots: shots(n)),
                  ),
                );
              },
              child: const Text('فتح'),
            ),
          );
        }),
      ),
    ));
    await t.tap(find.byKey(const Key('open-review')));
    await t.pumpAndSettle();
    return result;
  }

  testWidgets('الكل محددٌ افتراضياً والتأكيد يعيد الجميع', (t) async {
    final result = await openReview(t, 3);
    expect(find.byKey(const Key('xray-rev-grid')), findsOneWidget);
    expect(find.textContaining('رفع المحدد (3)'), findsOneWidget);
    await t.tap(find.byKey(const Key('xray-rev-ok')));
    await t.pumpAndSettle();
    final picked = await result;
    expect(picked, isNotNull);
    expect(picked!.length, 3);
    expect(t.takeException(), isNull);
  });

  testWidgets('إلغاء تحديد لقطةٍ يستثنيها — يُعاد المحدد فقط', (t) async {
    final result = await openReview(t, 3);
    // ألغِ تحديد الثانية (فهرس 1).
    await t.tap(find.byKey(const Key('xray-rev-item-1')));
    await t.pumpAndSettle();
    expect(find.textContaining('رفع المحدد (2)'), findsOneWidget);
    await t.tap(find.byKey(const Key('xray-rev-ok')));
    await t.pumpAndSettle();
    final picked = await result;
    expect([for (final s in picked!) s.$1], ['shot_0.jpg', 'shot_2.jpg'],
        reason: 'الثانية حُذفت (غير محددة)');
    expect(t.takeException(), isNull);
  });

  testWidgets('«إلغاء الكل» يعطل التأكيد و«تحديد الكل» يعيده', (t) async {
    await openReview(t, 2);
    await t.tap(find.byKey(const Key('xray-rev-all')));
    await t.pumpAndSettle();
    expect(find.text('لا لقطات محددة'), findsOneWidget);
    final btn =
        t.widget<FilledButton>(find.byKey(const Key('xray-rev-ok')));
    expect(btn.onPressed, isNull, reason: 'صفر لقطات = زرٌّ معطل');
    await t.tap(find.byKey(const Key('xray-rev-all')));
    await t.pumpAndSettle();
    expect(find.textContaining('رفع المحدد (2)'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('«رجوع للتصوير» يعود بلا نتيجة (لا رفع ولا حذف)', (t) async {
    final result = await openReview(t, 2);
    await t.tap(find.byKey(const Key('xray-rev-back')));
    await t.pumpAndSettle();
    expect(await result, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('زر العين يكبّر اللقطة بملء الشاشة', (t) async {
    await openReview(t, 2);
    await t.tap(find.byKey(const Key('xray-rev-eye-0')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('xray-rev-zoomed-0')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
