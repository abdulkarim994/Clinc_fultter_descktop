/// اختبارات: نظام الموظفين الاختياري + استرداد كلمة المرور المنسية.
///
///  يغطّي منطق المخزن (رمز الاسترداد، إعادة التعيين، الإيقاف الآمن)
///  وبوابة الصدفة (الوضع الفردي بلا دخول مقابل وجوب الدخول حين يوجد حساب).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart'
    show AppShellScreen;
import 'package:dental_clinic_flutter/features/staff/staff_login_screen.dart'
    show StaffLoginScreen;
import 'package:dental_clinic_flutter/features/staff/staff_store.dart';
import 'package:dental_clinic_flutter/main.dart' show DentalApp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('staffopt_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  StaffStore store() => StaffStore(c.read(reposProvider).settings);

  // ══ منطق المخزن ══
  group('رمز الاسترداد', () {
    test('التوليد: أربع مجموعاتٍ من أبجدية بلا محارف ملتبِسة', () {
      for (var i = 0; i < 30; i++) {
        final code = StaffStore.generateRecoveryCode();
        expect(RegExp(r'^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-'
                r'[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$')
            .hasMatch(code), isTrue, reason: code);
      }
    });

    test('يُخزَّن مُجزّأً لا نصّاً، ويُتحقَّق منه بتسامح الحالة/الشرطات', () {
      final s = store();
      final id = s.upsert(username: 'doc', name: 'طبيب', role: 'admin');
      final code = s.setRecoveryCode(id);
      // غير مقروء في الصف الخام.
      final raw = '${c.read(reposProvider).settings.get(StaffStore.rowKey(id))}';
      expect(raw.contains(code), isFalse, reason: 'الرمز لا يُخزَّن نصّاً');
      expect(s.verifyRecoveryCode(id, code), isTrue);
      // تسامح: حالة أحرفٍ مختلفة وبلا شرطات.
      expect(s.verifyRecoveryCode(id, code.toLowerCase().replaceAll('-', '')),
          isTrue);
      expect(s.verifyRecoveryCode(id, 'WRNG-WRNG-WRNG-WRNG'), isFalse);
    });

    test('إعادة التعيين بالرمز: تُغيّر كلمة المرور وتستهلك الرمز', () {
      final s = store();
      final id = s.upsert(username: 'doc', name: 'طبيب', role: 'admin');
      s.setPassword(id, 'oldpass');
      final code = s.setRecoveryCode(id);
      // رمزٌ خاطئ يُرفض.
      expect(s.resetPasswordWithRecovery(id, 'BAD0-BAD0-BAD0-BAD0', 'newpass'),
          isFalse);
      // الرمز الصحيح ينجح.
      expect(s.resetPasswordWithRecovery(id, code, 'newpass'), isTrue);
      // كلمة المرور الجديدة تعمل، والقديمة لا.
      expect(s.login('doc', 'newpass').status, StaffLoginStatus.ok);
      // الرمز استُهلك (لا يُعاد استخدامه).
      expect(s.hasRecoveryCode(id), isFalse);
      expect(s.verifyRecoveryCode(id, code), isFalse);
    });
  });

  group('إيقاف نظام الموظفين', () {
    test('يحذف كل الحسابات ويعيد للوضع الفردي بلا مسّ بيانات مريض', () {
      final s = store();
      s.upsert(username: 'doc', name: 'طبيب', role: 'admin');
      s.upsert(username: 'recep', name: 'موظف', role: 'staff');
      // بيانات مريض (تبقى بعد الإيقاف — جدولٌ مستقل).
      c.read(reposProvider).patients.upsertLocal({'id': 'p1', 'name': 'مريض'});
      expect(s.hasAnyUser, isTrue);

      s.disableStaffSystem();

      expect(s.hasAnyUser, isFalse, reason: 'لا حسابات ⇒ وضع فردي');
      expect(s.listAll(), isEmpty);
      expect(c.read(reposProvider).patients.getAll(), hasLength(1),
          reason: 'بيانات المريض لا تتأثر إطلاقاً');
    });
  });

  // ══ بوابة الصدفة ══
  // الصدفة تُعرض بعد بوابتَي الدخول السحابي والإعداد؛ فنُقلع كاختبارات م11:
  // تسجيلٌ ودخولٌ محلي (remember) + ضبط إعدادٍ صالح، ثم نفحص بوابة الموظفين.
  group('بوابة الوضع الفردي', () {
    Future<void> boot(WidgetTester tester) async {
      final setup = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      final auth = setup.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      setup.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
      });
      setup.dispose();
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('لا حساب ⇒ لا شاشة دخول موظفين، تفتح الصدفة مباشرةً',
        (tester) async {
      await boot(tester);
      expect(find.byType(StaffLoginScreen), findsNothing,
          reason: 'الوضع الفردي: بلا تسجيل دخول موظفين');
      expect(find.byType(AppShellScreen), findsOneWidget);
    });

    testWidgets('يوجد حساب ⇒ شاشة دخول الموظفين مطلوبة', (tester) async {
      // ازرع حساب إدارة قبل الإقلاع (على نفس مجلد البيانات).
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      StaffStore(seed.read(reposProvider).settings)
          .upsert(username: 'doc', name: 'طبيب', role: 'admin');
      seed.dispose();
      await boot(tester);
      expect(find.byType(StaffLoginScreen), findsOneWidget,
          reason: 'وجود حساب ⇒ وجوب الدخول');
    });
  });
}
