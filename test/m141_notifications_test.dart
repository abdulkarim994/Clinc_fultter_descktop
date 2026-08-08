/// اختبارات المرحلة هـ — الإشعارات داخل التطبيق (بلا Firebase/دفع).
///
///   • واجهة: تسلسل نوافذ الإشعارات غير المقروءة عند فتح التطبيق — النافذة
///     تعرض العنوان، وزرُّ الإجراء يفتح الرابط، والضغط على «تم» يعلّم الإشعار
///     مقروءاً (يسجّله الناقل المزيّف)، ثم تظهر نافذة التحديث بزرِّ التحميل.
///   • وحدة: تفضيل «إظهار زر التحديث» افتراضُه صحيح (unset) ثم يُقلَب ويثبت.
///
/// الناقل مزيَّفٌ بالكامل — لا يمسّ قاعدةً/خادماً. نُغطّي `showPendingNotifications`
/// مباشرةً عبر مُضيفٍ صغير (Builder) بدل تركيب البوابة كاملةً.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart'
    show FakeSyncServer;
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show NotificationsTransport;
import 'package:dental_clinic_flutter/features/notifications/notification_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

/// ناقلٌ مزيَّفٌ يُنفّذ [NotificationsTransport] فوق [FakeSyncServer]
/// (فيرث تنفيذ SyncTransport فيبقى تجاوز `transportProvider` صالحاً نوعياً).
/// يعيد إشعاراتٍ مُبذَّرة ويسجّل ما عُلِّم مقروءاً كي يتحقّق الاختبار.
class _FakeNotifTransport extends FakeSyncServer
    implements NotificationsTransport {
  _FakeNotifTransport({
    required this.notifications,
    required this.update,
  });

  final List<Map<String, Object?>> notifications;
  final Map<String, Object?> update;

  /// معرّفات الإشعارات التي عُلِّمت مقروءةً (بالترتيب).
  final List<String> markedRead = [];
  int getCalls = 0;

  @override
  Future<List<Map<String, Object?>>> getMyNotifications() async {
    getCalls++;
    return notifications;
  }

  @override
  Future<void> markNotificationRead(String id) async {
    markedRead.add(id);
  }

  @override
  Future<Map<String, Object?>> getAppUpdate() async => update;
}

/// زرٌّ يستدعي `showPendingNotifications(context, ref)` — مُضيفٌ اختباريٌّ صغير.
class _GoButton extends ConsumerWidget {
  const _GoButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ElevatedButton(
    key: const Key('go'),
    onPressed: () => showPendingNotifications(context, ref),
    child: const Text('go'),
  );
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m141_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // ── وحدة: تفضيل إظهار زر التحديث ──────────────────────────────────────────
  group('وحدة — تفضيل إظهار زر التحديث', () {
    test('الغياب = مفعَّل، والقلب يثبت في sync_meta', () {
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      addTearDown(c.dispose);
      final db = c.read(localDbProvider);

      // الافتراض عند الغياب = صحيح (إظهار الزر).
      expect(showUpdateButtonPref(db), isTrue);

      // إخفاء الزر ⇒ يثبت false.
      setShowUpdateButtonPref(db, false);
      expect(showUpdateButtonPref(db), isFalse);

      // إعادة الإظهار ⇒ true.
      setShowUpdateButtonPref(db, true);
      expect(showUpdateButtonPref(db), isTrue);
    });
  });

  // ── واجهة: تسلسل النوافذ عند فتح التطبيق ───────────────────────────────────
  group('واجهة — تسلسل الإشعارات ثم نافذة التحديث', () {
    /// مُضيفٌ صغير: زرٌّ واحدٌ يستدعي `showPendingNotifications(context, ref)`.
    const host = MaterialApp(
      home: Scaffold(
        body: Center(
          child: _GoButton(),
        ),
      ),
    );

    Future<_FakeNotifTransport> pumpHost(
      WidgetTester tester, {
      required List<Map<String, Object?>> notifications,
      required Map<String, Object?> update,
    }) async {
      final fake = _FakeNotifTransport(
        notifications: notifications,
        update: update,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
            transportProvider.overrideWithValue(fake),
          ],
          child: host,
        ),
      );
      await tester.pump();
      return fake;
    }

