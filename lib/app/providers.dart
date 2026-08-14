/// ============================================================================
///  التوصيلات المركزية (Riverpod) — قاعدة، مستودعات، محرك، مصادقة، إعدادات
/// ============================================================================
library;

import 'dart:io' show Directory;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/auth/auth_contracts.dart' show SdkSessionBridge;
import '../core/error_log.dart' show recordError;
import '../core/app_build.dart' show kAppStage;
import '../data/cloud/cloud_config.dart';
import '../data/cloud/gotrue_client.dart';
import '../data/cloud/session_store.dart' show SessionStore;
import '../data/net/network_status.dart';
import '../data/rates/rate_snapshot.dart' show ratesFeatureEnabled;
import '../data/net/reconnect_kick.dart';
import '../features/auth/onboarding_service.dart';
import '../features/auth/oauth_signin.dart';
import '../features/auth/license_service.dart';
import '../data/cloud/r2_client.dart';
import '../data/cloud/supabase_auth_service.dart';
import '../data/cloud/supabase_transport.dart';
import '../data/db/blob_vault.dart' show closeVaultsIn;
import '../data/db/db_boot.dart' show kDbFileName;
import '../data/db/db_key.dart' show DbKeyStore, MemoryDbKeyStore;
import '../data/db/local_db.dart';
import '../data/repositories/repositories.dart';
import '../data/sync/archive/cold_archive.dart';
import '../data/sync/audit_push.dart' show AuditPusher, AuditTransport;
import '../data/sync/context.dart';
import '../data/sync/engine.dart';
import '../data/sync/retention.dart';
import '../data/sync/fake_server.dart';
import '../data/sync/feature_flags.dart' show syncFlags;
import '../data/sync/transport.dart';
import '../features/appointments/appointments_tab.dart' show apptRevProvider;
import '../features/auth/auth_service.dart';
import '../features/auth/idle_lock.dart'
    show storeLockVerifier, clearLockVerifier;
import '../features/auth/pin_setup.dart' show hasPinVerifier;
import '../features/records/tooth_notation.dart'
    show NotationSystem, notationSystemFromConfig;
import '../features/auth/account_admin.dart';
import '../features/patients/audit_trail.dart' show AuditAction, recordAudit;
import '../features/finance/finance_screen.dart' show financeRevProvider;
import '../features/patients/patients_tab.dart' show patientsRevProvider;
import '../features/queue/queue_screen.dart'
    show queueRevProvider, queueViewProvider;
import '../features/xrays/storage_meter.dart';
import '../features/xrays/xray_pipeline.dart';
import '../features/xrays/xray_store.dart';

/// مسار مجلد البيانات — يُحقن عند الإقلاع (التطبيق: مجلد الدعم؛ الاختبارات: مؤقت).
final dbDirProvider = Provider<String>(
  (ref) => throw UnimplementedError('dbDirProvider must be overridden'),
);

/// نبضة استبدال القاعدة (الترحيل): زيادتها تعيد فتح القاعدة وكل ما فوقها —
/// نمط النبضات المعتمد في المشروع بدل invalidate اليدوي (يتجنب إعادة الدخول
/// أثناء البناء).
final dbEpochProvider = StateProvider<int>((ref) => 0);

/// مفتاح تشفير القاعدة — يُحقن عند الإقلاع بعد حسمه من مخزن النظام.
///
/// `null` يعني «افتح بلا تشفير»، ولا يحدث إلا في الاختبارات أو مع علم
/// البناء `DB_PLAINTEXT` الصريح. الافتراض هنا `null` كي تبقى الاختبارات
/// القائمة كلها عاملةً بلا تعديل سطر — ومسارُ الإنتاج يتجاوزه في `main`.
final dbEncryptionKeyProvider = Provider<String?>((ref) => null);

/// مخزن مفتاح القاعدة في مخزن أسرار النظام (Keystore/DPAPI). الافتراض
/// [MemoryDbKeyStore] كي تبقى الاختبارات بلا منصّة عاملةً؛ ومسارُ الإنتاج
/// يتجاوزه بـ[SecureDbKeyStore] في الإقلاع. يُقرأ في مسار «الخروج المصنعي»
/// لسطح المكتب لحذف مفتاح القاعدة نهائياً — انظر `factory_reset.dart`.
final dbKeyStoreProvider =
    Provider<DbKeyStore>((ref) => MemoryDbKeyStore());

final localDbProvider = Provider<LocalDb>((ref) {
  ref.watch(dbEpochProvider);
  final dir = ref.watch(dbDirProvider);
  // م18 — تمرير علم الهوية الهاتفية إلى هجرات الفتح: بناء الإنتاج يمرر
  // ‎--dart-define=PHONE_IDENTITY=1‎ (applyBuildTimeFlags قبل أي بناء)
  // وبياناته مكتوبة بمفاتيح p:هاتف:اسم — بدون التمرير لا تعمل هجرة
  // المرحلة A أبداً فتنفصم هوية المرضى عن الخلفية.
  final db = LocalDb.open(
    p.join(dir, kDbFileName),
    phoneIdentityEnabled: syncFlags.phoneIdentity,
    // م83 — التشفير عند السكون. المفتاح محسومٌ في الإقلاع قبل هذه النقطة،
    // و`PRAGMA key` يُصدَر أول أمر بعد الفتح داخل `openBootstrappedDb`.
    encryptionKey: ref.watch(dbEncryptionKeyProvider),
  );
  ref.onDispose(db.close);
  return db;
});

