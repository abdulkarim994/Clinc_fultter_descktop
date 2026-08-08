/// ============================================================================
///  إعدادات موزّعة على صفوف مستقلة — v30
/// ============================================================================
///
///  المشكلة: كل الإعدادات كانت تعيش في **صف واحد** (`app.config`) يُحفظ
///  كاملاً من لقطة الواجهة، والخادم يحسم الصف كاملاً بالساعة الأحدث ⇒
///  إضافة عيادة/معالجة/مختبر من جهازين في نفس الوقت: الأخير يفوز والآخر
///  يُمحى؛ وحفظٌ من لقطة قديمة يُرجع قيمة قديمة ويختمها فتغلب الآخر.
///
///  الحل (نفس دواء خطة العلاج في v29): **كل ورقة إعداد وكل عنصر قائمة
///  صفٌّ مستقل يتزامن بنفسه**:
///      `cfg:s:(مسار الورقة)`                = { v: القيمة }
///      `cfg:l:(مسار القائمة):(بصمة العنصر)`  = { v: العنصر, o: الترتيب }
///  والحذف = شاهد قبر على الصف نفسه (حتمي بلا بعث).
///
///  التوافق مع كل الكود القائم: الكتلة القديمة تبقى **أساساً للقراءة**
///  وتُركَّب فوقها صفوف الأوراق والعناصر، فيحصل التطبيق على «كائن إعدادات»
///  بنفس الشكل تماماً — بلا تغيير في أي موضع قراءة أو في شاشة الإعدادات.
library;

import 'dart:convert';

/// بادئة صف ورقة إعداد واحدة.
const String kCfgLeafPrefix = 'cfg:s:';

/// بادئة صف عنصر قائمة.
const String kCfgItemPrefix = 'cfg:l:';

/// بصمة خاصة تعني «القائمة موجودة لكنها فارغة».
const String kEmptyListSlug = '__empty__';

/// مفاتيح لا يديرها هذا النظام: بيانات وصفية للدمج فقط. أما
/// `treatmentPlans` فتُدار كبقية الإعدادات (كل مرحلة عنصر قائمة = صف
/// مستقل) — وهي مجرد أرشيف يقرأه مخزن الخطة الجديد (v29) للاستيراد.
const Set<String> kUnmanagedConfigKeys = {
  '_fmeta',
  '_tombs',
};

// ── ترميز المسارات (اسم قد يحتوي نقطة أو نقطتين أو ~) ──────────────────
String encSeg(String s) =>
    s.replaceAll('~', '~0').replaceAll('.', '~1').replaceAll(':', '~2');

String decSeg(String s) =>
    s.replaceAll('~2', ':').replaceAll('~1', '.').replaceAll('~0', '~');

String joinCfgPath(List<String> segs) => segs.map(encSeg).join('.');

List<String> splitCfgPath(String path) =>
    path.split('.').map(decSeg).toList();

/// صف إعداد كما يُقرأ من القاعدة.
class CfgRow {
  const CfgRow(this.value, this.deleted);
  final Object? value;
  final bool deleted;
}

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};