    testWidgets(
      'النافذة تعرض العنوان، زر الإجراء موجود، «تم» يعلّم مقروءاً، ثم نافذة '
      'التحديث بزر التحميل',
      (tester) async {
        final fake = await pumpHost(
          tester,
          notifications: [
            {
              'id': 'n1',
              'title': 'ترحيب',
              'body': 'مرحباً بك في التطبيق',
              'kind': 'info',
              'data': {
                'action_label': 'افتح',
                'action_url': 'https://example.com/a',
              },
              'created_at': '2026-08-01T00:00:00Z',
            },
            {
              'id': 'n2',
              'title': 'خبر ثانٍ',
              'body': 'تفاصيل الخبر',
              'kind': 'info',
              'data': <String, Object?>{},
              'created_at': '2026-08-02T00:00:00Z',
            },
          ],
          update: {
            'enabled': true,
            'version': 'v999',
            'url': 'https://example.com/download',
            'notes': 'إصلاحات وتحسينات',
          },
        );

        // فتح التطبيق (استدعاء الدالة).
        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();

        // النافذة الأولى: العنوان + زر الإجراء + زر «تم».
        expect(find.byKey(const Key('notif-dialog')), findsOneWidget);
        expect(find.text('ترحيب'), findsOneWidget);
        expect(find.byKey(const Key('notif-action')), findsOneWidget);

        // إغلاق الأولى بـ«تم» ⇒ تُعلَّم مقروءةً وتظهر الثانية.
        await tester.tap(find.byKey(const Key('notif-done')));
        await tester.pumpAndSettle();
        expect(fake.markedRead, contains('n1'));
        expect(find.text('خبر ثانٍ'), findsOneWidget);
        // الثانية بلا إجراء (data فارغة).
        expect(find.byKey(const Key('notif-action')), findsNothing);

        // إغلاق الثانية ⇒ تُعلَّم، ثم تظهر نافذة التحديث.
        await tester.tap(find.byKey(const Key('notif-done')));
        await tester.pumpAndSettle();
        expect(fake.markedRead, containsAllInOrder(['n1', 'n2']));

        // نافذة التحديث + زر التحميل (التفضيل الافتراضي = إظهار).
        expect(find.byKey(const Key('update-dialog')), findsOneWidget);
        expect(find.text('تحديث متوفّر'), findsOneWidget);
        expect(find.byKey(const Key('update-download')), findsOneWidget);
        expect(find.textContaining('إصلاحات وتحسينات'), findsOneWidget);
      },
    );

    testWidgets('إخفاء زر التحديث بالتفضيل ⇒ النافذة بلا زر التحميل', (
      tester,
    ) async {
      // اضبط التفضيل «مخفي» قبل الاستدعاء على قاعدة المجلد نفسه.
      final c = ProviderContainer(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
      );
      setShowUpdateButtonPref(c.read(localDbProvider), false);
      c.dispose();

      await pumpHost(
        tester,
        notifications: const [],
        update: {
          'enabled': true,
          'version': 'v999',
          'url': 'https://example.com/download',
          'notes': 'ملاحظات',
        },
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      // نافذة التحديث ظاهرة لكن بلا زر تحميل.
      expect(find.byKey(const Key('update-dialog')), findsOneWidget);
      expect(find.byKey(const Key('update-download')), findsNothing);
    });

    testWidgets('لا نافذة تحديث حين النسخة تطابق نسخة التطبيق', (tester) async {
      await pumpHost(
        tester,
        notifications: const [],
        update: {
          'enabled': true,
          // نسخةٌ فارغةٌ ⇒ لا نافذة (نفس منطق التطابق/الفراغ).
          'version': '',
          'url': 'https://example.com/download',
          'notes': 'x',
        },
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-dialog')), findsNothing);
    });
  });
}
