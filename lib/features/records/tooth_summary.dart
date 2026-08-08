/// ============================================================================
///  م104 — تلخيص الأسنان للعرض المضغوط (بطاقة الملف + الطباعة)
/// ============================================================================
///
///  العُرف السريري نفسه: تُجمَع الأسنان حسب (الربع، الطقم) وتُرتَّب مواضعها
///  من الخط المتوسط وحشياً (1→8)، ثم تُضغَط المتتاليات إلى مدى:
///
///    فكٌّ علويٌّ كامل ⇒ خليتان: «1-8⌐» و«¬1-8» بدل 16 رقاقة.
///    فمٌ كامل (32 سناً) ⇒ 4 خلايا فقط.
///    متفرقة بربعٍ واحد ⇒ خلية واحدة: «1,3,5».
///
///  قاعدة المدى: **ثلاثة مواضع متتالية فأكثر** تُضغط إلى «أ-ب»؛ الموضعان
///  المتجاوران يبقيان صريحين «1,2» (المالك يريد معرفة رقم السن فوراً —
///  فلا نضغط إلا حيث يُختصر فعلاً).
///
///  النص حسب نظام العرض: Palmer موضعٌ مجرّد (لبني A-E) مع إطار الربع،
///  وFDI رقمان كاملان لكل طرف («11-13»، لبني «51-55») بلا إطار.
///
///  عرضٌ محضٌ فوق التخزين المحايد `{q,n,d?}` — لا يكتب شيئاً.
library;

import 'tooth_notation.dart';

/// مرجع سنٍّ خفيف للتلخيص (ربع، موضع، لبني؟).
typedef ToothRef = ({String q, int n, bool primary});

/// مجموعة عرضٍ واحدة: نص المدى/القائمة + الربع (يقود الإطار واللون).
class ToothGroupLabel {
  const ToothGroupLabel(
    this.text,
    this.quadrant, {
    this.palmerBorder = false,
    this.primary = false,
  });

  /// «6» أو «1-3,5» أو «A-E» أو «11-18».
  final String text;

  /// UR/UL/LR/LL — يقود إطار Palmer ولون الربع.
  final String quadrant;

  /// أيُرسَم إطار Palmer الربعي؟ (Palmer نعم، FDI لا).
  final bool palmerBorder;

  /// مجموعة طقمٍ لبني؟ (للتمييز الاختباري/المستقبلي).
  final bool primary;
}

const _kQuadrantOrder = ['UR', 'UL', 'LR', 'LL'];

/// ضغطُ مواضعَ مرتَّبةٍ فريدة إلى أشواط: [بداية، نهاية] لكل شوط.
List<(int, int)> _runsOf(List<int> sorted) {
  final runs = <(int, int)>[];
  var i = 0;
  while (i < sorted.length) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    runs.add((sorted[i], sorted[j]));
    i = j + 1;
  }
  return runs;
}

String _tokenOf(int n, String q,
    {required NotationSystem system, required Dentition dentition}) =>
    toothLabel(q, n, system: system, dentition: dentition).text;

/// نصُّ مجموعةٍ واحدة من مواضعها المرتبة: مدىً للأشواط ≥3 وقوائم لما دونها.
String _groupText(List<int> sorted, String q,
    {required NotationSystem system, required Dentition dentition}) {
  final parts = <String>[];
  for (final (a, b) in _runsOf(sorted)) {
    final len = b - a + 1;
    String tok(int n) =>
        _tokenOf(n, q, system: system, dentition: dentition);
    if (len >= 3) {
      parts.add('${tok(a)}-${tok(b)}');
    } else {
      for (var n = a; n <= b; n++) {
        parts.add(tok(n));
      }
    }
  }
  return parts.join(',');
}

/// **قلب م104**: تلخيص مراجع أسنانٍ إلى مجموعات عرض مرتّبة
/// (UR→UL→LR→LL، الدائم قبل اللبني داخل الربع). فارغ الدخل ⇒ فارغ الخرج.
List<ToothGroupLabel> summarizeTeethRefs(
  Iterable<ToothRef> refs, {
  required NotationSystem system,
}) {
  // (ربع، طقم) ⇒ مجموعة مواضع فريدة.
  final buckets = <String, Set<int>>{};
  for (final r in refs) {
    final q = _kQuadrantOrder.contains(r.q) ? r.q : 'UR';
    buckets.putIfAbsent('$q:${r.primary ? 'P' : 'A'}', () => {}).add(r.n);
  }
  final out = <ToothGroupLabel>[];
  for (final q in _kQuadrantOrder) {
    for (final (suffix, dentition) in [
      ('A', Dentition.adult),
      ('P', Dentition.primary),
    ]) {
      final set = buckets['$q:$suffix'];
      if (set == null || set.isEmpty) continue;
      final sorted = set.toList()..sort();
      out.add(ToothGroupLabel(
        _groupText(sorted, q, system: system, dentition: dentition),
        q,
        palmerBorder: system == NotationSystem.palmer,
        primary: dentition == Dentition.primary,
      ));
    }
  }
  return out;
}

