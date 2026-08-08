/// ============================================================================
///  م83 — مجلد البيانات على ويندوز: من Roaming إلى Local
/// ============================================================================
///
///  العلة
///  ─────
///  `getApplicationSupportDirectory()` تعيد على ويندوز مساراً تحت
///  `%APPDATA%` — أي **Roaming**. وعلى أي شبكة عيادة فيها نطاق (domain) أو
///  ملفّات تعريف متنقّلة، محتوى Roaming **يُنسخ إلى خادم الشبكة** عند كل
///  تسجيل خروج ودخول. النتيجة مشكلتان لا واحدة:
///
///    ١) خصوصية — قاعدة المرضى تُنسخ إلى خادم لا يعلم به المالك ولا يشمله
///       تشفيرُ الجهاز، وقد يحتفظ بها احتياطياً سنوات.
///    ٢) سلامة — SQLite على مسار يُزامَن خلف ظهر التطبيق وصفةٌ معروفة
///       للتلف: نسخُ ملف WAL وملف القاعدة في لحظتين مختلفتين يُنتج قاعدة
///       غير متّسقة.
///
///  والتشفير لا يُلغي هذا: يُغلق باب الخصوصية جزئياً ويترك باب التلف
///  مفتوحاً على مصراعيه — قاعدةٌ مشفَّرةٌ تالفة ليست أفضل حالاً.
///
///  العلاج
///  ──────
///  `%LOCALAPPDATA%` لا يتنقّل. والمسار الجديد هو توأم القديم حرفياً مع
///  `\Local\` بدل `\Roaming\`، فبنيةُ المجلد وأسماؤه لا تتغيّر.
///
///  النقل مرّة واحدة وبأمان
///  ───────────────────────
///  المجلد يحوي أكثر من القاعدة: WAL وSHM، وإعداد السحابة، والجلسة، وسجل
///  الأعطال، والصادرات، وصور الأشعة، وعلامة التشفير. النقل ينقل **المجلد
///  كله** — نقلُ القاعدة وحدها يفصلها عن مفتاحها وإعدادها.
///
///  والترتيب يضمن ألّا تختفي البيانات في أي لحظة:
///    ١) الوجهة موجودة ومأهولة   ⇒ لا نقل (نُقل سابقاً — والوجهة هي الحقيقة)
///    ٢) المصدر غائب أو فارغ     ⇒ لا نقل (تثبيت جديد)
///    ٣) غير ذلك: إعادة تسمية ذرّية، وعند تعذّرها نسخٌ ثم تحقّق ثم حذف
///
///  ولا يُحذف المصدر إلا بعد التحقق من وصول كل ملف. وإخفاق أي خطوة يعود
///  بالمسار **القديم** — العمل على مسار ناقص أسوأ من العمل على مسار
///  غير مثالي.
///
///  متى يُستدعى: قبل فتح القاعدة بأي شيء — أي في الإقلاع قبل `runApp`.
///  استدعاؤه وقاعدةٌ مفتوحة يعني نقل ملف مقفول، ويفشل على ويندوز.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class DataDirMove {
  const DataDirMove({
    required this.dir,
    required this.moved,
    required this.reason,
    this.filesMoved = 0,
  });

  /// المسار الذي **يجب** أن يُستعمل بعد هذه المكالمة.
  final String dir;
  final bool moved;
  final String reason;
  final int filesMoved;
}