final reposProvider = Provider<Repositories>(
  (ref) => Repositories(ref.watch(localDbProvider)),
);

// ── الإعداد السحابي (م5) ────────────────────────────────────────────────────

/// نبضة إعادة قراءة للإعداد السحابي (تزيد بعد حفظه من الإعدادات).
final cloudConfigRevProvider = StateProvider<int>((ref) => 0);

/// إعداد Supabase/R2 — null = الوضع المحلي (الاختبارات كلها والافتراضي).
final cloudConfigProvider = Provider<CloudConfig?>((ref) {
  ref.watch(cloudConfigRevProvider);
  return loadCloudConfig(ref.watch(dbDirProvider));
});

final gotrueClientProvider = Provider<GotrueClient?>((ref) {
  final cfg = ref.watch(cloudConfigProvider);
  if (cfg == null) return null;
  return GotrueClient(baseUrl: cfg.supabaseUrl, anonKey: cfg.anonKey);
});

/// م88 — مخزن جلسة كلمة المرور. `null` = الافتراض التاريخي (ملف
/// `session.json`) وهو وضع الاختبارات كلها؛ والإقلاع السحابي الحقيقي
/// يتجاوزه بالمخزن الآمن المحمَّل مسبقاً (Keystore/DPAPI).
final sessionStoreProvider = Provider<SessionStore?>((ref) => null);

/// م88 — جسر جلسة الحزمة الرسمية (دخول Google). `null` = لا حزمة مهيأة
/// (الاختبارات والوضع المحلي)؛ يُتجاوز في الإقلاع السحابي بعد
/// `Supabase.initialize`، وبمزيّفٍ في اختبارات المسار.
final sdkSessionBridgeProvider = Provider<SdkSessionBridge?>((ref) => null);

