/// اختبارات م97 — النموذج النهائي: مفتاحان مطفآن افتراضياً، وتفعيلُ أيٍّ
/// منهما يستلزم رمزاً إجبارياً، ودخولُ كلمة المرور لا يدهس الرمز.
///
///  القاعدة (قرار المالك): «القفل عند فتح التطبيق» و«الدخول بالبصمة»
///  مطفآن للجميع، وشرطُ تشغيل أيٍّ منهما تعيينُ رمز قفلٍ — فلا يصل أحدٌ
///  إلى قفلٍ أو بصمةٍ بلا رمزٍ يفتح بهما. كلمةُ المرور مفتاحُ الحساب،
///  والرمزُ مفتاحُ الشاشة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart' show LocalDb;
import 'package:dental_clinic_flutter/features/auth/idle_lock.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart';
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/auth/pin_setup.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

Future<void> _seedPassword(Directory tmp) async {
  final c = ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );
  await c.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
  await c.read(authProvider.notifier).login('doc@clinic.ly', 'secret12', true);
  c.read(reposProvider).settings.set('app.config', {
    'centerName': 'مركز',
    'clinics': ['ع1'],
  });
  markSetupComplete(c.read(localDbProvider), 'doc@clinic.ly');
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

Future<void> _openProtect(WidgetTester tester) async {
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

Switch _sw(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(Key(key)));

LocalDb _db(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(DentalApp)),
  listen: false,
).read(localDbProvider);

void main() {
  group('م97/أ — الافتراضيان مطفآن (طبقة التخزين)', () {
    late Directory tmp;
    late ProviderContainer c;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m97a_');
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

    test('القفل عند الفتح والبصمة كلاهما معطَّل افتراضاً', () {
      final db = c.read(localDbProvider);
      expect(lockOnStartEnabled(db), isFalse, reason: 'م97: القفل مطفأ');
      expect(biometricEnabled(db), isFalse, reason: 'م97: البصمة مطفأة');
    });
  });

  group('م97/ب — تفعيلُ كلٍّ يستلزم رمزاً إجبارياً', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m97b_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('القفل: الإلغاء يُبقيه مطفأً، والتعيين يُفعّله', (
      tester,
    ) async {
      await _seedPassword(tmp);
      await _pump(tester, tmp);
      await _openProtect(tester);
      // مطفأٌ ابتداءً (م97).
      expect(_sw(tester, 'set-lock-on-start').value, isFalse);

      // تشغيله يفتح حوار الرمز؛ الإلغاء يُبقيه مطفأً.
      await tester.tap(find.byKey(const Key('set-lock-on-start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsOneWidget,
        reason: 'م97: تعيين رمزٍ شرطُ التفعيل',
      );
      await tester.tap(find.byKey(const Key('pin-setup-later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_sw(tester, 'set-lock-on-start').value, isFalse);
      expect(hasPinVerifier(_db(tester)), isFalse);

      // التعيين هذه المرة يُفعّله.
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
      expect(_sw(tester, 'set-lock-on-start').value, isTrue);
      final db = _db(tester);
      expect(hasPinVerifier(db), isTrue);
      expect(lockOnStartEnabled(db), isTrue);
    });

    testWidgets('البصمة: تشغيلُها بلا رمزٍ يفتح حوار التعيين', (tester) async {
      await _seedPassword(tmp);
      await _pump(tester, tmp);
      await _openProtect(tester);
      expect(
        _sw(tester, 'set-biometric').value,
        isFalse,
        reason: 'م97: البصمة مطفأة افتراضاً',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('set-biometric')),
        200,
        scrollable: _vScroll(),
      );
      await tester.tap(find.byKey(const Key('set-biometric')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const Key('pin-setup-title')),
        findsOneWidget,
        reason: 'م97: البصمة أيضاً تستلزم رمزاً أولاً',
      );
      // الإلغاء ⇒ تبقى مطفأة.
      await tester.tap(find.byKey(const Key('pin-setup-later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_sw(tester, 'set-biometric').value, isFalse);
      expect(biometricEnabled(_db(tester)), isFalse);
    });
  });

  group('م97/ج — دخول كلمة المرور لا يدهس الرمز', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m97c_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('رمزٌ معيَّن يبقى بعد إعادة دخول كلمة المرور', () async {
      // أول دخول: لا رمز ⇒ يُخزَّن مُتحقِّق كلمة المرور (توافق تاريخي).
      final c1 = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      await c1.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
      await c1
          .read(authProvider.notifier)
          .login('doc@clinic.ly', 'secret12', true);
      final db1 = c1.read(localDbProvider);
      // المالك يعيّن رمزاً (كأنه فعّل القفل).
      storeLockPin(db1, '246810');
      expect(hasPinVerifier(db1), isTrue);
      await c1.read(authProvider.notifier).logout();
      c1.dispose();

      // إعادة دخولٍ بكلمة المرور: **يجب ألّا يدهس الرمز**.
      final c2 = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      await c2
          .read(authProvider.notifier)
          .login('doc@clinic.ly', 'secret12', true);
      final db2 = c2.read(localDbProvider);
      expect(
        hasPinVerifier(db2),
        isTrue,
        reason: 'م97: الرمز صمد — لم يدهسه دخول كلمة المرور',
      );
      expect(verifyLock(db2, '246810'), isTrue);
      expect(lockVerifierKind(db2), 'pin');
      c2.dispose();
    });

    test('بلا رمزٍ: دخول كلمة المرور يخزّن مُتحقِّقها (سلوك تاريخي)', () async {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      await c.read(authServiceProvider).register('d@c.ly', 'secret12');
      await c.read(authProvider.notifier).login('d@c.ly', 'secret12', true);
      final db = c.read(localDbProvider);
      expect(hasLockVerifier(db), isTrue);
      expect(lockVerifierKind(db), 'password');
      expect(verifyLock(db, 'secret12'), isTrue);
      c.dispose();
    });
  });
}
