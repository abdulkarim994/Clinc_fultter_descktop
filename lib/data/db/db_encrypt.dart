/// ============================================================================
///  م83 — ترحيل القاعدة السادة إلى مشفَّرة: أخطر عملية في الخطة
/// ============================================================================
///
///  لماذا الحذر هنا أكثر من أي موضع آخر
///  ───────────────────────────────────
///  الترحيل يلمس **الملف الذي يحمل كل شيء**. خطأٌ في المزامنة يفقد تعديلاً؛
///  وخطأٌ هنا يفقد العيادة. ولذلك الترتيب مصمَّم بحيث **لا لحظة واحدة** يكون
///  فيها الأصل محذوفاً والبديل غير مُتحقَّق منه:
///
///    ١) نسخة احتياطية للأصل بجواره      ← الأصل لم يُمسّ بعد
///    ٢) تصدير إلى ملف مشفَّر جديد        ← الأصل لم يُمسّ بعد
///    ٣) **فتح المشفَّر والتحقق من عدّ الصفوف** ← الأصل لم يُمسّ بعد
///    ٤) إبدال ذرّي: المشفَّر مكان الأصل   ← نقطة التحوّل الوحيدة
///    ٥) العلامة على القرص
///
///  أي إخفاق قبل الخطوة ٤ يترك الأصل **سليماً كما كان**، ويُنظَّف المؤقّت.
///  وإخفاقٌ بعدها يترك النسخة الاحتياطية بجواره.
///
///  ولماذا `sqlcipher_export` لا نسخ الملف
///  ──────────────────────────────────────
///  التشفير يغيّر بنية الصفحات، فنسخ البايتات لا يُنتج قاعدة مشفَّرة.
///  و`sqlcipher_export` دالة SQLCipher نفسها: تقرأ المخطّط والبيانات من
///  القاعدة المفتوحة وتكتبها في المرفقة بمفتاحها. لا تفسير يدوي للصفحات.
///
///  ملاحظة سياق: المشروع في مرحلة البناء ولا بيانات مرضى حقيقية بعد، فأثر
///  إخفاق الترحيل اليوم محدود. والترتيب أعلاه مكتوبٌ **لأجل ما بعد ذلك** —
///  ترحيلُ قاعدة عيادة عاملة لا يُعاد تصميمه وقتها.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'db_key.dart';

class EncryptMigrationResult {
  const EncryptMigrationResult({
    required this.migrated,
    required this.reason,
    this.backupPath,
    this.rowsVerified = 0,
  });

  final bool migrated;
  final String reason;
  final String? backupPath;
  final int rowsVerified;
}

/// هل هذا الملف قاعدة **سادة** (غير مشفَّرة)؟
///
/// الفحص بالبايتات لا بمحاولة الفتح: ملف SQLite السادة يبدأ بالسلسلة
/// `SQLite format 3\0` حرفياً، والمشفَّر يبدأ بعشوائيّ. أرخص وأوثق من
/// محاولة فتحٍ قد ترمي لأسباب أخرى.
bool isPlainDatabase(String path) {
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() < 16) return false;
    final head = f.openSync()..setPositionSync(0);
    final bytes = head.readSync(16);
    head.closeSync();
    return String.fromCharCodes(bytes).startsWith('SQLite format 3');
  } catch (_) {
    return false;
  }
}

/// حالة ملف القاعدة على القرص — الدليل الذي يُبنى عليه قرار المفتاح.
enum DbFileState { absent, plain, encrypted }

DbFileState classifyDb(String path) {
  if (!File(path).existsSync()) return DbFileState.absent;
  return isPlainDatabase(path) ? DbFileState.plain : DbFileState.encrypted;
}

