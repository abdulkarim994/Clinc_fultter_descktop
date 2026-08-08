/// اختبارات م96 — لا قفلَ بلا وسيلة فتح، وبوابةُ مفتاح «القفل عند الفتح».
///
///  القاعدة (قرار المالك): قفلٌ لا مفتاح له (لا رمز ولا بصمة) ليس أماناً
///  بل حبسٌ يفرض خروجاً ويعرض رسالةَ فخّ. فلا يُقفل التطبيق — لا خمولاً
///  ولا إقلاعاً — إلا بوجود وسيلة فتح؛ وتفعيلُ «القفل عند فتح التطبيق»
///  يستلزم تعيينَ رمزٍ أولاً. مستخدم كلمة المرور لا يتغيّر عنده شيء.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/idle_lock.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

const _uid = 'google-uid-1';

/// يبذر جلسةَ Google مستعادةً مكتملةَ الإعداد (كإقلاعٍ بارد بعد دخول
/// سابق) مع خيارات: رمزٌ، بصمة، حالة مفتاح القفل.
void _seedGoogle(
  Directory tmp, {
  String? pin,
  bool? biometric,
  bool? lockOnStart,
}) {
  final c = ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );
  final db = c.read(localDbProvider);
  db.setOwnerUid(_uid);
  db.execute(
    'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
    "VALUES ('local_auth_session', ?, datetime('now'))",
    [
      jsonEncode({'uid': _uid, 'email': 'dr@gmail.com'}),
    ],
  );
  c.read(reposProvider).settings.set('app.config', {
    'centerName': 'مركز الاختبار',
    'clinics': ['ع1'],
  });
  markSetupComplete(db, _uid);
  if (pin != null) storeLockPin(db, pin);
  if (biometric != null) setBiometricEnabled(db, biometric);
  if (lockOnStart != null) setLockOnStart(db, lockOnStart);
  c.dispose();
}

Future<void> _pump(
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

Finder _vScroll() => find
    .byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          axisDirectionToAxis(w.axisDirection) == Axis.vertical,
    )
    .first;

