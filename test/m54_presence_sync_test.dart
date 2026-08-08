/// اختبار م54 — نضارة المزامنة بين جهازين:
///   • قاعدة الاستطلاع عادت لأصل المحرك (٣٠ ثانية) — كانت تُحقن بإعداد
///     syncMin (دقائق) فصار «الإيقاع السريع» ٥–٣٠ دقيقة والجهاز المستقبِل
///     لا يرى معالجةً أُضيفت على الجهاز الآخر إلا بعد دقائق طويلة.
///   • سقف الخمول قابل للحقن ويُقرأ حياً (يسري تغيير syncMin بلا إعادة
///     تشغيل)، ولا ينزل تحت القاعدة.
///   • ركلة «لحظة الحضور» (استئناف التطبيق / فتح الإعدادات) تجعل الجهاز
///     الثاني يلتقط معالجة الجهاز الأول فوراً — جهازان حقيقيان
///     (قاعدتا SQLite) عبر خادم بدلالات الخلفية.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class Device {
  Device(this.name, FakeSyncServer server, {int Function()? idleCapMs})
      : tmp = Directory.systemTemp.createTempSync('m54_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    engine = SyncEngine(
        SyncContext(db: db, repos: repos, transport: server),
        idleCapMs: idleCapMs);
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

  Set<String> list(String key) => <String>{
        for (final e in (config[key] is List ? config[key] as List : const []))
          '$e',
      };

  void dispose() {
    engine.stopEngine();
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  test('القاعدة الافتراضية = أصل المحرك (٣٠ث) لا دقائق syncMin', () {
    final server = FakeSyncServer();
    final d = Device('base', server);
    addTearDown(d.dispose);
    // الانتكاسة المصيدة: كانت القاعدة تُبنى من syncMin ‏(30 دقيقة
    // افتراضاً، أرضية 5) فصارت 300٬000–1٬800٬000 مللي ثانية.
    expect(d.engine.debugPollBaseMs, timerMs,
        reason: 'الإيقاع النشط ثلاثون ثانية — لا دقائق');
    expect(d.engine.debugIdleCapMs, idlePollMaxMs,
        reason: 'بلا حقن: سقف الخمول هو سقف الأصل (٥ دقائق)');
  });

  test('سقف الخمول يُقرأ حياً من الحاقن — تغيير الإعداد يسري بلا إعادة تشغيل',
      () {
    final server = FakeSyncServer();
    var capMin = 7;
    final d = Device('cap', server, idleCapMs: () => capMin * 60 * 1000);
    addTearDown(d.dispose);
    expect(d.engine.debugIdleCapMs, 7 * 60 * 1000);
    capMin = 12; // المستخدم عدّل «فاصل المزامنة» من الإعدادات
    expect(d.engine.debugIdleCapMs, 12 * 60 * 1000,
        reason: 'القراءة حية عند كل نبضة — لا لقطة مجمدة عند البناء');
  });

  test('ركلة الحضور: معالجة أُضيفت على A تظهر على B فور ركلته (بلا انتظار)',
      () async {
    final server = FakeSyncServer();
    final a = Device('a', server);
    final b = Device('b', server);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    a.repos.settings.set('app.config', {
      'centerName': 'مركز التقارب',
      'services': ['حشو'],
    });
    await a.sync();
    await b.sync();
    expect(b.list('services'), contains('حشو'));

    // A يضيف معالجة جديدة من الإعدادات ويدفعها.
    a.repos.settings.configAddItem(const ['services'], 'زراعة');
    await a.sync();

    // B «حضر» (استئناف من الخلفية / فتح شاشة الإعدادات) ⇒ kickSync(0)
    // — نفس المسار الذي تستدعيه kickPresenceSync — يلتقطها فوراً.
    b.engine.kickSync(0);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(b.list('services'), containsAll(const {'حشو', 'زراعة'}),
        reason: 'لحظة الحضور تكفي — لا انتظار نبضة الاستطلاع الدوري');
  });
}