// ── م105 — نموذج شبكة Palmer الصليبية (بطاقة الملف + الطباعة) ──────────────
//
//  عند امتداد الأسنان على أكثر من ربع تُعرض الشبكة الكلاسيكية نفسها التي
//  يخطها الأطباء: خطٌّ أفقي بين الفكين وخطٌّ وسطي عمودي، وقسمُ يمينِ
//  المريض يُكتب من الوحشي نحو الخط المتوسط (E D C B A / 8-1) وقسمُ
//  اليسار بالعكس (A B C D E / 1-8) — مطابقةً لصور المالك حرفياً.
//  فكٌّ واحد ⇒ نصف الشبكة فقط (بلا امتداد العمودي للنصف الغائب).

/// نموذج الشبكة: نصوص الأقسام الأربعة ('' = قسم فارغ) وعلما الفكين.
class ToothCrossModel {
  const ToothCrossModel({
    required this.upperRight,
    required this.upperLeft,
    required this.lowerRight,
    required this.lowerLeft,
  });

  final String upperRight;
  final String upperLeft;
  final String lowerRight;
  final String lowerLeft;

  bool get hasUpper => upperRight.isNotEmpty || upperLeft.isNotEmpty;
  bool get hasLower => lowerRight.isNotEmpty || lowerLeft.isNotEmpty;
}

/// نصُّ قسمٍ باتجاهه السريري: [descending] لأقسام يمين المريض
/// (من الوحشي نحو الوسط) — الأشواط ≥3 مدىً بطرفيها، وما دونها صريح.
String _sectionText(List<int> sorted, String q,
    {required NotationSystem system,
    required Dentition dentition,
    required bool descending}) {
  final runs = _runsOf(sorted);
  final ordered = descending ? runs.reversed : runs;
  final parts = <String>[];
  for (final (a, b) in ordered) {
    final len = b - a + 1;
    String tok(int n) =>
        _tokenOf(n, q, system: system, dentition: dentition);
    if (len >= 3) {
      parts.add(descending ? '${tok(b)}-${tok(a)}' : '${tok(a)}-${tok(b)}');
    } else {
      final ns = descending ? [for (var n = b; n >= a; n--) n] : [a, b];
      for (final n in len == 1 ? [a] : ns) {
        parts.add(tok(n));
      }
    }
  }
  return parts.join(',');
}

/// **بانية النموذج**: null عندما لا تستحق الشبكة (ربعٌ واحد أو لا أسنان) —
/// فيسقط المستدعي إلى خلايا القوس (م104). الدائم قبل اللبني داخل القسم.
ToothCrossModel? toothCrossModel(
  Iterable<ToothRef> refs, {
  required NotationSystem system,
}) {
  final buckets = <String, Set<int>>{};
  final quadrants = <String>{};
  for (final r in refs) {
    final q = _kQuadrantOrder.contains(r.q) ? r.q : 'UR';
    quadrants.add(q);
    buckets.putIfAbsent('$q:${r.primary ? 'P' : 'A'}', () => {}).add(r.n);
  }
  if (quadrants.length < 2) return null;

  String section(String q) {
    final descending = q == 'UR' || q == 'LR'; // يمين المريض
    final parts = <String>[];
    for (final (suffix, dentition) in [
      ('A', Dentition.adult),
      ('P', Dentition.primary),
    ]) {
      final set = buckets['$q:$suffix'];
      if (set == null || set.isEmpty) continue;
      final sorted = set.toList()..sort();
      parts.add(_sectionText(sorted, q,
          system: system, dentition: dentition, descending: descending));
    }
    return parts.join(',');
  }

  return ToothCrossModel(
    upperRight: section('UR'),
    upperLeft: section('UL'),
    lowerRight: section('LR'),
    lowerLeft: section('LL'),
  );
}

/// نموذج الشبكة من عناصر التخزين `{q,n,d?}` مباشرة.
ToothCrossModel? toothCrossModelFromMaps(
  Iterable<Map> teeth, {
  required NotationSystem system,
}) =>
    toothCrossModel(
      [
        for (final t in teeth)
          if (t['_deleted'] != 1 &&
              t['_deleted'] != true &&
              t['_deleted'] != '1')
            (
              q: '${t['q'] ?? 'UR'}',
              n: (num.tryParse('${t['n'] ?? 1}') ?? 1).toInt(),
              primary: dentitionOfTooth(t) == Dentition.primary,
            ),
      ],
      system: system,
    );

/// تلخيصٌ من عناصر التخزين `{q,n,d?}` مباشرة (يتجاهل شواهد الحذف).
List<ToothGroupLabel> summarizeTeethMaps(
  Iterable<Map> teeth, {
  required NotationSystem system,
}) =>
    summarizeTeethRefs(
      [
        for (final t in teeth)
          if (t['_deleted'] != 1 &&
              t['_deleted'] != true &&
              t['_deleted'] != '1')
            (
              q: '${t['q'] ?? 'UR'}',
              n: (num.tryParse('${t['n'] ?? 1}') ?? 1).toInt(),
              primary: dentitionOfTooth(t) == Dentition.primary,
            ),
      ],
      system: system,
    );
