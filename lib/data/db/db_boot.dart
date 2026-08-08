/// ============================================================================
///  م83 — متتالية إقلاع القاعدة المشفَّرة
/// ============================================================================
///
///  لماذا ملفٌ مستقل لا سطورٌ في `main.dart`
///  ────────────────────────────────────────
///  هذه أخطر متتالية في التطبيق: تنقل مجلد البيانات، وتحسم المفتاح، وتُرحّل
///  القاعدة في مكانها. و`main.dart` لا يُختبر — يحتاج منصّة ومسارات نظام.
///  فوضعُها هنا يجعل **كل فرع فيها** قابلاً للتشغيل في اختبار بمخزن مفتاح
///  في الذاكرة ومجلد مؤقّت، ويترك `main.dart` سطرين لا منطق فيهما.
///
///  الفشل هنا لا يُبتلع
///  ───────────────────
///  المتتالية لا ترمي، بل تعود بحالة صريحة. والسبب أن كل بديل أسوأ:
///
///    • ابتلاع الخطأ والمتابعة بلا تشفير ⇒ بيانات مرضى نصّاً مقروءاً بلا
///      أن يعلم أحد. تخفيضٌ أمني صامت — أسوأ أنواع الأعطال.
///    • ابتلاعه والمتابعة بقاعدة جديدة  ⇒ العيادة ترى قاعدةً فارغة وتظنّ
///      بياناتها تبخّرت، بينما هي سليمة على القرص خلف مفتاح مفقود.
///    • الرمي بلا معالجة               ⇒ شاشة بيضاء بلا تفسير.
///
///  فالحالة الصريحة تُتيح لـ`main.dart` عرض شاشة عربية تشرح ما جرى وتقول
///  ما العمل — والبيانات تبقى على القرص كما هي في كل الحالات.
///
///  الإيقاف الصريح لا الضمني
///  ────────────────────────
///  `--dart-define=DB_PLAINTEXT=true` يوقف التشفير لأجل التطوير. علمٌ صريح
///  يظهر في أمر البناء، لا ارتدادٌ صامت عند أول خطأ.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'blob_vault.dart';
import 'db_encrypt.dart';
import 'db_key.dart';
import 'db_paths.dart';

/// اسم ملف القاعدة — مصدرٌ واحد بدل تكراره في المزوّد والإقلاع.
const String kDbFileName = 'dental_clinic_offline.db';

/// إيقاف التشفير للتطوير: `--dart-define=DB_PLAINTEXT=true`.
const bool kPlaintextDbOverride =
    bool.fromEnvironment('DB_PLAINTEXT');

enum DbBootStatus {
  /// جاهزة — قاعدة مشفَّرة تُفتح بالمفتاح المعاد.
  ready,

  /// جاهزة، وقد رُحّلت من سادة إلى مشفَّرة في هذا الإقلاع.
  migrated,

  /// تشفيرٌ موقوف صراحةً بعلم البناء — المفتاح `null`.
  plaintextByFlag,

  /// القاعدة مشفَّرة والمفتاح مفقود. **لا تُفتح ولا يُولَّد بديل.**
  keyMissing,

  /// أخفق الترحيل. الأصل سليم كما كان، ولا يُفتح شيء حتى يُعالَج.
  migrationFailed,
}

class DbBootResult {
  const DbBootResult({
    required this.dataDir,
    required this.status,
    required this.detail,
    this.encryptionKey,
    this.backupPath,
    this.dirMoved = false,
  });

  /// المسار المعتمد للبيانات بعد أي نقل — يُحقن في `dbDirProvider`.
  final String dataDir;
  final DbBootStatus status;
  final String detail;

  /// `null` يعني «افتح بلا مفتاح» — لا يحدث إلا مع العلم الصريح.
  final String? encryptionKey;

  /// نسخة سادة بجوار القاعدة بعد الترحيل — تُحذف بعد تأكّد المالك.
  final String? backupPath;

  final bool dirMoved;

  /// هل يجوز فتح القاعدة والمضيّ؟
  bool get canOpen =>
      status == DbBootStatus.ready ||
      status == DbBootStatus.migrated ||
      status == DbBootStatus.plaintextByFlag;
}