bool cfgDeepEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!cfgDeepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !cfgDeepEqual(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// بصمة عنصر قائمة: القيمة نفسها للقيم البسيطة، والمعرّف (أو تمثيلها)
/// للكائنات — ثابتة على كل الأجهزة فلا يتكرر العنصر ولا يضيع.
String itemSlug(Object? item) {
  if (item is Map) {
    final id = item['id'];
    if (id != null && '$id'.isNotEmpty) return '$id';
    return jsonEncode(item);
  }
  return '$item';
}

Object? _getPath(Map<String, Object?> root, List<String> segs) {
  Object? cur = root;
  for (final s in segs) {
    if (cur is Map && cur.containsKey(s)) {
      cur = cur[s];
    } else {
      return null;
    }
  }
  return cur;
}

void _setPath(
    Map<String, Object?> root, List<String> segs, Object? value) {
  var cur = root;
  for (var i = 0; i < segs.length - 1; i++) {
    final k = segs[i];
    final nxt = cur[k];
    final m =
        nxt is Map ? Map<String, Object?>.from(nxt) : <String, Object?>{};
    cur[k] = m;
    cur = m;
  }
  cur[segs.last] = value;
}

void _removePath(Map<String, Object?> root, List<String> segs) {
  var cur = root;
  for (var i = 0; i < segs.length - 1; i++) {
    final k = segs[i];
    final nxt = cur[k];
    if (nxt is! Map) return;
    final m = Map<String, Object?>.from(nxt);
    cur[k] = m;
    cur = m;
  }
  cur.remove(segs.last);
}

bool _pathExists(Map<String, Object?> root, List<String> segs) {
  Object? cur = root;
  for (final s in segs) {
    if (cur is Map && cur.containsKey(s)) {
      cur = cur[s];
    } else {
      return false;
    }
  }
  return true;
}

/// يركّب كائن الإعدادات: الكتلة القديمة أساساً، ثم صفوف الأوراق، ثم
/// صفوف عناصر القوائم (بشواهد قبورها).
Map<String, Object?> assembleConfig({
  required Map<String, Object?> blob,
  required Map<String, CfgRow> leafRows,
  required Map<String, CfgRow> itemRows,
}) {
  final out = (jsonDecode(jsonEncode(blob)) as Map).cast<String, Object?>();

  // ① الأوراق: كل صف يكتب قيمته في مساره (والمحذوف يزيل مساره).
  final leafKeys = leafRows.keys.toList()..sort();
  for (final key in leafKeys) {
    final row = leafRows[key]!;
    final segs = splitCfgPath(key.substring(kCfgLeafPrefix.length));
    if (segs.isEmpty) continue;
    if (row.deleted) {
      // شاهد قبر: نُبقي المفتاح الأعلى موجوداً كخريطة (شكل الإعدادات
      // القديم: حذف بطاقة مريض يزيل مفتاحه ويبقي الخريطة الحاوية).
      if (segs.length >= 2 && out[segs.first] is! Map) {
        out[segs.first] = <String, Object?>{};
      }
      _removePath(out, segs);
    } else {
      _setPath(out, segs, _asMap(row.value)['v']);
    }
  }

  // تقليم الخرائط الفارغة تحت المستوى الأول (فمفتاح مريض حُذفت كل حقوله
  // يختفي، بينما تبقى الخريطة الحاوية موجودة كما كان الشكل القديم).
  void pruneEmpty(Map<String, Object?> m, int depth) {
    final drop = <String>[];
    for (final e in m.entries) {
      final v = e.value;
      if (v is Map) {
        final mm = Map<String, Object?>.from(v);
        pruneEmpty(mm, depth + 1);
        m[e.key] = mm;
        if (mm.isEmpty && depth >= 1) drop.add(e.key);
      }
    }
    for (final k in drop) {
      m.remove(k);
    }
  }

  // ② القوائم: تُبنى من عناصر الكتلة ثم تُطبَّق عليها صفوف العناصر.
  final byList = <String, List<({String slug, CfgRow row})>>{};
  for (final e in itemRows.entries) {
    final rest = e.key.substring(kCfgItemPrefix.length);
    final cut = rest.lastIndexOf(':');
    if (cut <= 0) continue;
    final listPath = rest.substring(0, cut);
    final slug = decSeg(rest.substring(cut + 1));
    (byList[listPath] ??= []).add((slug: slug, row: e.value));
  }

  for (final entry in byList.entries) {
    final segs = splitCfgPath(entry.key);
    // شكل الإعدادات القديم: تبقى الخريطة الحاوية العليا موجودة وإن أُزيل
    // مدخلها (مثل treatmentPlans بعد حذف خطة مريض).
    if (segs.length >= 2 && out[segs.first] is! Map) {
      out[segs.first] = <String, Object?>{};
    }
    final base = _getPath(out, segs);
    final items = <String, Object?>{}; // بصمة → قيمة
    final order = <String, num>{};
    var i = 0;
    if (base is List) {
      for (final el in base) {
        final s = itemSlug(el);
        items[s] = el;
        order[s] = i++;
      }
    }
    var emptyMarker = false;
    for (final r in entry.value) {
      if (r.slug == kEmptyListSlug) {
        // علامة «قائمة فارغة»: القائمة موجودة بلا عناصر بقرار المستخدم.
        emptyMarker = !r.row.deleted;
        continue;
      }
      if (r.row.deleted) {
        items.remove(r.slug);
        order.remove(r.slug);
        continue;
      }
      final v = _asMap(r.row.value);
      items[r.slug] = v['v'];
      order[r.slug] =
          v['o'] is num ? v['o'] as num : (order[r.slug] ?? i++);
    }
    final slugs = items.keys.toList()
      ..sort((a, b) {
        final c = (order[a] ?? 0).compareTo(order[b] ?? 0);
        return c != 0 ? c : a.compareTo(b);
      });
    if (slugs.isEmpty && !emptyMarker) {
      // كل العناصر محذوفة بلا علامة «فارغة» ⇒ المسار نفسه محذوف (حذف
      // مدخل كامل مثل خطة مريض أُزيل) — لا نُبقي قائمة فارغة شبحية.
      _removePath(out, segs);
      continue;
    }
    _setPath(out, segs, [for (final s in slugs) items[s]]);
  }

  pruneEmpty(out, 0);
  return out;
}

/// أمر كتابة واحد ناتج عن الفرق.
class CfgWrite {
  const CfgWrite(this.key, this.value, {this.delete = false});
  final String key;
  final Object? value;
  final bool delete;
}

/// يحسب فرق «ما قبل» و«ما بعد» ويعيد أوامر كتابة الصفوف المتأثرة فقط —
/// فلا يُلمس أي إعداد لم يغيّره المستخدم (وهو ما يحمي عمل الجهاز الآخر).
List<CfgWrite> diffConfigToRows(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final out = <CfgWrite>[];

  void walk(List<String> segs, Object? b, Object? a) {
    if (segs.isNotEmpty && kUnmanagedConfigKeys.contains(segs.first)) {
      return;
    }
    final path = joinCfgPath(segs);

    // قائمة على أي جانب ⇒ صف لكل عنصر.
    if (a is List || b is List) {
      final bl = b is List ? b : const [];
      final al = a is List ? a : const [];
      final bSlugs = <String, Object?>{};
      for (final el in bl) {
        bSlugs[itemSlug(el)] = el;
      }
      for (var i = 0; i < al.length; i++) {
        final slug = itemSlug(al[i]);
        final prev = bSlugs[slug];
        final samePlace = bl.length > i && itemSlug(bl[i]) == slug;
        if (prev == null || !cfgDeepEqual(prev, al[i]) || !samePlace) {
          out.add(CfgWrite(
              '$kCfgItemPrefix$path:${encSeg(slug)}', {'v': al[i], 'o': i}));
        }
      }
      // حذف عنصر غائب عن الكتابة الجديدة ⇒ شاهد قبر على صفه (حتمي بلا
      // بعث). ملاحظة v30: قوائم الإعدادات الحسّاسة (العيادات/المعالجات/
      // طرق الدفع) تُعدّل بنداءات نية صريحة لا بكتابة قائمة كاملة، فلا
      // يمكن لحفظٍ من لقطة قديمة أن يمحو عنصراً أضافه جهاز آخر.
      final aSlugs = <String>{for (final el in al) itemSlug(el)};
      for (final slug in bSlugs.keys) {
        if (!aSlugs.contains(slug)) {
          out.add(CfgWrite('$kCfgItemPrefix$path:${encSeg(slug)}', null,
              delete: true));
        }
      }
      // علامة «قائمة فارغة» تُكتب فقط إذا كانت القائمة موجودة فعلاً
      // وفُرّغت بقرار المستخدم — لا عند حذف المسار كله (حذف مدخل).
      if (al.isEmpty && _pathExists(after, segs)) {
        out.add(CfgWrite(
            '$kCfgItemPrefix$path:${encSeg(kEmptyListSlug)}', {'v': null}));
      } else if (al.isEmpty) {
        out.add(CfgWrite(
            '$kCfgItemPrefix$path:${encSeg(kEmptyListSlug)}', null,
            delete: true));
      }
      return;
    }

    // خريطتان ⇒ تعمّق مفتاحاً بمفتاح.
    if (a is Map || b is Map) {
      final bm = _asMap(b);
      final am = _asMap(a);
      // خريطة فارغة صريحة ⇒ صف يُثبت وجود المفتاح (شكل الإعدادات القديم:
      // `treatmentPlans: {}` تبقى موجودة بعد حذف آخر مدخل).
      if (a is Map && am.isEmpty && segs.isNotEmpty) {
        out.add(CfgWrite('$kCfgLeafPrefix$path', <String, Object?>{
          'v': <String, Object?>{},
        }));
      }
      final keys = <String>{...bm.keys, ...am.keys};
      for (final k in keys) {
        walk([...segs, k], bm[k], am[k]);
      }
      return;
    }

    // ورقة.
    if (segs.isEmpty) return;
    final existedBefore = _pathExists(before, segs);
    final existsAfter = _pathExists(after, segs);
    if (!existsAfter && existedBefore) {
      // v30 — تفضيل مفرد (المستوى الأول) لا يُحذف أبداً بغيابه عن كتابة
      // كاملة: الغياب يعني «لقطة قديمة لا تعرفه» لا «حذفتُه» (التطبيق لا
      // يحذف تفضيلاً، إنما يعدّله). الأعماق الأدنى (بطاقة مريض، نسبة
      // معالجة) يبقى حذفها معتبراً بشاهد قبر.
      if (segs.length == 1) return;
      out.add(CfgWrite('$kCfgLeafPrefix$path', null, delete: true));
      return;
    }
    if (existsAfter && (!existedBefore || !cfgDeepEqual(b, a))) {
      out.add(CfgWrite('$kCfgLeafPrefix$path', {'v': a}));
    }
  }

  final keys = <String>{...before.keys, ...after.keys};
  for (final k in keys) {
    if (kUnmanagedConfigKeys.contains(k)) continue;
    walk([k], before[k], after[k]);
  }
  return out;
}
