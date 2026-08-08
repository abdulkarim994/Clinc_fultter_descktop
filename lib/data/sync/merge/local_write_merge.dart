/// ============================================================================
///  كتابة الإعدادات عبر الدمج — إضافة v28
/// ============================================================================
///
///  الواجهة تحفظ **كائن الإعدادات كاملاً** من لقطة قرأتها قبل لحظات. إذا
///  وصلت مرحلة أو حقل من جهاز آخر ودُمج في القاعدة بين لحظة القراءة ولحظة
///  الحفظ، فالحفظ يكتب فوقه ويمحوه محلياً — ثم يختم الورقة المتراجعة بساعة
///  جديدة فتنتصر على الجهاز الآخر عند المزامنة. هذا بالضبط ما يحدث حين
///  تعمل نسختان من التطبيق بنفس الحساب معاً.
///
///  العلاج: قبل الكتابة نعيد دمج **الأشجار المختومة** مع القيمة المخزّنة
///  لحظة الكتابة، بقرار الساعة لكل ورقة: ما غيّرته الواجهة يفوز بساعته
///  الجديدة، وكل ما لم تلمسه يبقى كما في القاعدة. بقية مفاتيح الإعدادات
///  تبقى بسلوكها الأصلي (الكتابة المحلية تفوز) حتى لا يُلغى حذف متعمّد
///  لعيادة أو معالجة من شاشة الإعدادات.
library;

import 'config_fmeta.dart';
import 'config_tombs.dart';
import 'descriptors.dart';
import 'merge_engine.dart';

Map<String, Object?> _mapOf(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};

/// يدمج كتابة محلية واردة من الواجهة فوق القيمة المخزّنة. نقي.
Map<String, Object?> mergeLocalWriteIntoStored({
  required Map<String, Object?> stored,
  required Map<String, Object?> incoming,
  required bool Function(String?, String?) isNewer,
}) {
  final lMeta = readFMeta(incoming);
  final rMeta = readFMeta(stored);
  final out = Map<String, Object?>.from(incoming);

  for (final key in kStampedConfigKeys) {
    final hasStored = stored.containsKey(key);
    final hasIncoming = incoming.containsKey(key);
    if (!hasStored) continue;
    if (!hasIncoming) {
      out[key] = stored[key];
      continue;
    }
    final merged = mergeRecordValues(
      strategy: MergeStrategy(
        kind: 'object',
        defaultStrategy: scalarStrategy,
        fields: {key: deepStrategy()},
      ),
      base: missing,
      local: {key: incoming[key]},
      remote: {key: stored[key]},
      // تعادل ساعات الصف: القرار يعود لساعات الحقول، وعند غيابها تفوز
      // الكتابة المحلية (سلوك الأصل: آخر ما كتبه المستخدم على جهازه).
      localHlc: null,
      remoteHlc: null,
      isNewer: isNewer,
      localMeta: lMeta,
      remoteMeta: rMeta,
    );
    if (merged.containsKey(key)) out[key] = merged[key];
  }

  // شواهد الحذف: اتحاد محض (لا يفقد شاهداً)، ثم تقليم أثر المحذوف.
  final tombs = <String, Object?>{};
  for (final src in [_mapOf(stored[kConfigTombsKey]), _mapOf(incoming[kConfigTombsKey])]) {
    for (final e in src.entries) {
      tombs[e.key] = {..._mapOf(tombs[e.key]), ..._mapOf(e.value)};
    }
  }
  if (tombs.isNotEmpty) out[kConfigTombsKey] = tombs;

  final meta = mergeFMeta(rMeta, lMeta, isNewer);
  if (meta.isNotEmpty) out[kConfigFMetaKey] = meta;

  return pruneTombstoned(out);
}
