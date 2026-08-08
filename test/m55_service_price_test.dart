/// اختبار م55 — سعر المعالجة: الحفظ بلا Enter وظهوره على الجهازين:
///   • وحدات (جهازان حقيقيان عبر خادم بدلالات الخلفية): سعر من A يصل B،
///     سعران لمعالجتين من جهازين معاً ينجوان (صف ورقة لكل معالجة)،
///     تعارض نفس السعر ⇒ الأحدث، معالجة جديدة + سعرها من جهازين.
///   • واجهة: كتابة السعر ثم مغادرة الحقل (لمسة خارجه / حقل آخر / رجوع)
///     تحفظه — كان الحفظ على Enter فقط فيضيع؛ واختيار المعالجة في
///     الرئيسية يملأ سعرها حتى لو كان الحقل مملوءاً بسعر معالجة سابقة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';
import 'staff_test_session.dart' show staffAdminSession;

// ═══ جهاز حقيقي (قاعدة SQLite) — نمط m51 حرفياً ═══

class Device {
  Device(this.name, FakeSyncServer server)
    : tmp = Directory.systemTemp.createTempSync('m55_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine = SyncEngine(SyncContext(db: db, repos: repos, transport: server));
  }

  final String name;
  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncEngine engine;

  Future<void> sync() async {
    await engine.runCycle('test');
  }

  Map<String, Object?> get config {
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  Map<String, Object?> get prices => config['servicePrices'] is Map
      ? Map<String, Object?>.from(config['servicePrices'] as Map)
      : <String, Object?>{};

  Set<String> list(String key) => <String>{
    for (final e in (config[key] is List ? config[key] as List : const []))
      '$e',
  };

  /// توأم _setSvcPrice في شاشة الإعدادات: كتابة السعر من لقطة أساس.
  void setPrice(String svc, num n) {
    final cfg = config;
    final ps = prices;
    if (n > 0) {
      ps[svc] = n;
    } else {
      ps.remove(svc);
    }
    repos.settings.set('app.config', {
      ...cfg,
      'servicePrices': ps,
    }, configBase: cfg);
  }

  void dispose() {
    engine.stopEngine();
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  group('الوحدات — سعر المعالجة بين جهازين', () {
    late FakeSyncServer server;
    late Device a;
    late Device b;

    setUp(() {
      server = FakeSyncServer();
      a = Device('a', server);
      b = Device('b', server);
    });

    tearDown(() {
      a.dispose();
      b.dispose();
    });

    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await a.sync();
        await b.sync();
      }
    }

    Future<void> seedBoth() async {
      a.repos.settings.set('app.config', {
        'centerName': 'مركز التقارب',
        'services': ['حشو', 'خلع'],
      });
      await settle();
      expect(b.list('services'), containsAll(const {'حشو', 'خلع'}));
    }

    test('سعر يُضبط على A يظهر على B', () async {
      await seedBoth();
      a.setPrice('حشو', 120);
      await settle();
      expect(
        jsNumOr0(b.prices['حشو']),
        120,
        reason: 'b: سعر A وصل عبر صف الورقة المستقل',
      );
    });

    test('سعران لمعالجتين من جهازين معاً: الاثنان ينجوان', () async {
      await seedBoth();
      // كل سعر ورقة مستقلة (cfg:s:servicePrices.المعالجة) — لا يدهس
      // جهاز خريطة الأسعار كاملة فوق تعديل الآخر.
      a.setPrice('حشو', 120);
      b.setPrice('خلع', 80);
      await settle();

      for (final d in [a, b]) {
        expect(jsNumOr0(d.prices['حشو']), 120, reason: '${d.name}: سعر A نجا');
        expect(jsNumOr0(d.prices['خلع']), 80, reason: '${d.name}: سعر B نجا');
      }
    });

    test('تعارض على سعر المعالجة نفسها: الأحدث يفوز والبقية سليمة', () async {
      await seedBoth();
      a.setPrice('حشو', 100);
      a.setPrice('خلع', 55);
      await settle();
      b.setPrice('حشو', 150); // الأحدث
      await settle();

      for (final d in [a, b]) {
        expect(jsNumOr0(d.prices['حشو']), 150, reason: '${d.name}: الأحدث حسم');
        expect(
          jsNumOr0(d.prices['خلع']),
          55,
          reason: '${d.name}: سعر لم يُلمس لم يتغير',
        );
      }
    });

    test(
      'معالجة جديدة بسعرها من A ومعالجة أخرى من B: الكل يظهر عند الكل',
      () async {
        await seedBoth();
        a.repos.settings.configAddItem(const ['services'], 'زراعة');
        a.setPrice('زراعة', 900);
        b.repos.settings.configAddItem(const ['services'], 'تبييض');
        await settle();

        for (final d in [a, b]) {
          expect(
            d.list('services'),
            containsAll(const {'حشو', 'خلع', 'زراعة', 'تبييض'}),
            reason: '${d.name}: المعالجتان الجديدتان معاً',
          );
          expect(
            jsNumOr0(d.prices['زراعة']),
            900,
            reason: '${d.name}: سعر المعالجة الجديدة رافقها',
          );
        }
      },
    );

    test('مسح السعر (تفريغ الحقل) يزيله على الجهازين بلا بعث', () async {
      await seedBoth();
      a.setPrice('حشو', 120);
      await settle();
      expect(jsNumOr0(b.prices['حشو']), 120);

      b.setPrice('حشو', 0); // التفريغ = إزالة (سلوك _setSvcPrice)
      await settle();
      await settle();

      for (final d in [a, b]) {
        expect(
          d.prices.containsKey('حشو'),
          isFalse,
          reason: '${d.name}: الإزالة حتمية بلا بعث',
        );
      }
    });
  });

