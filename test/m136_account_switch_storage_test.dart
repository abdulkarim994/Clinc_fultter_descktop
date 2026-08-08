/// اختبارات م136 (المرحلة أ) — إصلاح تسريب تبديل الحساب في التخزين والرخصة،
/// وبذر الأساس الخادمي كي يظهر حسابٌ ممتلئ ممتلئاً فور الدخول على جهازٍ نظيف.
library;

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show StorageTransport;
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart'
    show wipeAllAccountData;
import 'package:dental_clinic_flutter/features/xrays/storage_meter.dart';
import 'package:flutter_test/flutter_test.dart';

/// خادم تخزين مزيّف بحصةٍ واستهلاكٍ قابلين للضبط.
class _Cloud implements StorageTransport {
  _Cloud({required this.quota, required this.used});
  int quota, used;
  @override
  Future<Map<String, Object?>> getMyStorage() async => {
    'used_bytes': used,
    'file_count': 0,
    'quota_bytes': quota,
  };
  @override
  Future<Map<String, Object?>> reportMyStorage(int u, int f) async => {
    'used_bytes': u,
    'file_count': f,
    'quota_bytes': quota,
  };
}

String? _meta(LocalDb db, String key) {
  final row = db.queryFirst('SELECT value FROM metadata WHERE key = ?', [key]);
  return row?['value'] as String?;
}

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.open(':memory:'));
  tearDown(() => db.close());

  group('م136/أ — بذر الأساس الخادمي (جوهر الثغرة)', () {
    test('حسابٌ ممتلئ على الخادم يُحجب فور الدخول رغم خريطةٍ محلية فارغة',
        () async {
      // الجهاز نظيف (لا خريطة أحجام محلية) لكن الحساب ممتلئ على الخادم.
      final m = StorageMeter(db, cloud: _Cloud(quota: 1000, used: 1000));
      expect(m.usedBytes, 0); // قبل البذر: محليٌّ صفر (هذه كانت الثغرة)
      await m.refreshFromServer();
      expect(m.usedBytes, 1000); // بعد البذر: ممتلئ
      expect(m.check(1).allowed, isFalse); // الرفع محجوب فوراً
      expect(m.level, StorageLevel.full);
    });

    test('الاستهلاك الفعّال = الأكبر بين الخادمي والمحلي، والرفع يتراكم فوقه',
        () async {
      final m = StorageMeter(db, cloud: _Cloud(quota: 1000, used: 500));
      await m.refreshFromServer();
      expect(m.usedBytes, 500);
      m.addUpload('x', 300); // 500 (خادمي) + 300 (هذا الجهاز)
      expect(m.usedBytes, 800);
      expect(m.check(200).allowed, isTrue);
      expect(m.check(201).allowed, isFalse);
    });

    test('الحذف ينقص الأساس الخادمي بدقة', () async {
      final m = StorageMeter(db, cloud: _Cloud(quota: 1000, used: 0));
      await m.refreshFromServer();
      m.addUpload('a', 400);
      expect(m.usedBytes, 400);
      m.removeKey('a');
      expect(m.usedBytes, 0);
    });

    test('بذرٌ لاحق بقيمة أصغر لا يُنقِص المجموع المحلي (تحفّظ آمن)', () async {
      final cloud = _Cloud(quota: 10000, used: 0);
      final m = StorageMeter(db, cloud: cloud);
      m.addUpload('a', 900); // محليّ 900، خادمي 900
      cloud.used = 100; // الخادم متأخّر (تقرير معلّق)
      await m.refreshFromServer();
      expect(m.usedBytes, 900); // يبقى الأكبر — لا يُفتح الرفع كذباً
    });
  });

  group('م136/ب — لا تسريب عند تبديل الحساب', () {
    test('wipeAllAccountData يمسح مفاتيح التخزين والرخصة', () {
      // حساب أ: حصة كبيرة واستهلاك ورخصة مخبَّأة.
      db.execute(
        "INSERT OR REPLACE INTO metadata(key,value,updated_at) "
        "VALUES ('xray.storage.quota_bytes','999999999',datetime('now'))",
      );
      db.execute(
        "INSERT OR REPLACE INTO metadata(key,value,updated_at) "
        "VALUES ('xray.storage.server_used','5000',datetime('now'))",
      );
      db.execute(
        "INSERT OR REPLACE INTO metadata(key,value,updated_at) "
        "VALUES ('xray.storage.sizes','{\"k\":5000}',datetime('now'))",
      );
      db.execute(
        "INSERT OR REPLACE INTO metadata(key,value,updated_at) "
        "VALUES ('license.cache','{\"status\":\"active\"}',datetime('now'))",
      );

      wipeAllAccountData(db);

      // كلها مُسحت — فلا يرث الحساب الجديد حصة أ ولا رخصته.
      expect(_meta(db, 'xray.storage.quota_bytes'), isNull);
      expect(_meta(db, 'xray.storage.server_used'), isNull);
      expect(_meta(db, 'xray.storage.sizes'), isNull);
      expect(_meta(db, 'license.cache'), isNull);
    });

    test('بعد المسح: مقياسٌ جديد يبدأ نظيفاً بالحصة الافتراضية', () {
      db.execute(
        "INSERT OR REPLACE INTO metadata(key,value,updated_at) "
        "VALUES ('xray.storage.server_used','5000',datetime('now'))",
      );
      wipeAllAccountData(db);
      final m = StorageMeter(db);
      expect(m.usedBytes, 0);
      expect(m.quotaBytes, kDefaultQuotaBytes);
    });
  });
}
