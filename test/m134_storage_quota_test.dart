/// اختبارات م134 — مقياس حصة التخزين (المرحلة ٣): عدّاد خريطة الأحجام،
/// العتبات، الحجب عند الامتلاء، والحارس في خط أنابيب الرفع.
library;

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show StorageTransport;
import 'package:dental_clinic_flutter/features/xrays/storage_meter.dart';
import 'package:flutter_test/flutter_test.dart';

/// خادم تخزين مزيّف — حصة قابلة للضبط + سجلّ تبليغ.
class FakeStorageCloud implements StorageTransport {
  FakeStorageCloud({this.quota = 200 * 1024 * 1024, this.serverUsed = 0});
  int quota;
  int serverUsed;
  final reports = <(int, int)>[];

  @override
  Future<Map<String, Object?>> getMyStorage() async => {
    'used_bytes': serverUsed,
    'file_count': 0,
    'quota_bytes': quota,
  };

  @override
  Future<Map<String, Object?>> reportMyStorage(
    int usedBytes,
    int fileCount,
  ) async {
    reports.add((usedBytes, fileCount));
    return {
      'used_bytes': usedBytes,
      'file_count': fileCount,
      'quota_bytes': quota,
    };
  }
}

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.open(':memory:'));
  tearDown(() => db.close());

  group('م134/أ — عدّاد خريطة الأحجام', () {
    test('الإضافة تجمع والحذف ينقص بدقة، والمفتاح نفسه لا يتضاعف', () {
      final m = StorageMeter(db);
      m.addUpload('k1', 1000);
      m.addUpload('k2', 2000);
      expect(m.usedBytes, 3000);
      expect(m.fileCount, 2);

      // إعادة المفتاح نفسه (إعادة رفع/توفيق) لا تضاعف.
      m.addUpload('k1', 1000);
      expect(m.usedBytes, 3000);
      expect(m.fileCount, 2);

      m.removeKey('k1');
      expect(m.usedBytes, 2000);
      expect(m.fileCount, 1);

      // حذف مفتاح غير موجود لا يؤثر.
      m.removeKey('ghost');
      expect(m.usedBytes, 2000);
    });

    test('يبقى عبر إعادة الفتح (metadata دائم)', () {
      StorageMeter(db).addUpload('k1', 5000);
      expect(StorageMeter(db).usedBytes, 5000);
    });

    test('reset يمسح كل شيء', () {
      final m = StorageMeter(db)..addUpload('k1', 5000);
      m.reset();
      expect(m.usedBytes, 0);
      expect(m.fileCount, 0);
    });
  });

  group('م134/ب — العتبات والحجب', () {
    test('العتبات على حصةٍ مضبوطة صغيرة', () async {
      final cloud = FakeStorageCloud(quota: 1000);
      final m = StorageMeter(db, cloud: cloud);
      await m.refreshQuota(); // يخبّئ 1000
      expect(m.quotaBytes, 1000);

      m.addUpload('a', 790);
      expect(m.level, StorageLevel.ok); // 79٪
      m.addUpload('b', 20); // 81٪
      expect(m.level, StorageLevel.warn80);
      m.addUpload('c', 100); // 91٪
      expect(m.level, StorageLevel.warn90);
      m.addUpload('d', 90); // 100٪
      expect(m.level, StorageLevel.full);
    });

    test('check يمنع ما يتجاوز الحصة ويسمح بما يسعها تماماً', () async {
      final m = StorageMeter(db, cloud: FakeStorageCloud(quota: 1000));
      await m.refreshQuota();
      m.addUpload('a', 900);
      expect(m.check(100).allowed, isTrue); // 900+100=1000 ✓
      expect(m.check(101).allowed, isFalse); // يتجاوز
      expect(m.check(100).remainingBytes, 100);
    });
  });

  group('م134/ج — الحصة من الخادم والتبليغ', () {
    test('refreshQuota يخبّئ الحصة، وبلا سحابة تبقى الافتراضية', () async {
      expect(StorageMeter(db).quotaBytes, kDefaultQuotaBytes);
      final m = StorageMeter(db, cloud: FakeStorageCloud(quota: 5 << 20));
      await m.refreshQuota();
      expect(m.quotaBytes, 5 << 20);
    });

    test('reportUp يبلّغ القياس الحالي', () async {
      final cloud = FakeStorageCloud(quota: 1 << 20);
      final m = StorageMeter(db, cloud: cloud);
      m.addUpload('a', 111);
      m.addUpload('b', 222);
      await m.reportUp();
      expect(cloud.reports.last, (333, 2));
    });

    test('فشل الشبكة لا يكسر — يبقى المخبَّأ', () async {
      final m = StorageMeter(db, cloud: _ThrowingCloud());
      await m.refreshQuota(); // لا يرمي
      expect(m.quotaBytes, kDefaultQuotaBytes);
      await m.reportUp(); // لا يرمي
    });
  });

  group('م134/د — humanBytesAr', () {
    test('تدرّج عربي', () {
      expect(humanBytesAr(512), '512 ب');
      expect(humanBytesAr(2048), '2.0 ك.ب');
      expect(humanBytesAr(5 << 20), '5.0 م.ب');
    });
  });
}

/// سحابة ترمي دائماً — لاختبار الفشل الآمن.
class _ThrowingCloud implements StorageTransport {
  @override
  Future<Map<String, Object?>> getMyStorage() async => throw Exception('net');
  @override
  Future<Map<String, Object?>> reportMyStorage(int u, int f) async =>
      throw Exception('net');
}
