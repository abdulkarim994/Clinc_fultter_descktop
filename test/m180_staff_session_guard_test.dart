/// اختبارات م180/أ — حارسا جلسة الموظفين (علة الكمبيوتر التي أبلغ عنها
/// المالك: أوقف النظام من الهاتف واستمر الكمبيوتر يعمل به بجلسةٍ عالقة،
/// وظهرت في الإعدادات بطاقتا التفعيل والإدارة **معاً**):
/// ١) جلسة إدارة عالقة + صفر مستخدمين (إيقافٌ وصل بالمزامنة) ⇒ تُصفَّر
///    تلقائياً ويعود الجهاز للوضع الفردي.
/// ٢) النظام مفعّل وجلستي لمستخدمٍ حُذف من جهاز آخر ⇒ خروج إجباري
///    لشاشة الدخول.
/// ٣) الإعدادات: يستحيل ظهور بطاقتَي «تفعيل النظام» و«إدارة المستخدمين»
///    معاً (شرطا hasUsers متنافيان).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/staff/staff_session.dart'
    show applyStaffSession, currentStaffProvider;
import 'package:dental_clinic_flutter/features/staff/staff_store.dart'
    show StaffStore;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m180a_'));
  tearDown(() {
    applyStaffSession(null);
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> config() => {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'services': ['حشو'],
        'payments': ['كاش'],
      };

  /// جلسة إدارة «عالقة» — كما تبقى في ذاكرة جهازٍ بعد إيقاف النظام
  /// من جهاز آخر.
  const staleAdmin = <String, Object?>{
    'id': 'ghost-admin',
    'username': 'boss',
    'name': 'الإدارة القديمة',
    'role': 'admin',
    'perms': <String, Object?>{},
  };

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    Map<String, Object?>? session,
    void Function(ProviderContainer c)? seed,
  }) async {
    final c = ProviderContainer(overrides: [
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', config());
    seed?.call(c);
    c.dispose();
    if (session != null) applyStaffSession(session);
    late final ProviderContainer live;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbDirProvider.overrideWithValue(tmp.path),
          if (session != null)
            currentStaffProvider.overrideWith((ref) => session),
        ],
        child: const DentalApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    live = ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );
    return live;
  }

  testWidgets(
      'جلسة إدارة عالقة + صفر مستخدمين ⇒ تُصفَّر ويُفتح الوضع الفردي',
      (tester) async {
    final c = await boot(tester, session: staleAdmin);
    // إطار إضافي: التصفير post-frame.
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.read(currentStaffProvider), isNull,
        reason: 'الجلسة العالقة يجب أن تُصفَّر تلقائياً');
    // الصدفة مفتوحة (وضع فردي) لا شاشة دخول.
    expect(find.text('الرئيسية'), findsWidgets);
  });

  testWidgets('النظام مفعّل وجلستي لمستخدم محذوف ⇒ شاشة الدخول إجبارياً',
      (tester) async {
    // النظام مفعّل بمستخدمٍ حقيقي واحد (غير صاحب الجلسة العالقة).
    await boot(
      tester,
      session: staleAdmin, // ghost-admin ليس في المخزن
      seed: (c) {
        final s = StaffStore(c.read(reposProvider).settings);
        final id = s.upsert(username: 'doc', name: 'طبيب', role: 'admin');
        s.setPassword(id, 'secret12');
      },
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // شاشة دخول الموظفين ظاهرة (حقل اسم الدخول) لا الصدفة.
    expect(find.byKey(const Key('login-user')), findsOneWidget,
        reason: 'مستخدم الجلسة حُذف ⇒ خروج إجباري');
  });

  testWidgets(
      'الإعدادات: جلسة إدارة عالقة بلا مستخدمين ⇒ بطاقة التفعيل وحدها '
      '(لا بطاقة إدارة معها)', (tester) async {
    await boot(tester, session: staleAdmin);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('الإعدادات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final scroll = find
        .byWidgetPredicate((w) =>
            w is Scrollable && w.axisDirection == AxisDirection.down)
        .last;
    await tester.scrollUntilVisible(
        find.byKey(const Key('group-staff')), 300, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-staff')),
        warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // بطاقة التفعيل ظاهرة، وبطاقتا الإدارة/الإيقاف غائبتان تماماً.
    expect(find.byKey(const Key('enable-staff-system')), findsOneWidget);
    expect(find.byKey(const Key('open-staff-users')), findsNothing);
    expect(find.byKey(const Key('disable-staff-system')), findsNothing,
        reason: 'علة «الخيارين معاً» — الشرطان صارا متنافيين');
  });
}