  // ═══ الواجهة — الحفظ بلا Enter وملء السعر في الرئيسية ═══

  group('الواجهة — حفظ السعر وملؤه', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m55w_'));
    tearDown(() {
      BrandColors.darkMode = false;
      tmp.deleteSync(recursive: true);
    });

    Map<String, Object?> config() => {
      'centerName': 'مركز الاختبار',
      'doctorPct': 50,
      'clinics': ['ع1'],
      'services': ['حشو', 'خلع'],
      'payments': ['كاش'],
      'labs': ['مخبر النور'],
      'servicePrices': {'حشو': 120, 'خلع': 80},
    };

    ProviderContainer container() => ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );

    Future<void> boot(WidgetTester tester) async {
      final c = container();
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', config());
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

    Map<String, Object?> readPrices() {
      final c = container();
      final v = c.read(reposProvider).settings.get('app.config');
      c.dispose();
      final cfg = v is Map ? v : const {};
      return cfg['servicePrices'] is Map
          ? Map<String, Object?>.from(cfg['servicePrices'] as Map)
          : <String, Object?>{};
    }

    testWidgets('كتابة السعر ثم الانتقال لحقل آخر تحفظه — بلا Enter', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await openGroup(tester, 'clinic');

      await tester.ensureVisible(find.byKey(const Key('svc-price-حشو')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('svc-price-حشو')), '175');
      // مغادرة الحقل بالانتقال لحقل آخر (لا Enter) — مسار فقد التركيز.
      await tester.ensureVisible(find.byKey(const Key('new-service-input')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('new-service-input')),
        warnIfMissed: false,
      );
      await settle(tester);

      expect(
        jsNumOr0(readPrices()['حشو']),
        175,
        reason: 'فقد التركيز حفظ السعر — Enter لم يعد شرطاً',
      );
    });

    testWidgets('كتابة السعر ثم الرجوع من الشاشة مباشرة تحفظه (شبكة الأمان)', (
      tester,
    ) async {
      await boot(tester);
      await tester.tap(find.byTooltip('الإعدادات'));
      await settle(tester);
      await openGroup(tester, 'clinic');

      await tester.ensureVisible(find.byKey(const Key('svc-price-خلع')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('svc-price-خلع')), '95');
      // رجوع فوري — لا Enter ولا لمسة أخرى: dispose يلتزم بما كُتب.
      // م92 — رجوعان (القسم ثم الشاشة) حتى نبلغ dispose الشاشة فعلاً.
      await tester.tap(
        find.byKey(const Key('settings-section-back')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.byType(BackButton).first, warnIfMissed: false);
      await settle(tester);

      expect(
        jsNumOr0(readPrices()['خلع']),
        95,
        reason: 'الرجوع المباشر لم يعد يضيع السعر',
      );
    });

    testWidgets('الرئيسية: تبديل المعالجة يملأ سعرها فوق سعر السابقة', (
      tester,
    ) async {
      await boot(tester);
      // م133 — نموذج الإدخال rec-* لم يبق على تبويب الرئيسية (صار
      // DailyIncomeScreen، م121+)؛ انتقل لورقة سفلية تُفتح بالزر العائم
      // Key('fab-add') (app_shell.dart)، كما في m8.
      await tester.tap(find.byKey(const Key('fab-add')), warnIfMissed: false);
      await settle(tester);

      // اختيار «حشو» ⇒ 120 (سلوك الملء الأصلي).
      await tester.tap(
        find.byKey(const Key('rec-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('حشو').last, warnIfMissed: false);
      await settle(tester);
      var amount = tester.widget<TextField>(
        find.byKey(const Key('rec-amount')),
      );
      expect(amount.controller!.text, '120');

      // التبديل إلى «خلع» ⇒ 80 يحل محل 120 (كان الحقل «غير فارغ» فيبقى
      // سعر المعالجة السابقة — علة م55).
      await tester.tap(
        find.byKey(const Key('rec-service')),
        warnIfMissed: false,
      );
      await settle(tester);
      await tester.tap(find.text('خلع').last, warnIfMissed: false);
      await settle(tester);
      amount = tester.widget<TextField>(find.byKey(const Key('rec-amount')));
      expect(
        amount.controller!.text,
        '80',
        reason: 'اختيار المعالجة يُظهر سعرها دائماً — ويبقى حراً للتعديل',
      );
    });
  });
}
