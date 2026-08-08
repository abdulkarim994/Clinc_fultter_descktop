/// اختبارات م137 (المرحلة ب) — قراءة حدّ العيادات من لقطة الترخيص وتخبئتها،
/// وهو مصدر الحدّ الذي تفرضه شاشتا الإعداد والإعدادات.
library;

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show LicenseTransport;
import 'package:dental_clinic_flutter/features/auth/license_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cloud implements LicenseTransport {
  _Cloud(this.payload);
  Map<String, Object?> payload;
  @override
  Future<Map<String, Object?>> verifyLicense(Map<String, Object?> d) async =>
      payload;
  @override
  Future<Map<String, Object?>> activateCode(
    String code,
    Map<String, Object?> d,
  ) async => payload;

  @override
  Future<Map<String, Object?>> getMySubscription() async => payload;

  @override
  Future<List<Map<String, Object?>>> listPublicPlans() async => const [];
}

Map<String, Object?> _payload({
  int maxClinics = 1,
  int maxDevices = 1,
  bool enforce = false,
  String status = 'active',
}) => {
  'enforce': enforce,
  'status': status,
  'plan_code': 'basic',
  'features': {
    'max_clinics': maxClinics,
    'max_devices': maxDevices,
    'storage_mb': 1024,
  },
  'device_allowed': true,
  'expires_at': null,
  'server_time': DateTime.now().toUtc().toIso8601String(),
  'grace_days': 7,
};

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.open(':memory:'));
  tearDown(() => db.close());

  group('م137 — حدود الميزات في اللقطة', () {
    test('اللقطة تقرأ max_clinics وmax_devices من features', () async {
      final svc = LicenseService(
        db,
        cloud: _Cloud(_payload(maxClinics: 3, maxDevices: 2)),
      );
      final s = await svc.evaluate();
      expect(s.maxClinics, 3);
      expect(s.maxDevices, 2);
      expect(s.deviceAllowed, isTrue);
    });

    test('غياب features ⇒ صفر (بلا حدّ)', () async {
      final svc = LicenseService(db, cloud: _Cloud({'enforce': false}));
      final s = await svc.evaluate();
      expect(s.maxClinics, 0);
      expect(s.maxDevices, 0);
    });

    test('cachedMaxClinics متزامن من آخر تحقق ناجح', () async {
      final svc = LicenseService(db, cloud: _Cloud(_payload(maxClinics: 5)));
      expect(svc.cachedMaxClinics(), 0); // لا تخبئة بعد
      await svc.evaluate(); // يخبّئ الحمولة
      expect(svc.cachedMaxClinics(), 5); // صار متاحاً متزامناً
    });

    test('reset يمسح التخبئة فيعود الحد صفراً', () async {
      final svc = LicenseService(db, cloud: _Cloud(_payload(maxClinics: 4)));
      await svc.evaluate();
      expect(svc.cachedMaxClinics(), 4);
      svc.reset();
      expect(svc.cachedMaxClinics(), 0);
    });
  });
}
