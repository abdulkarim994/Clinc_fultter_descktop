/// م173/د — اختبار هندسي لتخطيط شاشة الكاميرا (علاج الشريط الصغير):
/// الحاوية كانت تنكمش لارتفاع شريط الأزرار (Stack مرن بابنٍ وحيد غير
/// مثبت) فتتبعها المعاينة Positioned.fill — لقطات المالك 2171→2173.
/// يقيس الاختبار بمقاس هاتفٍ حقيقي أن مستطيل المعاينة يملأ كامل جسم
/// الشاشة (من أسفل الترويسة حتى أسفل الشاشة وبكامل العرض — لا مساحة
/// سوداء)، وأن زر الالتقاط بأسفل الشاشة فوق المعاينة.
library;

import 'package:dental_clinic_flutter/features/xrays/xray_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester t, Size logical) async {
    t.view.physicalSize = logical;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: XrayCameraScreen(
            patientName: 'سالم',
            // بديل المعاينة الهندسي — لا عتاد كاميرا في الاختبارات.
            debugPreview: Container(
              key: const Key('fake-preview'),
              color: const Color(0xFF222222),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('المعاينة تملأ كامل الجسم — لا شريط أسود (مقاس هاتف طويل)',
      (t) async {
    // مقاس منطقي بنسبة جهاز المالك (1080×2400 ⇒ 20:9).
    await boot(t, const Size(400, 889));

    final screen = t.getRect(find.byType(Scaffold));
    final appBar = t.getRect(find.byType(AppBar));
    final preview = t.getRect(find.byKey(const Key('fake-preview')));

    // المعاينة تبدأ تحت الترويسة مباشرةً وتنتهي بأسفل الشاشة تماماً
    // وبكامل العرض — أي لا مساحة سوداء غير مقصودة إطلاقاً.
    expect(preview.top, moreOrLessEquals(appBar.bottom, epsilon: .5));
    expect(preview.bottom, moreOrLessEquals(screen.bottom, epsilon: .5));
    expect(preview.left, moreOrLessEquals(screen.left, epsilon: .5));
    expect(preview.right, moreOrLessEquals(screen.right, epsilon: .5));

    // ارتفاع المعاينة = كامل الجسم (وليس ~180 نقطة كالعطل السابق).
    expect(preview.height, greaterThan((screen.height - appBar.bottom) * .99));

    // زر الالتقاط موجود بأسفل الشاشة وفوق المعاينة (داخل مستطيلها).
    final shutter = t.getCenter(find.byKey(const Key('xray-cam-shutter')));
    expect(shutter.dy, greaterThan(screen.bottom - 140),
        reason: 'شريط الأزرار مثبت بأسفل الشاشة');
    expect(preview.contains(shutter), isTrue,
        reason: 'الأزرار طبقة فوق المعاينة');
    expect(t.takeException(), isNull);
  });

  testWidgets('المقاسات الأخرى: عريض وقصير — الملء كامل أيضاً', (t) async {
    for (final s in const [Size(360, 640), Size(500, 1100)]) {
      await boot(t, s);
      final screen = t.getRect(find.byType(Scaffold));
      final appBar = t.getRect(find.byType(AppBar));
      final preview = t.getRect(find.byKey(const Key('fake-preview')));
      expect(preview.top, moreOrLessEquals(appBar.bottom, epsilon: .5));
      expect(preview.bottom, moreOrLessEquals(screen.bottom, epsilon: .5));
      expect(preview.width, moreOrLessEquals(screen.width, epsilon: .5));
    }
    expect(t.takeException(), isNull);
  });
}
