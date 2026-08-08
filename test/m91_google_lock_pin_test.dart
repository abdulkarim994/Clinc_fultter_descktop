/// اختبارات م91 — رمز قفل التطبيق: سدُّ فخّ «قفلٌ بلا مفتاح» لداخل Google.
///
///  الفخ الذي تحرسه (رصده المالك): داخلُ Google لا تمرّ كلمةُ مروره
///  بالتطبيق (جوهر OAuth) فلا يُخزَّن له مُتحقِّقُ قفلٍ — وكانت شاشة القفل
///  تعرض له «تسجيل الخروج» فقط: لا حقل، ولا حتى زرَّ البصمة لأن الزرّ نفسه
///  كان مشروطاً بوجود المُتحقِّق (بينما توثيق م88 يَعِد بعكس ذلك حرفياً)،
///  وقفلُ الإقلاع كان يتخطّى صامتاً رغم أن مفتاح الإعدادات يوحي بأنه يعمل.
///
///  الحل المُختبَر هنا: رمزُ قفلٍ رقمي محلي تحت نفس مفتاح المُتحقِّق بوسم
///  نوعٍ (idle_lock)، اقتراحُه فور الدخول (post_login_gate/pin_setup)،
///  بصمةٌ تعمل وحدها، قفلُ إقلاعٍ يشمل حالة البصمة-فقط، بندٌ وتنبيهٌ في
///  الإعدادات، وخنقُ محاولاتٍ على الغطاء — **ومسار كلمة المرور بلا أي
///  تغيير** (تحرسه أيضاً م86/م87/م88 كما هي).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/biometric_auth.dart';
import 'package:dental_clinic_flutter/features/auth/idle_lock.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart';
import 'package:dental_clinic_flutter/features/auth/oauth_signin.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/auth/pin_setup.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

/// مزوّد OAuth مزيّف — نفس نمط م88.
class _FakeOAuth implements OAuthSignIn {
  _FakeOAuth(this.result);
  final OAuthResult result;
  @override
  Future<OAuthResult> signInWithGoogle() async => result;
}

/// بصمة مزيّفة — نفس نمط م87.
class _FakeBiometric implements BiometricAuth {
  _FakeBiometric({this.available = true, this.willSucceed = true});
  bool available;
  bool willSucceed;
  int authCalls = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    authCalls++;
    return willSucceed;
  }
}

const _googleUser = OAuthResult(
  uid: 'google-uid-1',
  email: 'dr.ahmad@gmail.com',
  displayName: 'د. أحمد',
);

/// يبذر «جلسةَ Google مستعادة» مكتملةَ الإعداد: صفُّ جلسةٍ في metadata
/// (ما يستعيده الجذر عند الإقلاع البارد) بلا أي مُتحقِّق — تماماً كجهازٍ
/// دخل بحساب Google ثم أُغلق تطبيقه. الخيارات تبذر رمزاً/بصمة فوق ذلك.
void _seedGoogleSession(
  Directory tmp, {
  String? pin,
  bool? biometric,
  bool? lockOnStart,
}) {
  final c = ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );
  final db = c.read(localDbProvider);
  db.setOwnerUid(_googleUser.uid);
  db.execute(
    'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
    "VALUES ('local_auth_session', ?, datetime('now'))",
    [
      jsonEncode({'uid': _googleUser.uid, 'email': _googleUser.email}),
    ],
  );
  c.read(reposProvider).settings.set('app.config', {
    'centerName': 'مركز الاختبار',
    'clinics': ['العيادة أ'],
  });
  markSetupComplete(db, _googleUser.uid);
  if (pin != null) storeLockPin(db, pin);
  if (biometric != null) setBiometricEnabled(db, biometric);
  if (lockOnStart != null) setLockOnStart(db, lockOnStart);
  c.dispose();
}

/// يبذر حساب بريد+كلمة مرور مكتمل الإعداد عبر مسار الدخول الحقيقي
/// (يخزّن المُتحقِّق بوسم password) — نفس نمط م86 حرفياً.
/// م97 — القفل معطَّل افتراضاً؛ [lockOnStart] يفعّله صراحةً لمن يختبر القفل.
Future<void> _seedPasswordSession(
  Directory tmp, {
  bool lockOnStart = false,
}) async {
  final c = ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );
  await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
  await c.read(authProvider.notifier).login('doc@clinic.ly', 'secret12', true);
  c.read(reposProvider).settings.set('app.config', {
    'centerName': 'مركز الاختبار',
    'clinics': ['العيادة أ'],
  });
  markSetupComplete(c.read(localDbProvider), 'doc@clinic.ly');
  if (lockOnStart) setLockOnStart(c.read(localDbProvider), true);
  c.dispose();
}

