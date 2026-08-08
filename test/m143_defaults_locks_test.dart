/// اختبارات م143 — الافتراضات المبذورة والأقفال + مهلة التراجع عن الحذف:
///   • البذر (post_login_gate/_submitSetup): payments==[كاش,تحويل] و services
///     يحوي الافتراضات الثلاثة، والبذر لا يدهس قائمةً غير فارغة (idempotent).
///   • الأقفال في الإعدادات: كاش/تحويل بلا زر حذف وحقل الإضافة غائب؛ من
///     المعالجات «تركيبات» وحدها بلا زر حذف (حشوا العصب يبقيان قابلَي الحذف).
///   • مهلة التراجع عن الحذف (xray.delete_undo_secs): تُكتب وتُقرأ (5)،
///     و0 = إيقاف.
///
/// نستعمل نفس الحزام: staffAdminSession + dbDirProvider + ProviderContainer/
/// reposProvider (كما في m7_settings_11_test).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/features/settings/settings_screen.dart'
    show xrayDeleteUndoSecs, setXrayDeleteUndoSecs;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m143_'));
  tearDown(() {
    BrandColors.darkMode = false;
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer container() => ProviderContainer(
    overrides: [staffAdminSession(), dbDirProvider.overrideWithValue(tmp.path)],
  );

  // ── محاكاةُ ما يفعله _submitSetup عند البذر (نفس مسار الكتابة الكامل) ──
  // البوابة كلاسٌ خاص لا يُستدعى مباشرةً في اختبار وحدة؛ نُعيد إنتاج منطق
  // البذر الحتمي حرفياً (idempotent) فوق app.config عبر reposProvider.
  Map<String, Object?> seedDefaults(Map<String, Object?> cur) {
    final cfg = Map<String, Object?>.from(cur);
    bool empty(Object? v) =>
        v is! List || v.where((e) => '$e'.trim().isNotEmpty).isEmpty;
    if (empty(cfg['payments'])) {
      cfg['payments'] = <String>['كاش', 'تحويل'];
    }
    if (empty(cfg['services'])) {
      cfg['services'] = <String>['حشو عصب أمامي', 'حشو عصب خلفي', 'تركيبات'];
    }
    return cfg;
  }

  group('م143 — البذر الافتراضي (idempotent)', () {
    test('البذر يملأ payments=[كاش,تحويل] وservices بالافتراضات الثلاثة', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      // إعدادٌ صحيح بلا payments/services (كحال أول إعداد).
      repos.settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
      });
      final cur = repos.settings.get('app.config') as Map;
      repos.settings.set(
        'app.config',
        seedDefaults(Map<String, Object?>.from(cur)),
      );

      final cfg = repos.settings.get('app.config') as Map;
      expect(cfg['payments'], ['كاش', 'تحويل']);
      final services = [for (final e in cfg['services'] as List) '$e'];
      expect(services, containsAll(['حشو عصب أمامي', 'حشو عصب خلفي', 'تركيبات']));
    });

    test('البذر لا يدهس قائمةً غير فارغة (يحفظ بيانات المستخدم)', () {
      final c = container();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);
      repos.settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'payments': ['فيزا'], // قائمةٌ قائمة للمستخدم
        'services': ['قلع'],
      });
      final cur = repos.settings.get('app.config') as Map;
      repos.settings.set(
        'app.config',
        seedDefaults(Map<String, Object?>.from(cur)),
      );

      final cfg = repos.settings.get('app.config') as Map;
      // بقيت كما هي — لم تُدهَس بالافتراضات.
      expect(cfg['payments'], ['فيزا']);
      expect(cfg['services'], ['قلع']);
    });
  });

  group('م143 — مهلة التراجع عن الحذف (تفضيل محلي)', () {
    test('الغياب ⇒ 3 (الافتراضي)', () {
      final c = container();
      addTearDown(c.dispose);
      final db = c.read(localDbProvider);
      expect(xrayDeleteUndoSecs(db), 3);
    });

    test('كتابة 5 ⇒ القراءة تُعيد 5، وكتابة 0 ⇒ إيقاف (0)', () {
      final c = container();
      addTearDown(c.dispose);
      final db = c.read(localDbProvider);
      setXrayDeleteUndoSecs(db, 5);
      expect(xrayDeleteUndoSecs(db), 5);
      // القيمة الخام في sync_meta نصٌّ '5' (توأم بقية التفضيلات).
      final raw = db.queryFirst(
        'SELECT value FROM sync_meta WHERE key = ?',
        const ['xray.delete_undo_secs'],
      );
      expect('${raw?['value']}', '5');
      // 0 = إيقاف المؤقّت.
      setXrayDeleteUndoSecs(db, 0);
      expect(xrayDeleteUndoSecs(db), 0);
    });
  });

  group('م143 — الأقفال في واجهة الإعدادات', () {
    Future<void> boot(
      WidgetTester tester, {
      required Map<String, Object?> cfg,
    }) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', cfg);
      c.dispose();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder vScrollable() => find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;

    Future<void> openGroup(WidgetTester tester, String id) async {
      await tester.scrollUntilVisible(
        find.byKey(Key('group-$id')),
        300,
        scrollable: vScrollable(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('group-$id')), warnIfMissed: false);
      await settle(tester);
    }

    Map<String, Object?> cfgWith({
      List<String>? payments,
      List<String>? services,
    }) => {
      'centerName': 'مركز الاختبار',
      'clinics': ['ع1'],
      'services': services ?? ['حشو عصب أمامي', 'حشو عصب خلفي', 'تركيبات'],
      'payments': payments ?? ['كاش', 'تحويل'],
    };

    testWidgets(
      'طرق الدفع المقفولة (كاش/تحويل) بلا زر حذف وحقل الإضافة غائب',
      (tester) async {
        await boot(tester, cfg: cfgWith(payments: ['كاش', 'تحويل']));
        await tester.tap(find.byTooltip('الإعدادات'));
        await settle(tester);
        await openGroup(tester, 'clinic');

        // كلا طريقتي الدفع مقفولتان ⇒ لا زرَّ حذف إطلاقاً.
        expect(find.byKey(const Key('pay-del-0')), findsNothing);
        expect(find.byKey(const Key('pay-del-1')), findsNothing);
        // حقل إضافة طريقة دفعٍ محذوفٌ كلياً (وزر حفظه).
        expect(find.byKey(const Key('new-payment-input')), findsNothing);
        expect(find.byKey(const Key('add-payment')), findsNothing);
        // النصّان لا يزالان معروضين (البنود موجودة، فقط بلا حذف).
        expect(find.text('كاش'), findsWidgets);
        expect(find.text('تحويل'), findsWidgets);
      },
    );

    testWidgets(
      'من المعالجات: «تركيبات» وحدها بلا زر حذف؛ حشوا العصب قابلان للحذف',
      (tester) async {
        final services = ['حشو عصب أمامي', 'حشو عصب خلفي', 'تركيبات'];
        await boot(tester, cfg: cfgWith(services: services));
        await tester.tap(find.byTooltip('الإعدادات'));
        await settle(tester);
        await openGroup(tester, 'clinic');

        // ثلاث معالجات، واحدة مقفولة ⇒ زرَّا حذفٍ فقط (svc-del-*).
        final delButtons = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('svc-del-'),
        );
        expect(delButtons, findsNWidgets(services.length - 1));
        // حشوا العصب (فهرس 0 و1) لهما زر حذف.
        expect(find.byKey(const Key('svc-del-0')), findsOneWidget);
        expect(find.byKey(const Key('svc-del-1')), findsOneWidget);
        // «تركيبات» (الفهرس الأخير) بلا زر حذف.
        expect(
          find.byKey(Key('svc-del-${services.length - 1}')),
          findsNothing,
        );
        // لكنها لا تزال معروضةً كبند (نصّها ظاهر).
        expect(find.text('تركيبات'), findsWidgets);
        // إضافة معالجةٍ جديدة تبقى متاحة (خلاف طرق الدفع).
        expect(find.byKey(const Key('new-service-input')), findsOneWidget);
      },
    );
  });
}
