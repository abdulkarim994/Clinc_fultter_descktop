/// ============================================================================
///  كنّاس المؤقتات — لا يبقى ملفٌّ حساسٌ غير مشفَّر خارج القاعدة
/// ============================================================================
///
///  (قرار المالك — Windows Desktop Security §خامساً «حماية الملفات»):
///  «عدم ترك ملفات مؤقتة غير مشفَّرة، وحذفها بعد استخدامها، وتنظيف الموارد
///  عند إغلاق التطبيق».
///
///  ما الذي يُكنَس
///  ─────────────
///  التطبيق يكتب — في مساراتٍ معروفة — ملفاتٍ مؤقتة **مقروءة** بطبيعتها:
///    • تقارير PDF في `{dataDir}/exports/` (توأم print_service): تحمل
///      أسماء مرضى ومبالغ، وتخرج من حماية التشفير بالتعريف.
///    • أي `tmp/`/`cache/` داخل مجلد البيانات.
///    • مؤقتات النظام التي يخلّفها منتقي الملفات/الطباعة تحت مجلد مؤقت
///      خاص بالتطبيق (نُنشئه بادئة `dental_` كي لا نلمس مؤقتات غيرنا).
///
///  متى يُكنَس
///  ─────────
///    • عند الإقلاع (سطح المكتب): تنظيف ما خلّفته جلسةٌ أُغلقت فجأة.
///    • عند إغلاق النافذة: عبر مراقب دورة الحياة في الصدفة المكتبية.
///    • ضمن الخروج المصنعي: مسحٌ شامل (يستدعي [sweepEphemeral]).
///
///  الأمان أولاً: الكنس **أفضل جهد** لا يرمي أبداً — فشلُ حذف ملفٍ مؤقتٍ
///  لا يمنع الإقلاع ولا الإغلاق. لكنه لا يلمس القاعدة ولا الخزنة ولا
///  الإعداد — تلك ليست «مؤقتات».
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// المجلدات المؤقتة داخل مجلد البيانات التي يجوز كنسها بالكامل.
const List<String> _kEphemeralSubdirs = ['exports', 'tmp', 'cache'];

/// يكنس المؤقتات المعروفة داخل [dataDir] وأي مجلد مؤقت نظامي ببادئة
/// التطبيق. أفضل جهد — يبتلع كل خطأ. [removeExports] يتحكم بحذف
/// الصادرات (نحذفها في الإقلاع والإغلاق؛ الخروج المصنعي يحذفها أصلاً).
Future<int> sweepEphemeral(String dataDir, {bool removeExports = true}) async {
  var removed = 0;
  for (final sub in _kEphemeralSubdirs) {
    if (sub == 'exports' && !removeExports) continue;
    removed += _wipeContents(p.join(dataDir, sub));
  }
  // مؤقتات النظام الخاصة بالتطبيق (بادئة dental_) — لا نلمس غيرها.
  try {
    final sysTmp = Directory.systemTemp;
    if (sysTmp.existsSync()) {
      for (final e in sysTmp.listSync(followLinks: false)) {
        final base = p.basename(e.path);
        if (!base.startsWith('dental_')) continue;
        try {
          e.deleteSync(recursive: true);
          removed++;
        } catch (_) {/* مقفول/محذوف — تخطَّ */}
      }
    }
  } catch (_) {/* لا وصول لمؤقت النظام — تخطَّ */}
  return removed;
}

/// يفرّغ محتويات مجلدٍ دون حذف المجلد نفسه (كي يبقى جاهزاً للكتابة).
/// يعيد عدد العناصر المحذوفة. أفضل جهد.
int _wipeContents(String dirPath) {
  var n = 0;
  try {
    final d = Directory(dirPath);
    if (!d.existsSync()) return 0;
    for (final e in d.listSync(followLinks: false)) {
      try {
        e.deleteSync(recursive: true);
        n++;
      } catch (_) {/* عنصر مقفول — تخطَّ */}
    }
  } catch (_) {/* لا وصول — تخطَّ */}
  return n;
}