void main() {
  group('م96/أ — الخمول يحترم وجود وسيلة الفتح', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m96a_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('برمزٍ: الخمول يقفل والرمز يفتح (البوابة لا تُفرط بالحجب)', (
      tester,
    ) async {
      _seedGoogle(tmp, pin: '2468', lockOnStart: true);
      // م133 — حُذف `staffAdminSession()` المكرَّر: `_pump` تُدرجه ذاتياً،
      // وتكراره يُسقط Riverpod 3 بخطأ «تجاوزٌ مزدوج لنفس المزوّد».
      await _pump(
        tester,
        tmp,
        overrides: [idleTimeoutProvider.overrideWithValue(Duration.zero)],
      );
      // برمزٍ: قفل الإقلاع ينعقد أصلاً (م91) — فالشاشة مقفلة فوراً.
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsOneWidget,
        reason: 'م96: وجود الرمز يسمح بالقفل',
      );
      await tester.enterText(find.byKey(const Key('idle-lock-field')), '2468');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AppShellScreen), findsOneWidget);
    });

    testWidgets('بلا وسيلة: نبضاتُ الخمول المتتالية لا تقفل أبداً', (
      tester,
    ) async {
      _seedGoogle(tmp); // لا رمز ولا بصمة
      // م133 — حُذف `staffAdminSession()` المكرَّر (انظر التعليق أعلاه).
      await _pump(
        tester,
        tmp,
        overrides: [idleTimeoutProvider.overrideWithValue(Duration.zero)],
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 31));
        expect(
          find.byKey(const Key('idle-lock-title')),
          findsNothing,
          reason: 'م96: لا قفلَ بلا وسيلة (نبضة $i)',
        );
      }
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });

  group('م96/ب — بوابة «القفل عند فتح التطبيق»', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m96b_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> openProtect(WidgetTester tester) async {
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
        find.byKey(const Key('group-protect')),
        300,
        scrollable: _vScroll(),
      );
      await tester.tap(find.byKey(const Key('group-protect')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('داخلُ Google بلا رمز: المفتاح يُعرض مطفأً', (tester) async {
      _seedGoogle(tmp); // م97: لا رمز ⇒ المفتاح مطفأ (والافتراض مطفأ)
      await _pump(tester, tmp);
      expect(find.byType(AppShellScreen), findsOneWidget);
      await openProtect(tester);
      final sw = tester.widget<Switch>(
        find.byKey(const Key('set-lock-on-start')),
      );
      expect(
        sw.value,
        isFalse,
        reason: 'م96: العرض الفعّال مطفأ بلا وسيلة فتح رغم التفضيل',
      );
    });

    testWidgets('تفعيلُه بلا وسيلة يفتح حوار الرمز؛ الإلغاء يُبقيه مطفأً', (
      tester,
    ) async {
      _seedGoogle(tmp);
      await _pump(tester, tmp);
      await openProtect(tester);
      await tester.tap(find.byKey(const Key('set-lock-on-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // حوار تعيين الرمز يُفتح بدل تفعيلٍ أعمى.
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsOneWidget,
        reason: 'م96: التفعيل يقود لتعيين رمزٍ أولاً',
      );
      await tester.tap(find.byKey(const Key('pin-setup-later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final sw = tester.widget<Switch>(
        find.byKey(const Key('set-lock-on-start')),
      );
      expect(sw.value, isFalse, reason: 'م96: الإلغاء يُبقيه مطفأً');
      final db = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      ).read(localDbProvider);
      expect(hasLockVerifier(db), isFalse);
    });

    testWidgets('تعيينُ رمزٍ من الحوار يُفعّل المفتاح', (tester) async {
      _seedGoogle(tmp);
      await _pump(tester, tmp);
      await openProtect(tester);
      await tester.tap(find.byKey(const Key('set-lock-on-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
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
      final sw = tester.widget<Switch>(
        find.byKey(const Key('set-lock-on-start')),
      );
      expect(sw.value, isTrue, reason: 'م96: بعد تعيين الرمز يُفعّل');
      final db = ProviderScope.containerOf(
        tester.element(find.byType(DentalApp)),
        listen: false,
      ).read(localDbProvider);
      expect(hasLockVerifier(db), isTrue);
      expect(lockOnStartEnabled(db), isTrue);
    });
  });

  group('م96/ج — مستخدم كلمة المرور بلا تغيير', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m96c_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> seedPassword({bool lockOnStart = false}) async {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
      await c
          .read(authProvider.notifier)
          .login('doc@clinic.ly', 'secret12', true);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز',
        'clinics': ['ع1'],
      });
      markSetupComplete(c.read(localDbProvider), 'doc@clinic.ly');
      if (lockOnStart) setLockOnStart(c.read(localDbProvider), true);
      c.dispose();
    }

    testWidgets('م97 — القفل معطَّل افتراضاً: لا يقفل حتى لمن له مُتحقِّق', (
      tester,
    ) async {
      await seedPassword(); // بلا تفعيلٍ صريح
      // م133 — حُذف `staffAdminSession()` المكرَّر (`_pump` تُدرجه ذاتياً).
      await _pump(
        tester,
        tmp,
        overrides: [idleTimeoutProvider.overrideWithValue(Duration.zero)],
      );
      await tester.pump(const Duration(seconds: 31));
      expect(
        find.byKey(const Key('idle-lock-title')),
        findsNothing,
        reason: 'م97: مطفأ افتراضاً للجميع حتى يفعّله المالك',
      );
      expect(find.byType(AppShellScreen), findsOneWidget);
    });

    testWidgets('حين يُفعَّل: كلمة المرور تفتح القفل — كما كان', (
      tester,
    ) async {
      await seedPassword(lockOnStart: true);
      // م133 — حُذف `staffAdminSession()` المكرَّر (`_pump` تُدرجه ذاتياً).
      await _pump(
        tester,
        tmp,
        overrides: [idleTimeoutProvider.overrideWithValue(Duration.zero)],
      );
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('idle-lock-field')),
        'secret12',
      );
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });
}
