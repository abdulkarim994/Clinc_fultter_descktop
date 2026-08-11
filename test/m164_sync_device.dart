/// م164 — عدة جهازي مزامنة للاختبار: قاعدتان حقيقيتان وخادم مزيف مشترك
/// (نفس نمط m2b حرفياً) مع رقصة التقارب القياسية بأربع دورات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/engine.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:path/path.dart' as p;

import 'helpers/fake_sync_server.dart';

class SyncDevice {
  SyncDevice(this.name, FakeSyncServer server)
      : tmp = Directory.systemTemp.createTempSync('m164_${name}_') {
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    repos = Repositories(db);
    ctx = SyncContext(db: db, repos: repos, transport: server);
    engine = SyncEngine(ctx);
  }

  final String name;
  final Directory tmp;
  late final LocalDb db;
  late final Repositories repos;
  late final SyncContext ctx;
  late final SyncEngine engine;

  Future<void> sync() => engine.runCycle('test');

  void dispose() {
    db.close();
    tmp.deleteSync(recursive: true);
  }
}

/// خادم + جهازان — إنشاءً وتفكيكاً وتقارباً بأربع دورات.
class FakeServerBundle {
  FakeServerBundle() {
    syncFlags.resetForTest();
    server = FakeSyncServer();
    a = SyncDevice('A', server);
    b = SyncDevice('B', server);
  }

  late final FakeSyncServer server;
  late final SyncDevice a;
  late final SyncDevice b;

  Future<void> converge() async {
    await a.sync();
    await b.sync();
    await a.sync();
    await b.sync();
  }

  void dispose() {
    a.dispose();
    b.dispose();
    syncFlags.resetForTest();
  }
}
