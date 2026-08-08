/// اختبارات م135 — خدمة الترخيص (المرحلة ٥): الحسم، الإجبار، الانتهاء،
/// فترة السماح دون اتصال، ودفاع تلاعب الساعة.
library;

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart'
    show LicenseTransport;
import 'package:dental_clinic_flutter/features/auth/license_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// خادم ترخيص مزيّف قابل للبرمجة.
class FakeLicenseCloud implements LicenseTransport {
  FakeLicenseCloud(this.payload, {this.throwOnVerify = false});
  Map<String, Object?> payload;
  bool throwOnVerify;
  int verifyCalls = 0;
  (String, Map<String, Object?>)? lastActivate;

  @override
  Future<Map<String, Object?>> verifyLicense(
    Map<String, Object?> device,
  ) async {
    verifyCalls++;
    if (throwOnVerify) throw Exception('offline');
    return payload;
  }

  @override
  Future<Map<String, Object?>> activateCode(
    String code,
    Map<String, Object?> device,
  ) async {
    lastActivate = (code, device);
    if (code == 'BAD') throw Exception('invalid activation code');
    return payload;
  }

  @override
  Future<Map<String, Object?>> getMySubscription() async => payload;

  @override
  Future<List<Map<String, Object?>>> listPublicPlans() async => const [];
}

Map<String, Object?> _payload({
  bool enforce = true,
  String status = 'active',
  String? expiresAt,
  String? serverTime,
  int graceDays = 7,
}) => {
  'enforce': enforce,
  'status': status,
  'plan_code': 'basic',
  'expires_at': expiresAt,
  'server_time': serverTime ?? DateTime.now().toUtc().toIso8601String(),
  'grace_days': graceDays,
};

void main() {
  late LocalDb db;
  setUp(() => db = LocalDb.open(':memory:'));
  tearDown(() => db.close());

  group('م135/أ — الإجبار مطفأ ⇒ اسمح دائماً', () {
    test('حتى لو الحالة منتهية، الإجبار المطفأ يسمح', () async {
      final svc = LicenseService(
        db,
        cloud: FakeLicenseCloud(_payload(enforce: false, status: 'expired')),
      );
      final s = await svc.evaluate();
      expect(s.allowed, isTrue);
      expect(s.result, LicenseGateResult.allowed);
    });

    test('بلا سحابة (وضع محلي) ⇒ اسمح', () async {
      final s = await LicenseService(db).evaluate();
      expect(s.allowed, isTrue);
    });
  });

  group('م135/ب — الإجبار مفعّل: الحسم بالحالة', () {
    Future<LicenseGateResult> r(String status, {String? expires}) async {
      final svc = LicenseService(
        db,
        cloud: FakeLicenseCloud(_payload(status: status, expiresAt: expires)),
      );
      return (await svc.evaluate()).result;
    }

    test('active/trial ⇒ مسموح', () async {
      expect(await r('active'), LicenseGateResult.allowed);
      expect(await r('trial'), LicenseGateResult.allowed);
    });
    test('expired/none ⇒ تفعيل', () async {
      expect(await r('expired'), LicenseGateResult.needsActivation);
      expect(await r('none'), LicenseGateResult.needsActivation);
    });
    test('banned/frozen ⇒ حالتاهما', () async {
      expect(await r('banned'), LicenseGateResult.banned);
      expect(await r('frozen'), LicenseGateResult.frozen);
    });
    test('active لكن التاريخ ماضٍ ⇒ تفعيل (التاريخ يحكم)', () async {
      final past = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      expect(
        await r('active', expires: past),
        LicenseGateResult.needsActivation,
      );
    });
  });

  group('م135/ج — فترة السماح دون اتصال', () {
    test('تخبئة حديثة ثم انقطاع ⇒ يُسمح ضمن السماح', () async {
      // تحققٌ ناجح أولاً (يخبّئ active + grace=7).
      final cloud = FakeLicenseCloud(_payload(status: 'active', graceDays: 7));
      final svc = LicenseService(db, cloud: cloud);
      expect((await svc.evaluate()).allowed, isTrue);

      // ثم انقطاع: الخادم يرمي — نسقط للتخبئة، وهي ضمن السماح.
      cloud.throwOnVerify = true;
      final s = await svc.evaluate();
      expect(s.allowed, isTrue);
      expect(s.fromCache, isTrue);
    });

    test('تجاوز السماح ⇒ offlineExpired', () async {
      // نخبّئ عبر تحقق ناجح، لكن ساعة الجهاز تُزوَّر للأمام لتجاوز السماح.
      var now = DateTime(2026, 1, 1);
      final cloud = FakeLicenseCloud(
        _payload(
          status: 'active',
          graceDays: 3,
          serverTime: DateTime(2026, 1, 1).toUtc().toIso8601String(),
        ),
      );
      final svc = LicenseService(db, cloud: cloud, now: () => now);
      expect((await svc.evaluate()).allowed, isTrue);

      cloud.throwOnVerify = true;
      now = DateTime(2026, 1, 5); // بعد ٤ أيام والسماح ٣
      final s = await svc.evaluate();
      expect(s.result, LicenseGateResult.offlineExpired);
    });
  });

  group('م135/د — دفاع تلاعب الساعة', () {
    test('إرجاع ساعة الجهاز خلف آخر وقت خادمٍ ⇒ clockTampered', () async {
      var now = DateTime(2026, 6, 1);
      final cloud = FakeLicenseCloud(
        _payload(
          status: 'active',
          serverTime: DateTime(2026, 6, 1).toUtc().toIso8601String(),
        ),
      );
      final svc = LicenseService(db, cloud: cloud, now: () => now);
      expect((await svc.evaluate()).allowed, isTrue); // يختم آخر وقت خادم

      // المستخدم يرجع ساعة الجهاز شهراً للوراء (تمديد اشتراكٍ منتهٍ حيلةً).
      now = DateTime(2026, 5, 1);
      cloud.throwOnVerify = true; // أوفلاين كي لا يصحّح الخادمُ الساعة
      final s = await svc.evaluate();
      expect(s.result, LicenseGateResult.clockTampered);
    });
  });

  group('م135/هـ — التفعيل بالكود', () {
    test('كود صحيح ⇒ لقطة مسموحة + مرّر الكود للخادم', () async {
      final cloud = FakeLicenseCloud(_payload(status: 'active'));
      final svc = LicenseService(db, cloud: cloud);
      final s = await svc.activate('DENT-AAAA-BBBB-CCCC');
      expect(s.allowed, isTrue);
      expect(cloud.lastActivate!.$1, 'DENT-AAAA-BBBB-CCCC');
    });

    test('كود خاطئ ⇒ LicenseException برسالة عربية', () async {
      final svc = LicenseService(db, cloud: FakeLicenseCloud(_payload()));
      expect(
        () => svc.activate('BAD'),
        throwsA(
          isA<LicenseException>().having(
            (e) => e.message,
            'msg',
            contains('غير صحيح'),
          ),
        ),
      );
    });

    test('بلا سحابة ⇒ التفعيل يرمي (يتطلّب اتصالاً)', () async {
      expect(
        () => LicenseService(db).activate('X'),
        throwsA(isA<LicenseException>()),
      );
    });
  });
}