/// هل هذا المسار داخل ملف تعريف متنقّل؟
///
/// الفحص نصّي على `\Roaming\` لأن ويندوز يبنيها كذلك دائماً
/// (`C:\Users\x\AppData\Roaming\...`). ويُقبل الفاصل الأمامي أيضاً لأن
/// Dart يقبله على ويندوز وتستعمله الاختبارات.
bool isRoamingPath(String path) =>
    path.contains(r'\Roaming\') || path.contains('/Roaming/');

/// يحسب توأم المسار تحت `Local`.
String localTwinOf(String roamingPath) => roamingPath
    .replaceFirst(r'\Roaming\', r'\Local\')
    .replaceFirst('/Roaming/', '/Local/');

bool _hasContent(Directory d) {
  if (!d.existsSync()) return false;
  try {
    return d.listSync().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// ينقل مجلد البيانات من Roaming إلى Local مرّة واحدة، ويعيد المسار المعتمد.
///
/// عديم الأثر: استدعاؤه مراراً بعد النقل الأول يعود فوراً بمسار Local.
/// وعلى غير ويندوز يعود بالمسار كما هو بلا لمس شيء.
DataDirMove ensureNonRoamingDataDir(
  String supportPath, {
  bool isWindows = false,
}) {
  if (!isWindows || !isRoamingPath(supportPath)) {
    return DataDirMove(
      dir: supportPath,
      moved: false,
      reason: 'ليس مساراً متنقّلاً — لا نقل',
    );
  }

  final target = localTwinOf(supportPath);
  final src = Directory(supportPath);
  final dst = Directory(target);

  // ١) نُقل سابقاً: الوجهة مأهولة ⇒ هي الحقيقة، ولا يُدمج المصدر فوقها.
  //    الدمج قد يُعيد ملفاً قديماً فوق أحدث منه — والصمت هنا أخطر من التكرار.
  if (_hasContent(dst)) {
    return DataDirMove(
      dir: target,
      moved: false,
      reason: 'المسار المحلي مأهول أصلاً — نُقل سابقاً',
    );
  }

  // ٢) لا شيء يُنقل: تثبيت جديد ⇒ نبدأ في Local مباشرةً.
  if (!_hasContent(src)) {
    try {
      dst.createSync(recursive: true);
    } catch (_) {
      return DataDirMove(
        dir: supportPath,
        moved: false,
        reason: 'تعذّر إنشاء المسار المحلي — يُستعمل القديم',
      );
    }
    return DataDirMove(
      dir: target,
      moved: false,
      reason: 'تثبيت جديد — يبدأ محلياً بلا نقل',
    );
  }

  // ٣) نقلٌ فعليّ.
  final names = src
      .listSync()
      .map((e) => p.basename(e.path))
      .toList(growable: false);
  try {
    dst.parent.createSync(recursive: true);
    try {
      // المسار السعيد: إعادة تسمية ذرّية — Roaming وLocal على القرص نفسه.
      src.renameSync(target);
    } on FileSystemException {
      // احتياط حين تتعذّر التسمية (أقراص مختلفة مثلاً).
      //
      // ⚠ النسخ إلى **مسار جانبي** ثم تسمية المجلد — لا نسخٌ مباشر إلى
      // الوجهة. والسبب أن النسخ المباشر يترك عند أي انقطاع مجلدَ وجهةٍ
      // ناقصاً، فيراه الإقلاع التالي «مأهولاً» فيعتمده حقيقةً ويهجر
      // المصدر السليم إلى الأبد — وقد يكون ما وصل من القاعدة نصفَ ملف.
      // (رُصد بالمحاكاة: وجهةٌ فيها ملف إعداد وحده كفت لهجر القاعدة.)
      // والتسمية في النهاية تجعل الوجهة تظهر كاملةً أو لا تظهر.
      final staging = Directory('$target.partial');
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      _copyTree(src, staging);
      for (final n in names) {
        final got = FileSystemEntity.typeSync(p.join(staging.path, n));
        if (got == FileSystemEntityType.notFound) {
          staging.deleteSync(recursive: true);
          throw FileSystemException('لم يصل «$n» إلى الوجهة', target);
        }
      }
      if (dst.existsSync()) dst.deleteSync(recursive: true); // فارغٌ حتماً
      staging.renameSync(target);
      src.deleteSync(recursive: true);
    }
  } catch (e) {
    // الأصل سليم: إما لم يُمسّ، أو نُسخ ولم يُحذف. نبقى عليه.
    return DataDirMove(
      dir: supportPath,
      moved: false,
      reason: 'أخفق النقل — يُستعمل المسار القديم سليماً: $e',
    );
  }

  // فتاتُ خبز لمن يبحث في المكان القديم.
  try {
    Directory(supportPath).createSync(recursive: true);
    File(p.join(supportPath, 'MOVED_TO.txt')).writeAsStringSync(
      'انتقلت بيانات التطبيق إلى:\n$target\n\n'
      'السبب: مجلد Roaming يُنسخ إلى خادم الشبكة في بيئات النطاق، '
      'وهو غير مناسب لقاعدة بيانات مرضى.\n',
    );
  } catch (_) {/* أفضل جهد — غيابها لا يؤثر */}

  return DataDirMove(
    dir: target,
    moved: true,
    reason: 'نُقل من Roaming إلى Local',
    filesMoved: names.length,
  );
}

void _copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      _copyTree(entity, Directory(p.join(to.path, name)));
    } else if (entity is File) {
      entity.copySync(p.join(to.path, name));
    }
  }
}
