/// اختبار م45 — شاشة الدخول بعائلة البوابة (v21):
///   • بطاقة **بيضاء** بنمط شاشة الإعداد (قرار مالك — الخلفية كما هي).
///   • شعار بأيقونة السن المخططة، زر دخول أخضر متدرج بمفتاحه.
///   • الترتيب الحرفي للحقول (0 بريد، 1 كلمة المرور) والنصوص كما هي.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/features/shell/tab_icons.dart';
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

    // الشعار بأيقونة السن المخططة.
    expect(
        find.byWidgetPredicate(
            (w) => w is TabIcon && w.id == 'labs'),
        findsOneWidget);

    // زر الدخول الذهبي بمفتاحه + النصوص الحرفية.
    expect(find.byKey(const Key('login-btn')), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    expect(find.text('طب الأسنان الرقمي'), findsOneWidget);

    // الترتيب الحرفي: 0 بريد، 1 كلمة مرور (تكتب وتقرأ بالمواضع).
    await tester.enterText(
        find.byType(TextField).at(0), 'doc@clinic.ly');
    await tester.enterText(find.byType(TextField).at(1), 'secret12');
    expect(find.text('doc@clinic.ly'), findsOneWidget);

    // فتح قسم إنشاء الحساب: الحقلان 2 و3 وزر «إنشاء الحساب».
    // م88 — أُضيف زرّ «المتابعة باستخدام Google» فوقه، والبطاقة قابلة
    // للتمرير (SingleChildScrollView)، فيُمرَّر إليه قبل النقر في شاشة
    // الاختبار الصغيرة. لا يغيّر ما يُفحَص: الحقول الأربعة وترتيبها.
    await tester.ensureVisible(find.text('إنشاء حساب جديد').first);
    await tester.pump();
    await tester.tap(find.text('إنشاء حساب جديد').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.byKey(const Key('register-btn')), findsOneWidget);
    expect(find.text('إنشاء الحساب'), findsOneWidget);
  });
}