Future<void> _pumpApp(
  WidgetTester tester,
  Directory tmp, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
        ...overrides,
      ],
      child: const DentalApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(DentalApp)),
      listen: false,
    );

void main() {
  group('م91/أ — الرمز في طبقة التخزين', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m91a_');
      c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('يُخزَّن بوسم pin ويُفتَح به — والأرقام العربية نفس الرمز', () {
      final db = c.read(localDbProvider);
      expect(hasLockVerifier(db), isFalse, reason: 'م91: البداية بلا مُتحقِّق');
      storeLockPin(db, '2468');
      expect(hasLockVerifier(db), isTrue);
      expect(lockVerifierKind(db), 'pin');
      expect(verifyLock(db, '2468'), isTrue);
      expect(
        verifyLock(db, '٢٤٦٨'),
        isTrue,
        reason: 'م91: لوحة عربية-هندية ⇒ نفس الرمز بعد التطبيع',
      );
      expect(verifyLock(db, '1111'), isFalse);
      // ولو خُزّن أصلاً بأرقام عربية فالتطبيع في التخزين يسوّيهما.
      storeLockPin(db, '٧٧٥٥');
      expect(verifyLock(db, '7755'), isTrue);
    });

    test('مسار كلمة المرور يسم password — والغياب = password', () {
      final db = c.read(localDbProvider);
      expect(
        lockVerifierKind(db),
        'password',
        reason: 'م91: تنصيبات ما قبل الوسم كلها مسار كلمة مرور',
      );
      storeLockVerifier(db, 'secret12');
      expect(lockVerifierKind(db), 'password');
      expect(verifyLock(db, 'secret12'), isTrue);
      // دخولُ كلمة مرورٍ لاحقٌ يكتب فوق رمزٍ سابق — الكلمة هي المفتاح.
      storeLockPin(db, '2468');
      storeLockVerifier(db, 'secret12');
      expect(lockVerifierKind(db), 'password');
      expect(verifyLock(db, '2468'), isFalse);
    });

    test('المسح يزيل المُتحقِّق والوسم معاً', () {
      final db = c.read(localDbProvider);
      storeLockPin(db, '2468');
      clearLockVerifier(db);
      expect(hasLockVerifier(db), isFalse);
      expect(
        lockVerifierKind(db),
        'password',
        reason: 'م91: لا وسم يتيماً بعد المسح',
      );
    });

    test('صحة الرمز: قصير/غير رقمي/غير متطابق تُرفض بعربية صريحة', () {
      expect(validateLockPin('123', '123'), 'الرمز أربعة أرقام على الأقل');
      expect(validateLockPin('12ab', '12ab'), 'الرمز أرقامٌ فقط');
      expect(validateLockPin('1234', '1235'), 'الرمزان غير متطابقين');
      expect(validateLockPin('1234', '1234'), isNull);
      expect(
        validateLockPin('٢٤٦٨', '2468'),
        isNull,
        reason: 'م91: التأكيد بلوحة مختلفة يبقى مطابقاً',
      );
    });

    test('قواعد العرض الثلاث تميّز المسارين بلا علم مزوّد', () {
      final db = c.read(localDbProvider);
      // Google قبل التعيين: الاقتراح مستحق، البند ظاهر.
      expect(postLoginPinOfferDue(db, justLoggedIn: true), isTrue);
      expect(pinSettingsEntryVisible(db), isTrue);
      // م97 — القفل مطفأ افتراضاً ⇒ لا فخّ ⇒ لا تنبيه (بلا تفعيلٍ صريح).
      expect(
        lockTrapWarningDue(db),
        isFalse,
        reason: 'م97: مطفأ افتراضاً فلا فخّ',
      );
      // ولو فُعِّل القفل صراحةً بلا وسيلةٍ لظهر التنبيه (شبكة أمان)…
      setLockOnStart(db, true);
      expect(lockTrapWarningDue(db), isTrue);
      // …وبصمةٌ مفعَّلة تُسكته.
      setBiometricEnabled(db, true);
      expect(lockTrapWarningDue(db), isFalse);
      setBiometricEnabled(db, false);
      setLockOnStart(db, false);
      // جلسة مستعادة (لا دخول صريح) ⇒ لا حوار.
      expect(postLoginPinOfferDue(db, justLoggedIn: false), isFalse);
      // بعد تعيين الرمز: لا اقتراح، البند «تغيير»، ولا تنبيه.
      storeLockPin(db, '2468');
      expect(postLoginPinOfferDue(db, justLoggedIn: true), isFalse);
      expect(pinSettingsEntryVisible(db), isTrue);
      expect(hasPinVerifier(db), isTrue);
      expect(lockTrapWarningDue(db), isFalse);
      // مستخدم كلمة المرور: لا شيء من ذلك كله.
      storeLockVerifier(db, 'secret12');
      expect(postLoginPinOfferDue(db, justLoggedIn: true), isFalse);
      expect(
        pinSettingsEntryVisible(db),
        isFalse,
        reason: 'م91/٤: صاحب كلمة المرور لا يرى بنداً جديداً',
      );
      expect(lockTrapWarningDue(db), isFalse);
    });
  });

  group('م91/ب — الفخ القديم مُثبَت وصادق، والبصمة حرّة', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m91b_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('م96 — بلا أي وسيلة: لا يقفل الخمول أصلاً ولا رسالة', (
      tester,
    ) async {
      _seedGoogleSession(tmp);
      // مهلة خمولٍ صفرية: لو كان القفل سيشتعل لاشتعل فوراً.
      await _pumpApp(
        tester,
        tmp,
        // م133 — حُذف `staffAdminSession()` المكرَّر هنا: `_pumpApp` تُدرجه
        // ذاتياً، وتكراره يُسقط Riverpod 3 بخطأ «تجاوزٌ مزدوج لنفس المزوّد».
        overrides: [idleTimeoutProvider.overrideWithValue(Duration.zero)],
      );
      expect(find.byType(AppShellScreen), findsOneWidget);
      expect(find.byKey(const Key('idle-lock-title')), findsNothing);

      // م96 — يمرّ زمنٌ يتجاوز عدّة نبضاتِ فحص (كل 30ث): لا يُقفل
      // إطلاقاً لأن لا رمز ولا بصمة. الفخّ القديم (شاشة «خروج فقط»
      // ورسالتها) لا يُبلَغ أصلاً — لا يُعالَج برسالةٍ بل يُمنع.
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsNothing,
        reason: 'م96: لا قفلَ بلا وسيلة فتح — ولا رسالة إرشاد',
      );
      expect(find.byKey(const Key('idle-lock-guidance')), findsNothing);
      expect(
        find.byType(AppShellScreen),
        findsOneWidget,
        reason: 'م96: يبقى في التطبيق يعمل بلا انقطاع',
      );
    });

    testWidgets('البصمة تُعرض وتعمل **وحدها** بلا مُتحقِّق — جوهر الإصلاح', (
      tester,
    ) async {
      _seedGoogleSession(tmp, biometric: true, lockOnStart: true);
      final fake = _FakeBiometric(available: true, willSucceed: true);
      await _pumpApp(
        tester,
        tmp,
        // م133 — `staffAdminSession()` مكرَّر مع ما تُدرجه `_pumpApp` ذاتياً.
        overrides: [biometricAuthProvider.overrideWithValue(fake)],
      );
      // م91: قفل الإقلاع يشمل حالة البصمة-فقط (كان يتخطى صامتاً)…
      // …والبصمة عُرضت فوراً فنجحت فرُفع القفل.
      expect(
        fake.authCalls,
        greaterThanOrEqualTo(1),
        reason: 'م91: البصمة تُطلَب بلا شرط مُتحقِّق',
      );
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsNothing,
        reason: 'م91: نجاح البصمة وحدها يفتح',
      );
      expect(find.byType(AppShellScreen), findsOneWidget);
    });

    testWidgets('فشل البصمة لا يحبس: الزر باقٍ للإعادة والخروج متاح', (
      tester,
    ) async {
      _seedGoogleSession(tmp, biometric: true, lockOnStart: true);
      final fake = _FakeBiometric(available: true, willSucceed: false);
      await _pumpApp(
        tester,
        tmp,
        // م133 — `staffAdminSession()` مكرَّر مع ما تُدرجه `_pumpApp` ذاتياً.
        overrides: [biometricAuthProvider.overrideWithValue(fake)],
      );
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsOneWidget,
        reason: 'م91: قفل الإقلاع انعقد لمفعِّل البصمة بلا رمز',
      );
      expect(find.byKey(const Key('idle-lock-biometric')), findsOneWidget);
      expect(find.byKey(const Key('idle-lock-field')), findsNothing);
      expect(find.byKey(const Key('idle-lock-signout')), findsOneWidget);
    });
  });

  group('م91/ج — اقتراح الرمز بعد دخول Google', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m91c_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// يقود أولَ دخول Google كاملاً حتى الصدفة: زر الدخول ⇒ الإعداد
    /// الإجباري ⇒ إكماله ⇒ (تجهيز 600ms) ⇒ الصدفة — نفس مسار م88.
    Future<void> firstGoogleLogin(WidgetTester tester) async {
      await _pumpApp(
        tester,
        tmp,
        // م133 — `staffAdminSession()` مكرَّر مع ما تُدرجه `_pumpApp` ذاتياً.
        overrides: [
          oauthSignInProvider.overrideWithValue(_FakeOAuth(_googleUser)),
        ],
      );
      await tester.tap(find.byKey(const Key('google-signin-btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('gate-center-name')),
        'مركز الأمل',
      );
      await tester.enterText(
        find.byKey(const Key('gate-clinic-0')),
        'العيادة أ',
      );
      await tester.tap(find.byKey(const Key('gate-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('م96 — أول دخول Google لا يطلب رمزاً ولا يقفل ولا يخزّن', (
      tester,
    ) async {
      await firstGoogleLogin(tester);
      // م96 — أُزيلت نافذة أول الدخول (قرار المالك): يهبط على الصدفة
      // مباشرةً بلا أي مطالبة، ولا مُتحقِّق يُخزَّن خلسةً.
      expect(find.byType(AppShellScreen), findsOneWidget);
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsNothing,
        reason: 'م96: لا نافذةَ رمزٍ عند أول دخول',
      );
      final db = _containerOf(tester).read(localDbProvider);
      expect(
        hasLockVerifier(db),
        isFalse,
        reason: 'م96: لا تخزينَ بلا طلبٍ صريح من المستخدم',
      );
    });

    testWidgets('جلسة مستعادة برمزٍ معيَّن: يبدأ مقفلاً ويُفتَح بالرمز', (
      tester,
    ) async {
      _seedGoogleSession(tmp, pin: '2468', lockOnStart: true);
      await _pumpApp(tester, tmp);
      // م86 يعمل الآن لمستخدم Google: مُتحقِّقٌ موجود ⇒ إقلاعٌ مقفل.
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsOneWidget,
        reason: 'م91: قفل الإقلاع صار يعمل لمستخدم Google',
      );
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsNothing,
        reason: 'جلسة مستعادة لا دخول صريح ⇒ لا حوار اقتراح',
      );
      // الحقل يسمّي المطلوب باسمه: «رمز القفل» لا «كلمة المرور».
      expect(find.text('رمز القفل'), findsOneWidget);
      expect(find.text('كلمة المرور'), findsNothing);

      // رمز خاطئ ⇒ رسالة الرمز (لا رسالة كلمة المرور).
      await tester.enterText(find.byKey(const Key('idle-lock-field')), '1111');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      expect(find.text('الرمز غير صحيح'), findsOneWidget);

      // الرمز الصحيح — بالأرقام العربية عمداً — يفتح.
      await tester.enterText(find.byKey(const Key('idle-lock-field')), '٢٤٦٨');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsNothing,
        reason: 'م91: الرمز مفتاحُ هذا الجهاز — بأي لوحة أرقام',
      );
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });

  group('م91/د — مستخدم كلمة المرور: لا حرف يتغيّر', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m91d_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('الإقلاع المقفول يسأل «كلمة المرور» ويفتح بها — كما كان', (
      tester,
    ) async {
      await _seedPasswordSession(tmp, lockOnStart: true);
      await _pumpApp(tester, tmp);
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsNothing,
        reason: 'م91: لا حوار رمزٍ يظهر لمن كلمتُه مفتاحه',
      );
      expect(find.text('كلمة المرور'), findsOneWidget);
      expect(find.text('رمز القفل'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('idle-lock-field')),
        'wrong-pass',
      );
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      expect(
        find.text('كلمة المرور غير صحيحة'),
        findsOneWidget,
        reason: 'م91: نصوص مسار كلمة المرور كما هي حرفياً',
      );

      await tester.enterText(
        find.byKey(const Key('idle-lock-field')),
        'secret12',
      );
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('idle-lock-title')), findsNothing);
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });

  group('م91/هـ — بند الإعدادات وتنبيهها الصادق', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m91e_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Finder vScrollable() => find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;

    Future<void> openProtect(WidgetTester tester) async {
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
        find.byKey(const Key('group-protect')),
        300,
        scrollable: vScrollable(),
      );
      await tester.tap(find.byKey(const Key('group-protect')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('م97 — لمستخدم Google: بند التعيين ظاهر بلا تنبيهٍ فخّ', (
      tester,
    ) async {
      _seedGoogleSession(tmp); // لا رمز ولا بصمة + القفل مطفأ افتراضاً (م97)
      await _pumpApp(tester, tmp);
      expect(find.byType(AppShellScreen), findsOneWidget);
      await openProtect(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('set-pin-btn')),
        300,
        scrollable: vScrollable(),
      );
      expect(
        find.text('تعيين رمز القفل'),
        findsOneWidget,
        reason: 'م91/٤: بند التعيين ظاهر لمن دخل بلا كلمة مرور',
      );
      // م97 — القفل مطفأ افتراضاً فلا فخّ ⇒ لا تنبيه أصلاً.
      expect(
        find.byKey(const Key('set-lock-warning')),
        findsNothing,
        reason: 'م97: لا قفلَ مفعَّلاً بلا وسيلة ⇒ لا تنبيه فخّ',
      );

      // التعيين من البند نفسه يعمل ويقلبه إلى «تغيير».
      await tester.tap(find.byKey(const Key('set-pin-btn')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('pin-setup-field')),
        '246810',
      );
      await tester.enterText(
        find.byKey(const Key('pin-setup-confirm')),
        '246810',
      );
      await tester.tap(find.byKey(const Key('pin-setup-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('تغيير رمز القفل'), findsOneWidget);
      final db = _containerOf(tester).read(localDbProvider);
      expect(hasPinVerifier(db), isTrue);
    });

    testWidgets('لمستخدم كلمة المرور: لا بند ولا تنبيه — شاشته كما كانت', (
      tester,
    ) async {
      await _seedPasswordSession(tmp);
      // تعطيل قفل الإقلاع كي نصل الإعدادات مباشرة (تفضيل محلي مشروع).
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      setLockOnStart(c.read(localDbProvider), false);
      c.dispose();

      await _pumpApp(tester, tmp);
      expect(find.byType(AppShellScreen), findsOneWidget);
      await openProtect(tester);
      // مرّر إلى آخر بنود القفل (مفتاح البصمة) للتأكد أن ما بعدها بُني.
      await tester.scrollUntilVisible(
        find.byKey(const Key('set-biometric')),
        300,
        scrollable: vScrollable(),
      );
      expect(
        find.byKey(const Key('set-pin-btn')),
        findsNothing,
        reason: 'م91/٤: كلمتُه مفتاحه — لا بند جديد يشوّش',
      );
      expect(
        find.byKey(const Key('set-lock-warning')),
        findsNothing,
        reason: 'م91/٥: لديه وسيلة فتح — لا تنبيه',
      );
    });
  });

  group('م91/و — خنق المحاولات على الغطاء', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m91f_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('خمسة إخفاقات ⇒ انتظار يصدّ حتى الصحيح، ثم يفتح بعده', (
      tester,
    ) async {
      _seedGoogleSession(tmp, pin: '2468', lockOnStart: true);
      await _pumpApp(
        tester,
        tmp,
        // م133 — حُذف `staffAdminSession()` المكرَّر (`_pumpApp` تُدرجه
        // ذاتياً). نافذة مضغوطة: أوسع من فجوة إدخالٍ بين محاولتين (فيثبت
        // الصدّ) وأقصر من صبر الاختبار (فيُختبَر الانقضاء على الساعة الحقيقية).
        overrides: [
          lockThrottleProvider.overrideWithValue((
            maxFails: 5,
            window: const Duration(milliseconds: 500),
          )),
        ],
      );
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.enterText(
          find.byKey(const Key('idle-lock-field')),
          '0000',
        );
        await tester.tap(find.byKey(const Key('idle-lock-unlock')));
        await tester.pump();
      }
      expect(find.text('الرمز غير صحيح'), findsOneWidget);

      // الصحيح **أثناء** النافذة يُرفض — وإلا واصل المخمِّن قصفه بلا كلفة.
      await tester.enterText(find.byKey(const Key('idle-lock-field')), '2468');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      expect(
        find.textContaining('محاولات كثيرة'),
        findsOneWidget,
        reason: 'م91: سقف الإخفاقات يفرض انتظاراً حقيقياً',
      );
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);

      // بعد انقضائها يعود المفتاح مفتاحاً. الانتظار نبضاتٌ متتالية على
      // الساعة الحقيقية (النافذة تقاس بـ DateTime.now) — لا runAsync:
      // تشغيل القنوات الحقيقية يرمي MissingPluginException في الصندوق.
      final windowEnd = DateTime.now().add(const Duration(milliseconds: 650));
      while (DateTime.now().isBefore(windowEnd)) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      await tester.enterText(find.byKey(const Key('idle-lock-field')), '2468');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('idle-lock-title')), findsNothing);
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });
}