/// يُهيّئ كل ما تحتاجه القاعدة قبل أول فتح: المسار، والمفتاح، والترحيل.
///
/// يُستدعى **قبل** فتح القاعدة بأي شيء. ونقلُ المجلد تحديداً يفشل على
/// ويندوز إن كان ملفٌ فيه مفتوحاً.
Future<DbBootResult> prepareDatabase({
  required String supportDir,
  required DbKeyStore keyStore,
  bool? isWindows,
  bool plaintextOverride = kPlaintextDbOverride,
}) async {
  // ١) المسار أولاً: كل ما بعده — المفتاح والعلامة والقاعدة — يعيش فيه،
  //    فنقلُه بعد حسم المفتاح يترك العلامة في المكان الخطأ.
  final move = ensureNonRoamingDataDir(
    supportDir,
    isWindows: isWindows ?? Platform.isWindows,
  );
  final dir = move.dir;
  try {
    Directory(dir).createSync(recursive: true);
  } catch (_) {/* موجود أصلاً في الغالب */}

  if (plaintextOverride) {
    // العلم يوقف التشفير، ولا يجعل قاعدةً مشفَّرة قائمة تُقرأ بلا مفتاح.
    // بلا هذا الفحص يعود `canOpen` صادقاً بمفتاح `null`، فينهار الفتح
    // باستثناء خام بدل رسالة — والعلم مسوَّق أنه مفتاح إيقاف مفهوم.
    if (classifyDb(p.join(dir, kDbFileName)) == DbFileState.encrypted) {
      return DbBootResult(
        dataDir: dir,
        status: DbBootStatus.keyMissing,
        detail: 'DB_PLAINTEXT مُفعَّل بينما القاعدة على القرص مشفَّرة. '
            'لا تُفتح مشفَّرةٌ بلا مفتاح — أزل العلم، أو استعمل مجلد '
            'بيانات آخر للتطوير.',
        dirMoved: move.moved,
      );
    }
    return DbBootResult(
      dataDir: dir,
      status: DbBootStatus.plaintextByFlag,
      detail: 'التشفير موقوف بعلم البناء DB_PLAINTEXT — للتطوير فقط',
      dirMoved: move.moved,
    );
  }

  // ٢) المفتاح — والقرار مبنيٌّ على **دليل من القرص** لا على ملف علامة.
  //
  //    رأسُ ملف القاعدة يقول أمشفَّرٌ هو أم سادّ أم غائب، وخزنةُ الأشعة
  //    دليلٌ ثانٍ. ومراجعةٌ كشفت أن الاعتماد على العلامة وحدها يفتح عطلين
  //    متقابلين: علامةٌ محذوفة فوق قاعدة مشفَّرة ⇒ يُولَّد مفتاح جديد
  //    **يُكتب فوق** القديم فيصير الفقد نهائياً؛ وعلامةٌ باقية بلا بيانات
  //    ⇒ رفضُ إقلاعٍ أبديّ حمايةً لما لا وجود له. والملفات لا تكذب.
  final dbPath = p.join(dir, kDbFileName);
  final vaultFile =
      File(p.join(dir, 'xray_images', EncryptedBlobVault.fileName));
  final dbState = classifyDb(dbPath);
  final tmpOrphan = File('$dbPath.enc-tmp');
  final encryptedDataExists = dbState == DbFileState.encrypted ||
      vaultFile.existsSync() ||
      // ترحيلٌ قُطع في نافذة الإبدال: البيانات كلها في المؤقّت المشفَّر،
      // فطلبُ المفتاح واجب وإلا وُلِّد بديلٌ ولم يُستعد شيء.
      (dbState == DbFileState.absent && tmpOrphan.existsSync());

  final String key;
  try {
    final res = await resolveKey(
      keyStore,
      encryptedDataExists: encryptedDataExists,
      dbDir: dir,
    );
    key = res.key;
  } on DbKeyMissingException catch (e) {
    return DbBootResult(
      dataDir: dir,
      status: DbBootStatus.keyMissing,
      detail: e.toString(),
      dirMoved: move.moved,
    );
  } catch (e) {
    // إخفاق مخزن النظام نفسه (منصّة غير مدعومة، أو خدمة أسرار معطّلة).
    // لا ارتداد إلى السادة: ذلك تخفيضٌ أمني صامت.
    return DbBootResult(
      dataDir: dir,
      status: DbBootStatus.keyMissing,
      detail: 'تعذّر الوصول إلى مخزن مفاتيح النظام: $e',
      dirMoved: move.moved,
    );
  }

  // ٣) استرجاع ترحيلٍ قُطع قبل أي شيء آخر: لا قاعدة في مكانها ومؤقّتٌ
  //    مشفَّر بجوارها يفتح بالمفتاح ⇒ هو البيانات الحقيقية، يُنقل مكانها.
  //    وبلا هذا يمضي الإقلاع فيُنشئ قاعدةً **فارغة** فوق عيادةٍ كاملة.
  var recovered = false;
  if (dbState == DbFileState.absent && tmpOrphan.existsSync()) {
    recovered = recoverInterruptedMigration(dbPath: dbPath, hexKey: key);
  }

  // ٤) الترحيل إن كانت القاعدة قائمةً وسادة. عديم الأثر فيما عدا ذلك.
  if (!recovered && isPlainDatabase(dbPath)) {
    final r = migrateToEncrypted(dbPath: dbPath, hexKey: key);
    if (!r.migrated) {
      return DbBootResult(
        dataDir: dir,
        status: DbBootStatus.migrationFailed,
        detail: r.reason,
        backupPath: r.backupPath,
        dirMoved: move.moved,
      );
    }
    markEncrypted(dir);
    final imgs = _migrateImages(dir, key);
    return DbBootResult(
      dataDir: dir,
      status: DbBootStatus.migrated,
      detail: 'رُحِّلت القاعدة إلى مشفَّرة (${r.rowsVerified} جدولاً محقَّقاً)'
          '$imgs',
      encryptionKey: key,
      backupPath: r.backupPath,
      dirMoved: move.moved,
    );
  }

  // ٥) قاعدة مشفَّرة قائمة، أو لا قاعدة بعد (ستُنشأ مشفَّرة عند أول فتح).
  markEncrypted(dir);
  final imgs = _migrateImages(dir, key);

  // ٦) طوق النجاة يُرفع بعد أن تُثبت المشفَّرة أنها تعمل.
  //
  //    النسخة السادة تفتح بلا مفتاح وتحوي كل شيء، فبقاؤها بجوار قاعدة
  //    مشفَّرة **يُبطل التشفير عملياً**. وكانت دالةُ حذفها موجودة لا
  //    يناديها إلا الاختبارات — أي أن كل تثبيت مُرقَّى كان سيحتفظ بنسخة
  //    مقروءة إلى الأبد. والحذف هنا لا في نهاية الترحيل: الوصول إلى هذه
  //    النقطة يعني إقلاعاً كاملاً لاحقاً نجح، وهو الإثبات المطلوب.
  final dropped =
      dropPlainBackupIfEncryptedHealthy(dbPath: dbPath, hexKey: key);

  return DbBootResult(
    dataDir: dir,
    status: recovered ? DbBootStatus.migrated : DbBootStatus.ready,
    detail: (recovered
            ? 'استُعيد ترحيلٌ مقطوع — القاعدة المشفَّرة أُعيدت إلى مكانها'
            : File(dbPath).existsSync()
                ? 'قاعدة مشفَّرة قائمة'
                : 'لا قاعدة بعد — ستُنشأ مشفَّرة') +
        imgs +
        (dropped ? ' — حُذفت النسخة السادة بعد التحقق' : ''),
    encryptionKey: key,
    dirMoved: move.moved,
  );
}

/// ينقل صور الأشعة السادة إلى الخزنة المشفَّرة — عمليةٌ عديمة الأثر تعود
/// فوراً حين لا شيء لينقَل.
///
/// إخفاقُها **لا يوقف الإقلاع**: الصور السادة تبقى مقروءةً كما كانت، وهو
/// وضعٌ لا يزيد سوءاً عمّا قبل هذه النسخة، بينما إيقاف العيادة عن العمل
/// لأجل صورةٍ لم تُنقل ضررٌ أكبر. والنتيجة تُذكر في التفصيل لا تُبتلع.
String _migrateImages(String dir, String key) {
  final imagesDir = p.join(dir, 'xray_images');
  if (!Directory(imagesDir).existsSync()) return '';
  EncryptedBlobVault? vault;
  try {
    vault = EncryptedBlobVault(dir: imagesDir, hexKey: key);
    final r = migratePlainImagesIntoVault(imagesDir: imagesDir, vault: vault);
    if (r.moved == 0 && r.failed == 0) return '';
    return ' — صور الأشعة: ${r.reason}';
  } catch (e) {
    return ' — تعذّر ترحيل صور الأشعة (بقيت كما هي): $e';
  } finally {
    vault?.close();
  }
}