/// يُرحّل قاعدة سادة إلى مشفَّرة في مكانها. عديم الأثر: قاعدةٌ مشفَّرة
/// أصلاً أو ملفٌ غائب يعودان بلا عمل.
EncryptMigrationResult migrateToEncrypted({
  required String dbPath,
  required String hexKey,
}) {
  if (!File(dbPath).existsSync()) {
    return const EncryptMigrationResult(
        migrated: false, reason: 'لا قاعدة بعد — ستُنشأ مشفَّرة');
  }
  if (!isPlainDatabase(dbPath)) {
    return const EncryptMigrationResult(
        migrated: false, reason: 'مشفَّرة أصلاً');
  }

  final backup = '$dbPath.plain-backup';
  final tmp = '$dbPath.enc-tmp';

  Database? src;
  try {
    // ٠) تنظيف بقايا محاولة سابقة — **داخل** الحماية.
    //
    //    كان خارجها، وهو المسار الوحيد في متتالية الإقلاع كلها الذي يرمي
    //    بلا التقاط: على ويندوز يكفي أن يمسك مضادُّ فيروسات أو نسخةٌ ثانية
    //    من التطبيق ذلك الملف ليُخفق الحذف، فيهرب الاستثناء من الإقلاع
    //    ويرى المستخدم شاشةً سوداء بلا سطر تشخيص.
    for (final leftover in [tmp, '$tmp-wal', '$tmp-shm']) {
      final f = File(leftover);
      if (f.existsSync()) f.deleteSync();
    }

    // ١) نسخة احتياطية — قبل أي لمسة للأصل.
    //
    //    ⚠ نقطةُ تفتيش قبل النسخ. الترحيل يجري عند الإقلاع — أي غالباً
    //    بُعيد انطفاءٍ مفاجئ، وهي اللحظة التي يحمل فيها `-wal` آخر ما
    //    أُودع من الجلسة السابقة. ونسخُ الملف الرئيس وحده كان يُنتج
    //    «طوق نجاة» أقدم من القاعدة المشفَّرة الناتجة: المشفَّرة تُصدَّر من
    //    مقبض مفتوح يقرأ WAL، والنسخة لا. من يستعيدها يفقد آخر جلسة
    //    ولا يعلم. (رُصد بالقياس: 2 مقابل 1.)
    final pre = sqlite3.open(dbPath);
    try {
      pre.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      pre.close();
    }
    File(dbPath).copySync(backup);

    // ٢) تصدير إلى مشفَّر جديد.
    src = sqlite3.open(dbPath);
    src.execute("ATTACH DATABASE ? AS enc KEY ${pragmaKeyLiteral(hexKey)}",
        [tmp]);
    src.execute("SELECT sqlcipher_export('enc')");
    src.execute('DETACH DATABASE enc');
    src.close();
    src = null;

    // ٣) التحقق قبل الإبدال: يُفتح بالمفتاح، ويُقرأ منه فعلاً.
    //    مجرّد وجود الملف لا يكفي — قد يكون فارغاً أو نصفياً.
    final check = sqlite3.open(tmp);
    var rows = 0;
    try {
      check.execute("PRAGMA key = ${pragmaKeyLiteral(hexKey)}");
      final t = check.select(
          "SELECT count(*) AS n FROM sqlite_master WHERE type='table'");
      rows = (t.first['n'] as int?) ?? 0;
      if (rows == 0) throw StateError('المشفَّرة بلا جداول');
      // قراءة فعلية من جدول بيانات — الفتح وحده لا يُثبت سلامة المحتوى.
      check.select('SELECT count(*) FROM patients');
    } finally {
      check.close();
    }

    // ٤) نقطة التحوّل الوحيدة — وترتيبها يُقلّص نافذة الموت إلى صفر.
    //
    //    كان: احذف الأصل ثم أعد التسمية. وبينهما نافذةٌ إن مات التطبيق
    //    فيها (انقطاع كهرباء — وهو السيناريو الذي يدّعي هذا الملف حمايته)
    //    فلا قاعدة على القرص إطلاقاً، والبيانات كلها في `.enc-tmp` الذي
    //    لا ينظر إليه أحد بعدها. والإقلاع التالي يرى «لا قاعدة» فيُنشئ
    //    **فارغةً** — أي ذاتُ الكارثة التي بُنيت المتتالية كلها لمنعها.
    //
    //    والآن: إعادة تسمية مباشرة فوق الهدف. على أنظمة POSIX هذه عملية
    //    ذرّية (`rename(2)`) لا نافذة فيها البتّة. وويندوز يرفض التسمية
    //    فوق موجود، فيُحتفظ بالمسار القديم استثناءً له — ويحرسه
    //    [recoverInterruptedMigration] عند الإقلاع.
    //
    //    والجانبيّان يُحذفان **قبل** التسمية لا بعدها: بقاء `-wal` يخصّ
    //    القاعدة القديمة بجوار ملفٍ جديد يُتلف الجديد.
    for (final side in ['-wal', '-shm']) {
      final f = File('$dbPath$side');
      if (f.existsSync()) f.deleteSync();
    }
    try {
      File(tmp).renameSync(dbPath);
    } on FileSystemException {
      final old = File(dbPath);
      if (old.existsSync()) old.deleteSync();
      File(tmp).renameSync(dbPath);
    }

    return EncryptMigrationResult(
      migrated: true,
      reason: 'رُحِّلت إلى مشفَّرة',
      backupPath: backup,
      rowsVerified: rows,
    );
  } catch (e) {
    // فشلٌ قبل الإبدال ⇒ الأصل سليم. يُنظَّف المؤقّت ولا يُلمس شيء آخر.
    try {
      src?.close();
    } catch (_) {}
    for (final leftover in [tmp, '$tmp-wal', '$tmp-shm']) {
      final f = File(leftover);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    return EncryptMigrationResult(
      migrated: false,
      reason: 'أخفق الترحيل — الأصل سليم كما كان: $e',
      backupPath: File(backup).existsSync() ? backup : null,
    );
  }
}

/// يحذف النسخة الاحتياطية السادة **بعد** أن يتأكد المالك.
///
/// لا تُحذف تلقائياً: نسخةٌ سادة بجوار قاعدة مشفَّرة تُبطل التشفير عملياً،
/// لكن حذفها قبل التأكد من عمل المشفَّرة يُلغي طوق النجاة. الحذف فعلٌ
/// صريح — والتوثيق يذكّر به.
bool dropPlainBackup(String dbPath) {
  try {
    final f = File('$dbPath.plain-backup');
    if (!f.existsSync()) return false;
    f.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

bool hasPlainBackup(String dbPath) =>
    File('$dbPath.plain-backup').existsSync();

/// يستعيد ترحيلاً قُطع في نافذة الإبدال على ويندوز.
///
/// الحالة: لا قاعدة في مكانها، و`.enc-tmp` موجود ويفتح بالمفتاح. عندها
/// المشفَّرة هي البيانات الحقيقية — نقلها إلى مكانها استرجاعٌ لا مجازفة.
///
/// وبلا هذا الفحص يرى الإقلاع «لا قاعدة» فيُنشئ فارغة، وتظنّ العيادة أن
/// بياناتها تبخّرت بينما هي كاملة في ملفٍ بجوارها.
bool recoverInterruptedMigration({
  required String dbPath,
  required String hexKey,
}) {
  if (File(dbPath).existsSync()) return false;
  final tmp = '$dbPath.enc-tmp';
  if (!File(tmp).existsSync()) return false;

  Database? check;
  try {
    check = sqlite3.open(tmp);
    check.execute("PRAGMA key = ${pragmaKeyLiteral(hexKey)}");
    final t = check.select(
        "SELECT count(*) AS n FROM sqlite_master WHERE type='table'");
    if (((t.first['n'] as int?) ?? 0) == 0) return false;
    check.select('SELECT count(*) FROM patients');
  } catch (_) {
    return false; // لا يفتح بهذا المفتاح ⇒ ليس لنا، لا يُلمس
  } finally {
    try {
      check?.close();
    } catch (_) {}
  }

  try {
    File(tmp).renameSync(dbPath);
    for (final side in ['-wal', '-shm']) {
      final f = File('$tmp$side');
      if (f.existsSync()) f.renameSync('$dbPath$side');
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// يحذف النسخة السادة **بعد إثبات** أن المشفَّرة تعمل وتحمل البيانات.
///
/// لماذا آلياً لا بانتظار المالك: النسخة السادة تفتح بلا مفتاح وتحوي كل
/// شيء، فبقاؤها بجوار قاعدة مشفَّرة **يُبطل التشفير عملياً**. وقد كانت
/// دالة الحذف موجودة ولا يناديها إلا الاختبارات — أي أن كل تثبيت مُرقَّى
/// كان يحتفظ بنسخة مقروءة إلى الأبد، فينهار الغرض كله عند أول تدقيق.
///
/// والشرط يحفظ طوق النجاة: لا يُحذف شيء حتى تُفتح المشفَّرة بالمفتاح
/// **ويُقرأ منها جدول بيانات فعلاً** — أي بعد إقلاعٍ ناجح كامل، لا بمجرّد
/// انتهاء الترحيل.
bool dropPlainBackupIfEncryptedHealthy({
  required String dbPath,
  required String hexKey,
}) {
  if (!hasPlainBackup(dbPath)) return false;
  if (classifyDb(dbPath) != DbFileState.encrypted) return false;

  Database? db;
  try {
    db = sqlite3.open(dbPath);
    db.execute("PRAGMA key = ${pragmaKeyLiteral(hexKey)}");
    db.select('SELECT count(*) FROM patients');
  } catch (_) {
    return false; // لا تُثبت سلامتها ⇒ يبقى الطوق
  } finally {
    try {
      db?.close();
    } catch (_) {}
  }
  return dropPlainBackup(dbPath);
}
