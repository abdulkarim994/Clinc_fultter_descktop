/// ============================================================================
///  Sync context — the wiring the JS modules reached via global imports
/// ============================================================================
///
///  The Vue sync layer was module-singletons bound to the app's global DB /
///  repositories / supabase client. The Dart port passes ONE explicit context
///  instead — trivially testable (two contexts = two devices in one process).
library;

import '../db/local_db.dart';
import '../repositories/repositories.dart';
import 'transport.dart';

class SyncContext {
  SyncContext({
    required this.db,
    required this.repos,
    required this.transport,
    bool Function()? isOnline,
    bool Function()? hasCloudImages,
  })  : isOnline = isOnline ?? (() => true),
        hasCloudImages = hasCloudImages ?? (() => false);

  final LocalDb db;
  final Repositories repos;
  final SyncTransport transport;

  /// Network gate (network.service.getIsOnline twin) — injectable for tests.
  bool Function() isOnline;

  /// م65 — هل عامل R2 مضبوط؟ حين يكون كذلك تُستثنى مصغّرات الأشعة من
  /// حمولة المزامنة (العامل يخدمها عبر `?v=thumb` ومسار الاسترجاع قائم)،
  /// فيُوفَّر نحو 96٪ من حجم صف الأشعة على قاعدة السحابة. وبلا R2 تبقى
  /// المصغّرة تسافر لأنها حينها السبيل الوحيد للمعاينة على جهاز آخر.
  /// يُمرَّر عبر السياق لا كعلم عام — فالسياق هو نمط الحقن المعتمد هنا.
  bool Function() hasCloudImages;

  String get deviceId => db.deviceId;
  String tick() => db.hlc.tick(db.deviceId);
  void receive(String? hlc) => db.hlc.receive(hlc);
}