/// خدمة مصادقة Supabase — تُبنى فقط في الوضع السحابي.
final supabaseAuthProvider = Provider<SupabaseAuthService?>((ref) {
  final client = ref.watch(gotrueClientProvider);
  if (client == null) return null;
  final svc = SupabaseAuthService(
    client: client,
    dbDir: ref.watch(dbDirProvider),
    store: ref.watch(sessionStoreProvider),
    sdk: ref.watch(sdkSessionBridgeProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// عميل عامل R2 — null عندما لا يوجد عنوان عامل.
/// عميل R2 — بواجهته المجردة XrayRemote كي تستطيع الاختبارات تبديله
/// بمزيّف (المسار الأونلاين لخط الأنابيب والمسترجِع).
final r2ClientProvider = Provider<XrayRemote?>((ref) {
  final cfg = ref.watch(cloudConfigProvider);
  final auth = ref.watch(supabaseAuthProvider);
  if (cfg == null || !cfg.hasImages || auth == null) return null;
  return R2Client(
    workerUrl: cfg.r2WorkerUrl,
    accessToken: auth.validAccessToken,
  );
});

/// م93 — مدير الحساب السحابي (كلمة المرور + حذف الحساب). `null` في الوضع
/// المحلي (بلا Supabase) فلا يظهر قسم «إعدادات الحساب» أصلاً.
final accountAdminProvider = Provider<AccountAdmin?>((ref) {
  final client = ref.watch(gotrueClientProvider);
  final auth = ref.watch(supabaseAuthProvider);
  if (client == null || auth == null) return null;
  final state = ref.watch(authProvider);
  final email = state is SignedIn ? state.user.email : '';
  return AccountAdmin(
    client: client,
    accessToken: auth.validAccessToken,
    email: email,
    // تطهير R2: تعداد كل مفاتيح الصور المحلية المعروفة وحذفها أفضلَ جهد.
    purgeImages: () async {
      final remote = ref.read(r2ClientProvider);
      if (remote == null) return;
      final db = ref.read(localDbProvider);
      final rows = db.query(
        "SELECT DISTINCT file_key FROM xrays "
        "WHERE file_key IS NOT NULL AND file_key != ''",
        const [],
      );
      for (final r in rows) {
        final key = '${r['file_key'] ?? ''}';
        if (key.isEmpty) continue;
        try {
          await remote.delete(key); // 404/410 = نجاح («زال أصلاً»)
        } catch (_) {
          /* أفضل جهد — الحساب زال من المصدر */
        }
      }
    },
    // مسحٌ محليّ كامل + خروج: نفس مسار مسح تبديل الحساب حرفياً.
    wipeLocal: () => ref.read(authProvider.notifier).deleteLocalAndLogout(),
  );
});

/// ناقل المزامنة — SupabaseTransport في الوضع السحابي، وإلا الخادم المحلي
/// المزيف (الذي أثبت العقد نفسه في اختبارات التقارب).
final transportProvider = Provider<SyncTransport>((ref) {
  final cfg = ref.watch(cloudConfigProvider);
  final auth = ref.watch(supabaseAuthProvider);
  if (cfg != null && auth != null) {
    return SupabaseTransport(
      baseUrl: cfg.supabaseUrl,
      anonKey: cfg.anonKey,
      accessToken: auth.validAccessToken,
      onUnauthorized: auth.forceRefresh,
    );
  }
  return FakeSyncServer();
});

/// م134 — مقياس حصة التخزين (المرحلة ٣). يمرّر قناة الخادم إن كان النقل
/// يدعمها (SupabaseTransport)؛ وإلا فالمقياس يعمل محلياً بحصةٍ افتراضية.
final storageMeterProvider = Provider<StorageMeter>((ref) {
  final t = ref.watch(transportProvider);
  return StorageMeter(
    ref.watch(localDbProvider),
    cloud: t is StorageTransport ? t as StorageTransport : null,
  );
});

/// م135 — خدمة الترخيص (المرحلة ٥). بلا سحابة (وضع محلي) القناة null
/// فتُسمح كل الأحكام — سلوك الاختبارات والوضع المحلي بلا تغيير.
final licenseServiceProvider = Provider<LicenseService>((ref) {
  final t = ref.watch(transportProvider);
  return LicenseService(
    ref.watch(localDbProvider),
    cloud: t is LicenseTransport ? t as LicenseTransport : null,
  )..appVersion = kAppStage;
});

// ── الشبكة الموحدة (م25 — توأم network.service.js) ─────────────────────────

/// حالة الاتصال الحية — «متصل الآن/غير متصل» في الهيدر وبوابة المحرك.
/// تُغذّى من خدمة NetworkStatus (وصلة + تأكيد وصول) — لا تُكتب من غيرها.
final onlineProvider = StateProvider<bool>((ref) => true);

/// خدمة الشبكة الموحدة: حالة الوصلة (connectivity_plus) + تأكيد وصول
/// حقيقي بطلب HEAD إلى Supabase (مهلة 5 ثوانٍ، دورية 15 ثانية) — لأن
/// حالة الوصلة تكذب على أندرويد (واي-فاي بلا إنترنت). في الوضع المحلي
/// بلا خلفية: الوصلة تكفي (سلوك الأصل عند غياب SUPABASE_URL).
final networkStatusProvider = Provider<NetworkStatus>((ref) {
  final cfg = ref.watch(cloudConfigProvider);
  Future<bool> probe() async {
    if (cfg == null) return true; // محلي: الوصلة وحدها تكفي
    try {
      await http
          .head(Uri.parse('${cfg.supabaseUrl}/rest/v1/'))
          .timeout(networkPingTimeout);
      return true; // أي ردّ HTTP (حتى 401) = الخادم بلغ
    } catch (_) {
      return false;
    }
  }

  final svc = NetworkStatus(
    linkStream: Connectivity().onConnectivityChanged.map(
      (results) => results.any((r) => r != ConnectivityResult.none),
    ),
    probe: probe,
  );
  svc.listeners.add((v) => ref.read(onlineProvider.notifier).state = v);
  svc.start();
  ref.onDispose(svc.dispose);
  return svc;
});

final syncContextProvider = Provider<SyncContext>(
  (ref) => SyncContext(
    db: ref.watch(localDbProvider),
    repos: ref.watch(reposProvider),
    transport: ref.watch(transportProvider),
    // بوابة المحرك — توأم getIsOnline: دورة أوفلاين تعود 'offline'
    // بلا نداء شبكة، ويستأنفها محفز إعادة الاتصال فور العودة.
    isOnline: () => ref.read(onlineProvider),
    // م65 — عامل R2 مضبوط ⇒ مصغّرات الأشعة تُستثنى من حمولة المزامنة
    // (العامل يخدمها بـ`?v=thumb`). تُقرأ حيّةً فتعطيلُ R2 يعيدها فوراً.
    hasCloudImages: () => ref.read(cloudConfigProvider)?.hasImages ?? false,
  ),
);

/// م70 — الأرشفة الباردة: لا تُبنى إلا بوضع سحابي كامل (ناقل Supabase
/// الذي ينفذ ArchiveTransport + عامل R2 للحزم). الوضع المحلي والمزيّفات
/// ⇒ null فتتعطل الميزة تلقائياً بلا شرط إضافي في أي مكان آخر.
final coldArchiveProvider = Provider<ColdArchive?>((ref) {
  final remote = ref.watch(r2ClientProvider);
  final transport = ref.watch(transportProvider);
  if (remote == null || transport is! ArchiveTransport) return null;
  return ColdArchive(
    ctx: ref.watch(syncContextProvider),
    remote: remote,
    transport: transport as ArchiveTransport,
  );
});

/// مخزن الأشعة المحلي (كان في xray_section — انتقل هنا ليشاركه خط الأنابيب).
final xrayStoreProvider = Provider<XrayStore>((ref) {
  final auth = ref.watch(authProvider);
  // م83 — الصور تدخل خزنة SQLCipher بالمفتاح نفسه. بلا مفتاح (اختبارات،
  // أو علم DB_PLAINTEXT) يبقى السلوك ملفّات كما كان حرفياً.
  final store = XrayStore(
    encryptionKey: ref.watch(dbEncryptionKeyProvider),
    repos: ref.watch(reposProvider),
    baseDir: ref.watch(dbDirProvider),
    uid: auth is SignedIn ? auth.user.uid : 'anon',
  );
  // مقبض الخزنة المشفَّرة يبقى مفتوحاً بين العمليات — يُغلق مع المزوّد.
  ref.onDispose(store.close);
  return store;
});

/// خط أنابيب الأشعة السحابي — null بلا عامل R2 (الوضع المحلي).
final xrayPipelineProvider = Provider<XrayPipeline?>((ref) {
  final remote = ref.watch(r2ClientProvider);
  if (remote == null) return null;
  return XrayPipeline(
    db: ref.watch(localDbProvider),
    repos: ref.watch(reposProvider),
    store: ref.watch(xrayStoreProvider),
    remote: remote,
    meter: ref.watch(storageMeterProvider), // م134 — حارس ومحاسب الحصة
    remapConfigKey: (tempKey, serverKey, patient) {
      final repos = ref.read(reposProvider);
      final v = repos.settings.get('app.config');
      final cfg = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
      repos.settings.set(
        'app.config',
        remapXrayKeyInConfig(cfg, patient, tempKey, serverKey),
      );
      ref.read(configRevProvider.notifier).state++;
    },
  );
});

/// عدّاد نسخة الأشعة — نظير xrayVersion: يقفز عند اكتمال/فشل استرجاع
/// مصغرة فيعاد بناء الشبكة (سبينر ← صورة/بلاطة حمراء).
final xrayVersionProvider = StateProvider<int>((ref) => 0);

/// م24 — عدد الصور بانتظار الرفع (توأم pendingUploadCount التفاعلي):
/// يتحدث بنبضة xrayVersion بعد كل التقاط/تصريف/حذف — تعرضه لافتة
/// الرئيسية «N صور بانتظار الرفع».
final pendingXrayUploadsProvider = Provider<int>((ref) {
  ref.watch(xrayVersionProvider);
  return ref.watch(reposProvider).xrays.getPendingUploads().length;
});

/// م24 — طابور الرفع التلقائي (توأم startUploadQueueListener): وحدة
/// تصريف واحدة أحادية الرحلة (رفع + حذف معلق + نبضة واجهة) يتشاركها
/// المحفزون الأربعة: البدء بعد الدخول، مؤقت الثلاثين ثانية، حافة عودة
/// الاتصال، وزر المزامنة اليدوي. null في الوضع المحلي (بلا عامل R2).
final xrayUploadQueueProvider = Provider<XrayUploadQueue?>((ref) {
  final pipeline = ref.watch(xrayPipelineProvider);
  if (pipeline == null) return null;
  final q = XrayUploadQueue(
    drain: () async {
      await pipeline.drainUploads();
      await pipeline.drainDeletes();
      // نبضة الواجهة: تحدّث اللافتة وشارات «بانتظار الرفع» والمعارض.
      ref.read(xrayVersionProvider.notifier).state++;
    },
  );
  ref.onDispose(q.stop);
  return q;
});

/// مسترجِع المصغرات عند الطلب — null بلا عامل R2 (الوضع المحلي:
/// الغياب يظهر بلاطة فاشلة مباشرة كما لو تعذّر الجلب).
final xrayThumbRestorerProvider = Provider<XrayThumbRestorer?>((ref) {
  final remote = ref.watch(r2ClientProvider);
  if (remote == null) return null;
  return XrayThumbRestorer(
    store: ref.watch(xrayStoreProvider),
    remote: remote,
    onChange: () => ref.read(xrayVersionProvider.notifier).state++,
  );
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  // م54 — قاعدة الاستطلاع تعود لأصل المحرك (٣٠ ثانية نشاطاً): كانت
  // تُحقن بـ syncMin (٣٠ دقيقة افتراضاً، أرضية ٥) فصار «الإيقاع السريع»
  // دقائق طويلة — يضيف المستخدم معالجة على جهاز ويفتح الآخر فلا يجدها.
  // syncMin يبقى محترماً لكن بمعناه الصحيح: **سقف** تراخي الخمول
  // (كل: N دقيقة كحد أقصى بين سحبَي خمول)، يُقرأ حياً عند كل نبضة
  // فيسري تغييره من الإعدادات فوراً بلا إعادة تشغيل.
  final engine = SyncEngine(
    ref.watch(syncContextProvider),
    idleCapMs: () {
      final cfgV = ref.read(reposProvider).settings.get('app.config');
      final syncMin = cfgV is Map
          ? (num.tryParse('${cfgV['syncMin'] ?? ''}') ?? 30)
          : 30;
      final ceilingMs = (syncMin < 5 ? 5 : syncMin).toInt() * 60 * 1000;
      // م-إصلاح (فورية المزامنة — بلاغ المالك: تعديل جهازٍ لا يظهر على
      // الآخر إلا بإعادة تشغيل). التراجع الأُسّي كان يمدّ سقف سحب الخمول
      // إلى ٥–٣٠ دقيقة، فينتظر الجهاز المستقبِل طويلاً. نُثبّت السقف عند
      // ٦٠ ثانية كحدٍّ أقصى أثناء تشغيل التطبيق: انتظارٌ لا يتجاوز دقيقة
      // بدل نصف ساعة، بكلفة طلبٍ خفيفٍ واحدٍ في الدقيقة عند الخمول التام
      // فقط (النشاط والركل يعيدان الإيقاع السريع فوراً كما هو). قابلٌ
      // للضبط لاحقاً؛ والوضع المحلي بلا سحابة لا يتأثر (المحرك متوقف).
      const activeCapMs = 60 * 1000;
      return ceilingMs < activeCapMs ? ceilingMs : activeCapMs;
    },
  );
  // توصيل الإسقاط التفاعلي — سحبٌ دمج صفوفاً يجب أن يحدّث الواجهة كلها
  // (كان مفقوداً: أول دخول سحابي يسحب إعدادات الحساب وبياناته إلى القاعدة
  // ولا يظهر منها شيء حتى إعادة التشغيل). نبضات النسخ تعيد بناء الإسقاطات:
  // الإعدادات (بيت الحقول والهيدر) والسجلات والمالية والحجوزات والدور
  // وصور الأشعة — توأم «التحميل بعد المزامنة» في الأصل.
  engine.projectionListeners.add((info) {
    ref.read(configRevProvider.notifier).state++;
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    ref.read(apptRevProvider.notifier).state++;
    ref.read(queueRevProvider.notifier).state++;
    ref.read(xrayVersionProvider.notifier).state++;
    // م56 — مصالحة ترقيم الدور بعد دورة دمجت صفوفاً (توأم initQueueSync
    // في الأصل): جهازان أضافا/رتّبا معاً يتقاربان على نفس الأرقام بلا
    // تأرجح. idempotent فلا كتابة بعد التقارب. أفضل جهد — لا يفشل الإسقاط.
    try {
      (ref.read(queueViewProvider.notifier)).reconcileNumbers();
    } catch (_) {
      /* لا لوحة مفتوحة أو خطأ عابر */
    }
  });
  // م70 — الأرشفة الباردة التلقائية: بعد كل دورة مكتملة، مرة كل ٣٠ يوماً
  // كحد أقصى. القراءة كسولة عند كل نبضة (لا التقاط) فتغيير الإعداد أو
  // الحساب أو تعطيل R2 يسري فوراً؛ وnull (وضع محلي/بلا عامل) = لا عمل.
  final archiveScheduler = ArchiveScheduler(
    archiveOf: () => ref.read(coldArchiveProvider),
  );
  engine.statusListeners.add(archiveScheduler.onEngineStatus);
  // م71 — احتفاظ المواعيد: كنسة يومية (شطب الماضي الأقدم من أسبوع) وحذف
  // فعلي أسبوعي للشواهد القديمة. مستقلة عن R2 عمداً — تعمل بأي وضع سحابي
  // (المنفذ هو الناقل نفسه)، وبالوضع المحلي تصمت خطوة الحذف الخادمي فقط.
  final tp = ref.read(transportProvider);
  final retention = RetentionSweeper(
    ctx: ref.read(syncContextProvider),
    purge: tp is TombstonePurge ? tp as TombstonePurge : null,
  );
  engine.statusListeners.add(retention.onEngineStatus);
  // م79 — دافع سجلّ التدقيق: يلتصق بنبضة اكتمال الدورة كما تفعل الأرشفة
  // والاحتفاظ. القراءة كسولة عند كل نبضة، فالوضع المحلي (ناقل لا ينفّذ
  // AuditTransport) يعني تراكم القيود محلياً بلا دفع — وهو سلوك مقصود:
  // السجلّ يبقى كاملاً على الجهاز، وينقصه حارس الخادم فقط.
  final auditPusher = AuditPusher(
    db: ref.read(localDbProvider),
    transportOf: () {
      final t = ref.read(transportProvider);
      return t is AuditTransport ? t as AuditTransport : null;
    },
  );
  engine.statusListeners.add(auditPusher.onEngineStatus);
  ref.onDispose(engine.stopEngine);
  return engine;
});

/// محفّز إعادة الاتصال — توأم onNetworkChange في الأصل: عودة الشبكة تركل
/// دورة مزامنة (وتصريف صور أفضل-جهد) بعد توهين ثانيتين، بدل انتظار نبضة
/// الاستطلاع (٣٠ث حتى ٥ دقائق في الخمول). محفّز فقط — بوابة isOnline تبقى
/// متفائلة فلا يستطيع قارئ شبكة مخطئ منع المزامنة. لا يُبنى إلا في وضع
/// السحابة؛ تفعيله كسول من الصدفة بعد أول إطار.
final reconnectKickProvider = Provider<ReconnectKick?>((ref) {
  if (ref.watch(cloudConfigProvider) == null) return null;
  final engine = ref.watch(syncEngineProvider);
  final kick = ReconnectKick(() {
    engine.kickSync(0);
    // تصريف صور الأشعة بعد عودة الاتصال — عبر الطابور أحادي الرحلة
    // (توأم مستمع online في الأصل: نفس التشغيلة يتشاركها الجميع).
    ref.read(xrayUploadQueueProvider)?.drainNow();
  });
  // م25 — مصدر واحد: يستهلك خدمة الشبكة الموحدة (وصلة + وصول مؤكد)
  // بدل اشتراك خاص بالوصلة الخام — توأم اشتراك onNetworkChange بالخدمة.
  final net = ref.watch(networkStatusProvider);
  void onNet(bool online) => kick.onEvent(online);
  net.listeners.add(onNet);
  ref.onDispose(() {
    net.listeners.remove(onNet);
    kick.dispose();
  });
  return kick;
});

/// المزامنة التلقائية — توأم autoSync/syncMin: دالة صريحة **لا موفر
/// تفاعلي** (مراقبة configRev من الصدفة كانت تستأنف اشتراكاً موقوفاً وسط
/// انتقال المسارات فترمي تأكيد Riverpod). تُستدعى بعد الإطار من الصدفة
/// وبعد كل تغيير إعدادات — startEngine idempotent فالتكرار آمن.
void applyAutoSync(dynamic ref) {
  // تفعيل خدمة الشبكة الموحدة (هيدر «متصل الآن» وبوابة المحرك) كسولاً —
  // في كل الأوضاع؛ ومحفز إعادة الاتصال (وضع السحابة فقط).
  ref.read(networkStatusProvider);
  ref.read(reconnectKickProvider);
  final engine = ref.read(syncEngineProvider) as SyncEngine;
  final signedIn = ref.read(authProvider) is SignedIn;
  final cloud = ref.read(cloudConfigProvider) != null;
  final cfg = ref.read(appConfigProvider) as Map;
  final wantAuto = cfg['autoSync'] != false;
  // م24 — طابور رفع الصور يعمل مع الدخول في وضع السحابة (توأم استدعاء
  // startUploadQueueListener عند الإقلاع في الأصل): تصريف فوري + مؤقت
  // ثلاثين ثانية. يقف مع الخروج/فقد وضع السحابة.
  final queue = ref.read(xrayUploadQueueProvider) as XrayUploadQueue?;
  if (signedIn && cloud) {
    queue?.start();
  } else {
    queue?.stop();
  }
  if (signedIn && cloud && wantAuto) {
    engine.startEngine();
  } else {
    engine.stopEngine();
  }
}

/// م54 — ركلة «لحظة حضور»: دورة مزامنة فورية عند استئناف التطبيق من
/// الخلفية وعند فتح شاشة الإعدادات. المؤقّت الدوري وحده كان يترك الجهاز
/// المستقبِل أعمى عن تغييرات الجهاز الآخر حتى نبضته التالية (دقائق) —
/// بينما المستخدم يفتح التطبيق الآن ليرى ما أضافه هناك. تحترم شروط
/// applyAutoSync نفسها (دخول + سحابة + مزامنة تلقائية مفعلة) فلا تعمل
/// في الوضع المحلي ولا لمن أوقف المزامنة التلقائية (له زر «مزامنة»).
void kickPresenceSync(dynamic ref) {
  final signedIn = ref.read(authProvider) is SignedIn;
  final cloud = ref.read(cloudConfigProvider) != null;
  final cfg = ref.read(appConfigProvider) as Map;
  final wantAuto = cfg['autoSync'] != false;
  if (!signedIn || !cloud || !wantAuto) return;
  (ref.read(syncEngineProvider) as SyncEngine).kickSync(0);
}

/// حالة مزامنة حية للواجهة (عداد المعلق + جارية الآن).
class SyncUiState {
  const SyncUiState({this.syncing = false, this.pending = 0, this.lastOk});

  final bool syncing;
  final int pending;
  final DateTime? lastOk;
}

class SyncUiController extends Notifier<SyncUiState> {
  @override
  SyncUiState build() => const SyncUiState();

  Future<void> manualSync() async {
    final engine = ref.read(syncEngineProvider);
    state = SyncUiState(
      syncing: true,
      pending: state.pending,
      lastOk: state.lastOk,
    );
    final r = await engine.syncNow();
    // في الوضع السحابي: تصريف صور الأشعة بعد الدورة عبر الطابور أحادي
    // الرحلة (م24) — نداء متزامن مع المؤقت/عودة الاتصال يتشارك التشغيلة
    // نفسها فلا رفع مزدوجاً. أفضل جهد — لا يفشل المزامنة نفسها.
    try {
      await ref.read(xrayUploadQueueProvider)?.drainNow();
    } catch (_) {
      /* أفضل جهد */
    }
    state = SyncUiState(
      syncing: false,
      pending: engine.getEngineStatus().pending,
      lastOk: r.ok ? DateTime.now() : state.lastOk,
    );
  }
}

final syncUiProvider = NotifierProvider<SyncUiController, SyncUiState>(
  SyncUiController.new,
);

// ── المصادقة ────────────────────────────────────────────────────────────────

/// المصادقة: Supabase في الوضع السحابي وإلا المحلية — الواجهة واحدة.
final authServiceProvider = Provider<AuthService>((ref) {
  final supabase = ref.watch(supabaseAuthProvider);
  return supabase ?? LocalAuthService(ref.watch(localDbProvider));
});

sealed class AuthState {
  const AuthState();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.user);

  final AuthUser user;
}

class AuthController extends Notifier<AuthState> {
  /// م31 — هل هذا دخولٌ صريح للتو؟ (يقود شاشة الترحيب في البوابة). استعادة
  /// الجلسة عند فتح التطبيق = false فلا ترحيب متكرر؛ login/register = true.
  bool justLoggedIn = false;

  @override
  AuthState build() {
    final restored = ref.watch(authServiceProvider).restoreSession();
    if (restored != null) {
      // عزل الحسابات: نفس ما يفعله setRepositoryOwner بعد استرجاع الجلسة.
      final db = ref.read(localDbProvider);
      db.setOwnerUid(restored.uid);
      // م33 — تعافي الملكية: آخر حساب غير مسجل (جهاز من عهد ما قبل
      // التتبع) ⇒ ختم/تطهير الصفوف بلا مالك وصفوف الحسابات الأخرى
      // وتصفير المؤشر — فلا تظهر عيادات/سجلات حساب قديم بعد الفتح.
      if (lastUid(db) == null) {
        healOwnershipAtBoot(
          db,
          restored.uid,
          cloud: ref.read(cloudConfigProvider) != null,
        );
      }
      justLoggedIn = false;
      return SignedIn(restored);
    }
    return const SignedOut();
  }

  /// كشف التبديل السلطوي + مسح بيانات الحساب السابق (دلالات clearLocalData):
  /// دخول uid يختلف عن آخر uid عرف الجهاز ⇒ مسح كامل قبل تثبيت الملكية،
  /// فلا تتسرب بيانات الحساب القديم إلى الجديد. نفس المستخدم ⇒ لا مسح
  /// (offline-first: بياناته تبقى). آخر حساب غير مسجل ⇒ تعافي الملكية م33.
  void _handleAccountSwitch(String uid) {
    final db = ref.read(localDbProvider);
    final prev = lastUid(db);
    if (prev == null || prev.isEmpty) {
      // دخول جديد بلا استمرارية جلسة ⇒ لا ادعاء للمتسخة (claimDirty=false).
      healOwnershipAtBoot(
        db,
        uid,
        cloud: ref.read(cloudConfigProvider) != null,
        claimDirty: false,
      );
      return; // healOwnershipAtBoot سجّل آخر حساب.
    }
    if (prev != uid) {
      wipeAllAccountData(db);
      _wipeXrayImages();
    }
    setLastUid(db, uid);
  }

  /// م77 — منفذ اختبار لمسار التبديل بلا تزييف خدمة مصادقة كاملة.
  /// المسار نفسه الذي يستدعيه [login] حرفياً — لا نسخة موازية منه.
  @visibleForTesting
  void handleAccountSwitchForTest(String uid) => _handleAccountSwitch(uid);

  /// م77 — حذف صور الأشعة عند تبديل الحساب.
  ///
  ///  العلة: [wipeAllAccountData] يمسح الجداول فقط، **وتوثيقه الذاتي يقرّ
  ///  بذلك حرفياً**: «لا يمسّ ملفات صور الأشعة — المستدعي يتولّاها». وهذا
  ///  هو المستدعي الوحيد، ولم يكن يتولّاها.
  ///
  ///  وما يضاعف الأثر أن مُنقّي أسماء الملفات في `xray_store.dart` يُبقي
  ///  نطاق الحروف العربية عمداً، فيبقى **اسم المريض في اسم الملف**. على
  ///  لوح عيادة مشترك، سرد المجلد وحده كشفٌ كامل لقائمة مرضى الحساب
  ///  السابق — بلا فتح صورة واحدة.
  ///
  ///  **النطاق: تبديل الحساب فقط** (قرار المالك). الخروج العادي لا يحذف:
  ///  بلا عامل R2 مضبوط تكون الصور محلية حصراً، وحذفها عند كل خروج فقدٌ
  ///  نهائي لا مجرّد إخلاء ذاكرة مؤقتة. وتبديل الحساب حالة مختلفة —
  ///  البيانات هناك تخصّ حساباً آخر أصلاً.
  void _wipeXrayImages() {
    // م83 — المجلد صار يضمّ `xray_vault.db` ومقبضُه يبقى مفتوحاً بين
    // العمليات. وويندوز لا يحذف ملفاً مفتوحاً: كان الحذف يُخفق ويُبتلع
    // صامتاً، فتبقى صور الحساب السابق — وهي تُفتح بمفتاح الجهاز نفسه —
    // متاحةً للحساب الجديد. أي انتكاسةٌ صامتة لذات الإصلاح الذي وُضعت
    // هذه الدالة لأجله. فيُغلق المقبض أولاً، ويُبطَل المزوّد كي لا يعيد
    // فتحه أثناء الحذف.
    final imagesPath = p.join(ref.read(dbDirProvider), 'xray_images');
    // الإغلاق بالمسار لا بإبطال المزوّد: `xrayStoreProvider` يراقب
    // `authProvider` فإبطاله من هنا دورةُ اعتماد يرفضها Riverpod.
    closeVaultsIn(imagesPath);
    try {
      final dir = Directory(imagesPath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e, st) {
      // لم يعد يُبتلع: إخفاق المسح يعني بقاء بيانات حسابٍ آخر.
      recordError(e, st, context: 'wipe-xray-images');
    }
  }

  Future<void> login(String email, String password, bool remember) async {
    final user = await ref
        .read(authServiceProvider)
        .login(email, password, remember: remember);
    _handleAccountSwitch(user.uid);
    final db = ref.read(localDbProvider);
    db.setOwnerUid(user.uid);
    // م79 — مُتحقِّق فتح القفل: مغلّف PBKDF2 بملح، لا كلمة المرور نفسها.
    // يُخزَّن هنا لأنها **اللحظة الوحيدة** التي تمرّ فيها الكلمة الصريحة
    // بالتطبيق، ووجوده يجعل فتح القفل ممكناً بلا إنترنت.
    //
    // م97 — **لا يدهس رمزَ قفلٍ معيَّناً**: الرمز صار مفتاحَ الشاشة
    // للجميع (يُعيَّن إجبارياً عند تفعيل القفل/البصمة)، ولو كتب كلُّ
    // دخولٍ فوقه لانهار النموذج عند أول إعادة دخول. بلا رمزٍ يبقى
    // السلوك التاريخي حرفياً (توافق التنصيبات القائمة).
    if (!hasPinVerifier(db)) storeLockVerifier(db, password);
    recordAudit(db, action: AuditAction.login);
    justLoggedIn = true;
    state = SignedIn(user);
  }

  Future<void> register(String email, String password) =>
      ref.read(authServiceProvider).register(email, password);

  /// م88 — دخول Google عبر مزوّد OAuth (PKCE فوق Supabase). يتدفّق في بوابة
  /// ما بعد الدخول نفسها: جديدٌ ⇒ إعداد إجباري، عائدٌ ⇒ ترحيبٌ باسمه.
  ///
  /// لا مُتحقِّق قفلٍ يُخزَّن هنا — لا كلمةَ مرور تمرّ بالتطبيق أصلاً
  /// (جوهر أمان OAuth). كان توثيق هذا السطر يَعِد بأن «مستخدم Google يفتح
  /// القفل بالبصمة»، بينما زرُّ البصمة نفسه كان مشروطاً بوجود المُتحقِّق —
  /// فخٌّ قفلُه بلا مفتاح: لا حقل ولا بصمة، خروجٌ فقط. م91 سدّه من طرفَي
  /// الوعد: البوابة تقترح «رمز قفل التطبيق» فور الدخول
  /// (post_login_gate/pin_setup)، والبصمة تعمل وحدها بلا مُتحقِّق
  /// (idle_lock). الرمز محليٌّ بنفس ضمانات المُتحقِّق حرفياً.
  Future<void> signInWithGoogle() async {
    final res = await ref.read(oauthSignInProvider).signInWithGoogle();
    _handleAccountSwitch(res.uid);
    final db = ref.read(localDbProvider);
    db.setOwnerUid(res.uid);
    recordAudit(db, action: AuditAction.login);
    justLoggedIn = true;
    state = SignedIn(
      AuthUser(uid: res.uid, email: res.email, displayName: res.displayName),
    );
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    ref.read(localDbProvider).setOwnerUid(null);
    // إصلاح تبديل الحساب: إبطال خدمتَي التخزين والترخيص كي يعيد الدخول
    // التالي بناءهما نظيفتين (لا لقطة/حصة محفوظة في الذاكرة من حسابٍ سابق).
    // الحالة نفسها في القاعدة تُمسح عند التبديل، وهذا يمنع أي بقايا ذاكرة.
    ref.invalidate(storageMeterProvider);
    ref.invalidate(licenseServiceProvider);
    justLoggedIn = false;
    state = const SignedOut();
  }

  /// م93 — مسحٌ محليّ كامل بعد حذف الحساب من الخادم، ثم خروج. يُعيد
  /// استخدام مسار مسح تبديل الحساب حرفياً (الجداول + صور الأشعة +
  /// اعتمادات الدخول)، ويمحو مُتحقِّق القفل، فلا يبقى أثرٌ لحسابٍ زال
  /// من مصدره. يُستدعى من [AccountAdmin.deleteAccount] بعد نجاح الخادم.
  Future<void> deleteLocalAndLogout() async {
    final db = ref.read(localDbProvider);
    wipeAllAccountData(db);
    _wipeXrayImages();
    clearLockVerifier(db);
    await logout();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// م88 — مزوّد دخول OAuth (Google). الافتراض «غير مُفعَّل» حتى تُضبَط
/// اعتمادات Google؛ يُتجاوَز بالتنفيذ الحقيقي (supabase_flutter) عند جهوزها،
/// وبمزيّفٍ في الاختبارات.
final oauthSignInProvider = Provider<OAuthSignIn>(
  (ref) => const OAuthNotConfigured(),
);

// ── الإعدادات المشتركة للواجهة ─────────────────────────────────────────────

/// app.config من جدول الإعدادات (نفس مفتاح Vue).
final appConfigProvider = Provider<Map<String, Object?>>((ref) {
  ref.watch(configRevProvider); // يعاد البناء عند أي كتابة إعدادات
  final v = ref.watch(reposProvider).settings.get('app.config');
  return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
});

/// م180 — مفتاح ميزة «نسبة المعالجات» للواجهات (مطفأ افتراضياً):
/// عند الإطفاء تختفي حصة الطبيب من كل الشاشات والطباعة، والإجمالي كله
/// للعيادة. المصدر الواحد: ratesFeatureEnabled في rate_snapshot.
final ratesEnabledProvider = Provider<bool>(
    (ref) => ratesFeatureEnabled(ref.watch(appConfigProvider)));

/// نبضة إعادة قراءة للإعدادات (تزيد بعد كل كتابة).
final configRevProvider = StateProvider<int>((ref) => 0);

final clinicsProvider = Provider<List<String>>((ref) {
  final cfg = ref.watch(appConfigProvider);
  final c = cfg['clinics'];
  return c is List ? c.map((e) => '$e').toList() : const <String>[];
});

/// العملة — توأم app.currency (config.currency الصادقة وإلا د.ل).
final currencyProvider = Provider<String>((ref) {
  final cfg = ref.watch(appConfigProvider);
  final c = cfg['currency'];
  return (c is String && c.trim().isNotEmpty) ? c.trim() : 'د.ل';
});

/// م100 — نظام ترقيم الأسنان المعروض (Palmer / FDI). **تفضيل عرضٍ
/// مُزامَن** في app.config (هويةُ عرضٍ للعيادة كلها بقرار المالك) — لا
/// يمسّ تخزين الأسنان المحايد `{q,n}` إطلاقاً. الغياب = Palmer.
final notationSystemProvider = Provider<NotationSystem>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return notationSystemFromConfig(cfg['toothNotation']);
});

/// وضع الواجهة (فاتح/داكن) — محلي للجهاز في metadata: توأم dental_theme.
final themeModeProvider = StateProvider<String>((ref) {
  final db = ref.watch(localDbProvider);
  final row = db.queryFirst('SELECT value FROM metadata WHERE key = ?', const [
    'dental_theme',
  ]);
  final v = '${row?['value'] ?? ''}';
  return v == 'dark' ? 'dark' : 'light';
});

/// مقياس الخط (محلي للجهاز — metadata لا config المتزامن): توأم dental_font_size.
final fontScaleProvider = StateProvider<double>((ref) {
  final db = ref.watch(localDbProvider);
  final row = db.queryFirst('SELECT value FROM metadata WHERE key = ?', const [
    'dental_font_size',
  ]);
  return double.tryParse('${row?['value'] ?? ''}') ?? 1.0;
});

final centerNameProvider = Provider<String>((ref) {
  final cfg = ref.watch(appConfigProvider);
  final n = cfg['centerName'];
  // م180/٦ — اسم العلامة الجديد بديلاً حين لا اسم مركز مضبوط.
  return (n is String && n.trim().isNotEmpty) ? n : kAppBrandName;
});

/// الشهر المحدد في الهيدر (yyyy-MM) — توأم appStore.selectedMonth.
final selectedMonthProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}';
});
