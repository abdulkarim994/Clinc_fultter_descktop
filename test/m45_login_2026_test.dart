/// اختبار م45 — شاشة الدخول بعائلة البوابة (v21):
///   • بطاقة **بيضاء** بنمط شاشة الإعداد (قرار مالك — الخلفية كما هي).
///   • شعار بأيقونة السن المخططة، زر دخول أخضر متدرج بمفتاحه.
///   • الترتيب الحرفي للحقول (0 بريد، 1 كلمة المرور) والنصوص كما هي.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m45_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('عناصر الهوية 2026 والترتيب الحرفي للحقول',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [dbDirProvider.overrideWithValue(tmp.path)],
      child: const DentalApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // م45/v21 — البطاقة البيضاء بعائلة البوابة (قرار مالك).
    expect(find.byKey(const Key('login-glass-card')), findsOneWidget);
    final card = tester.widget<Container>(
        find.byKey(const Key('login-glass-card')));
    expect((card.decoration as BoxDecoration).color, Colors.white,
        reason: 'بطاقة بيضاء كنمط شاشة الإعداد');

    // م180/د — الشعار صار أيقونة DENTSHINE الرسمية بدل أيقونة التبويب.
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/icon/icon-512.png'),
        findsOneWidget);

    // زر الدخول الذهبي بمفتاحه + النصوص الحرفية.
    expect(find.byKey(const Key('login-btn')), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsWidgets);
    // م180/د — «إنشاء حساب جديد» صار تبويباً في المبدّل المنزلق.
    expect(find.byKey(const Key('auth-switcher')), findsOneWidget);
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    // م182 — الاسم صار داخل لوحة الشعار نفسها (لا سطر نصّي تحتها)؛
    // الجملة التعريفية وحدها هي النصّ الباقي تحت الشعار.
    expect(find.text('DENTSHINE'), findsNothing);
    expect(find.text('لعيادة أكثر ذكاءً وتنظيمًا'), findsOneWidget);

    // الترتيب الحرفي: 0 بريد، 1 كلمة مرور (تكتب وتقرأ بالمواضع).
    await tester.enterText(
        find.byType(TextField).at(0), 'doc@clinic.ly');
    await tester.enterText(find.byType(TextField).at(1), 'secret12');
    expect(find.text('doc@clinic.ly'), findsOneWidget);

    // م180/د — وضع الدخول يعرض حقليه وحدهما (الإنشاء خلف تبويبه).
    expect(find.byType(TextField), findsNWidgets(2));
    // «نسيت كلمة المرور؟» متاح في وضع الدخول.
    expect(find.byKey(const Key('forgot-password')), findsOneWidget);

    // التبديل لتبويب «إنشاء حساب جديد»: م186 — نفس صندوقَي البريد
    // وكلمة المرور (المتحكمان مشتركان: النص المكتوب يبقى) + حقل
    // «تأكيد كلمة المرور» الثالث، وبلا «نسيت» ولا Google.
    await tester.ensureVisible(find.byKey(const Key('auth-tab-register')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auth-tab-register')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byKey(const Key('reg-confirm')), findsOneWidget);
    expect(find.text('doc@clinic.ly'), findsOneWidget,
        reason: 'م186: البريد المكتوب يبقى عند التبديل — نفس الصندوق');
    expect(find.byKey(const Key('forgot-password')), findsNothing);
    expect(find.byKey(const Key('google-signin-btn')), findsNothing,
        reason: 'م186: Google مسار دخولٍ حصراً — لا يظهر في الإنشاء');
    await tester.ensureVisible(find.byKey(const Key('register-btn')));
    await tester.pump();
    expect(find.byKey(const Key('register-btn')), findsOneWidget);
    expect(find.text('إنشاء الحساب'), findsOneWidget);
  });
}
