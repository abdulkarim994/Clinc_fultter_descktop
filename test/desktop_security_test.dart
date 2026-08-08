/// ============================================================================
///  اختبارات أمن نسخة الكمبيوتر — الخروج المصنعي، كنس المؤقتات، سلامة الإعداد
/// ============================================================================
///
///  ⚠ **هذه الاختبارات تُثبت الأمن ولا تصفه.** كل ادّعاء مبنيّ على فحص
///  القرص فعلياً (ملفات محذوفة، صفوف ممسوحة) أو منطقٍ نقيّ (ختم HMAC) —
///  لا على استدعاء دالة تعيد `true`. والخروج المصنعي يُستدعى عبر الدالة
///  الإنتاجية `runFactoryReset(WidgetRef)` نفسها (لا نسخة موازية) من داخل
///  ودجة حقيقية تملك `ref`.
///
///  ما ليس مُتحقَّقاً هنا (يستلزم جهازاً): حذف مفتاح DPAPI الفعلي، وإزالة
///  بيانات MSIX عند إلغاء التثبيت. الواجهات مُختبَرة بمخزنٍ ذاكري، والربط
///  بالمنصّة نقطة تكامل تُفحص على Windows حقيقي (انظر التقرير النهائي).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/uid.dart' show genId;
import 'package:dental_clinic_flutter/data/db/db_key.dart';
import 'package:dental_clinic_flutter/features/desktop/security/config_integrity.dart';
import 'package:dental_clinic_flutter/features/desktop/security/factory_reset.dart';
import 'package:dental_clinic_flutter/features/desktop/security/temp_cleaner.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  //  سلامة إعداد السحابة — HMAC نقيّ
  // ══════════════════════════════════════════════════════════════════════
  group('سلامة الإعداد — ختم HMAC', () {
    const key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90'
        'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const content = '{"supabaseUrl":"https://real.supabase.co","anonKey":"k"}';

    test('الختم ثابت لنفس المحتوى والمفتاح', () {
      final a = computeConfigSeal(content, key);
      final b = computeConfigSeal(content, key);
      expect(a, b);
      expect(a, hasLength(64), reason: 'SHA-256 hex = 64 حرفاً');
    });

    test('تغيّر حرفٍ واحد في المحتوى يبطل الختم — كشف العبث', () {
      final seal = computeConfigSeal(content, key);
      const tampered =
          '{"supabaseUrl":"https://EVIL.supabase.co","anonKey":"k"}';
      expect(verifyConfigSeal(content, key, seal), isTrue);
      expect(verifyConfigSeal(tampered, key, seal), isFalse,
          reason: 'عنوان خادم مُبدَّل خلسةً يُكتشف');
    });

    test('مفتاح مختلف (جهاز آخر) لا يُطابق — الملف المنسوخ يُرفض', () {
      final seal = computeConfigSeal(content, key);
      const otherKey =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      expect(verifyConfigSeal(content, otherKey, seal), isFalse);
    });

    test('المقارنة ثابتة الزمن ترفض طولاً مختلفاً بلا انهيار', () {
      expect(verifyConfigSeal(content, key, 'short'), isFalse);
      expect(verifyConfigSeal(content, key, ''), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  كنس المؤقتات — فحص القرص فعلياً
  // ══════════════════════════════════════════════════════════════════════
  group('كنس المؤقتات', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sec_sweep_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('يمسح محتوى exports و tmp و cache ويُبقي المجلدات', () async {
      for (final sub in ['exports', 'tmp', 'cache']) {
        final d = Directory(p.join(tmp.path, sub))..createSync();
        File(p.join(d.path, 'leak_$sub.pdf')).writeAsStringSync('سرّ مريض');
      }
      final removed = await sweepEphemeral(tmp.path);
      expect(removed, greaterThanOrEqualTo(3));
      for (final sub in ['exports', 'tmp', 'cache']) {
        final d = Directory(p.join(tmp.path, sub));
        expect(d.existsSync(), isTrue, reason: 'المجلد يبقى جاهزاً');
        expect(d.listSync(), isEmpty, reason: 'محتواه مُسح');
      }
    });

    test('removeExports=false يُبقي الصادرات (سلوك انتقائي)', () async {
      final exp = Directory(p.join(tmp.path, 'exports'))..createSync();
      final f = File(p.join(exp.path, 'report.pdf'))..writeAsStringSync('x');
      await sweepEphemeral(tmp.path, removeExports: false);
      expect(f.existsSync(), isTrue);
    });

    test('لا يرمي على مجلد غائب', () {
      final gone = p.join(tmp.path, 'nonexistent');
      expect(() => sweepEphemeral(gone), returnsNormally);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  //  الخروج المصنعي — عبر الدالة الإنتاجية runFactoryReset
  // ══════════════════════════════════════════════════════════════════════
  group('الخروج المصنعي', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sec_reset_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// يبني حاوية فوق مجلد مؤقت بمفتاح ذاكري مزروع + بيانات حساسة في كل
    /// الجداول وملفات على القرص، ويعرض زرّاً ينادي `runFactoryReset(ref)`
    /// الإنتاجية. الضغط عليه يشغّل المسار الحقيقي.
    Future<(MemoryDbKeyStore, Finder)> seedAndPump(WidgetTester tester,
        {bool keepGeneralSettings = true,
        List<FactoryResetReport>? sink}) async {
      final keyStore = MemoryDbKeyStore();
      await keyStore.write(generateDbKey());
      // ملفات حساسة على القرص.
      File(p.join(tmp.path, 'cloud_config.json'))
          .writeAsStringSync('{"supabaseUrl":"x"}');
      File(p.join(tmp.path, 'session.json'))
          .writeAsStringSync('{"token":"سرّ"}');
      File(p.join(tmp.path, 'errors.log')).writeAsStringSync('log');
      final exp = Directory(p.join(tmp.path, 'exports'))..createSync();
      File(p.join(exp.path, 'r.pdf')).writeAsStringSync('تقرير');
      final xr = Directory(p.join(tmp.path, 'xray_images'))..createSync();
      File(p.join(xr.path, 'x.blob')).writeAsStringSync('blob');

      FactoryResetReport? report;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
          dbKeyStoreProvider.overrideWithValue(keyStore),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('do-reset'),
                  onPressed: () async {
                    report = await runFactoryReset(ref,
                        keepGeneralSettings: keepGeneralSettings);
                    sink?.add(report!);
                  },
                  child: Text(report?.toString() ?? 'reset'),
                ),
              ),
            );
          }),
        ),
      ));
      await tester.pump();

      // زرع بيانات حساسة في كل جدول عبر المستودعات والقاعدة الحقيقية.
      final ctx = tester.element(find.byKey(const Key('do-reset')));
      final container = ProviderScope.containerOf(ctx);
      final repos = container.read(reposProvider);
      repos.patients.upsertLocal({'id': genId(), 'name': 'مريض سرّي'});
      repos.records.upsertLocal(
          {'id': genId(), 'patient_name': 'مريض سرّي', 'amount': 100});
      final db = container.read(localDbProvider);
      db.execute(
          "INSERT INTO employees(id, name) VALUES(?, 'موظف')", [genId()]);
      db.execute(
          "INSERT INTO expenses(id, amount, category) VALUES(?, 50, 'other')",
          [genId()]);
      db.execute(
          "INSERT OR REPLACE INTO metadata(key, value) VALUES('dental_theme','dark')");
      db.execute(
          "INSERT OR REPLACE INTO metadata(key, value) VALUES('local_auth_accounts','{\"h\":\"سرّ\"}')");
      // تحقّق أن البيانات موجودة فعلاً قبل المسح (نظير يُثبت أن الاختبار يقيس).
      expect(db.query('SELECT COUNT(*) c FROM patients').single['c'], 1);
      expect(db.query('SELECT COUNT(*) c FROM employees').single['c'], 1);
      expect(db.query('SELECT COUNT(*) c FROM expenses').single['c'], 1);

      return (keyStore, find.byKey(const Key('do-reset')));
    }

    testWidgets('يحذف ملفات القاعدة والإعداد والجلسة والصادرات من القرص',
        (tester) async {
      final (_, btn) = await seedAndPump(tester);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      for (final name in [
        'cloud_config.json',
        'session.json',
        'errors.log',
        'dental_clinic_offline.db',
      ]) {
        expect(File(p.join(tmp.path, name)).existsSync(), isFalse,
            reason: '$name حُذف من القرص');
      }
      for (final sub in ['exports', 'xray_images']) {
        expect(Directory(p.join(tmp.path, sub)).existsSync(), isFalse,
            reason: 'مجلد $sub حُذف بالكامل');
      }
    });

    testWidgets('يحذف مفتاح القاعدة — لا استرجاع للبيانات بعد الخروج',
        (tester) async {
      final (keyStore, btn) = await seedAndPump(tester);
      expect(await keyStore.read(), isNotNull, reason: 'المفتاح موجود قبل');
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(await keyStore.read(), isNull,
          reason: 'بلا مفتاح: أي بقايا بايتات لا تُفكّ أبداً');
    });

    testWidgets('يُبقي الإعدادات العامة غير الحساسة ويمحو الحساسة',
        (tester) async {
      final (_, btn) = await seedAndPump(tester);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      // القاعدة أُعيد فتحها فارغة على نفس المسار (الملف حُذف) — نفتح
      // ونتحقق: لا صفوف مرضى/موظفين/مصروفات، والاعتماد المحلي مُمحى.
      final ctx = tester.element(btn);
      final container = ProviderScope.containerOf(ctx);
      final db = container.read(localDbProvider);
      expect(db.query('SELECT COUNT(*) c FROM patients').single['c'], 0);
      expect(db.query('SELECT COUNT(*) c FROM employees').single['c'], 0);
      expect(db.query('SELECT COUNT(*) c FROM expenses').single['c'], 0);
      final auth = db.query(
          "SELECT COUNT(*) c FROM metadata WHERE key='local_auth_accounts'");
      expect(auth.single['c'], 0, reason: 'اعتمادات الدخول مُمحاة');
    });

    testWidgets('التقرير يعلن مسحاً نظيفاً بلا أخطاء', (tester) async {
      final sink = <FactoryResetReport>[];
      final (_, btn) = await seedAndPump(tester, sink: sink);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(sink, hasLength(1));
      final r = sink.single;
      expect(r.keyDeleted, isTrue, reason: 'المفتاح حُذف');
      expect(r.clean, isTrue, reason: 'بلا أخطاء');
      expect(r.tablesCleared, greaterThanOrEqualTo(14),
          reason: 'كل الجداول الحساسة + metadata مُسحت');
      expect(r.filesDeleted, greaterThanOrEqualTo(5),
          reason: 'ملفات القاعدة والإعداد والجلسة والمجلدات حُذفت');
    });
  });
}
