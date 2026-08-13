/// م175 — محرك قوالب المقارنة: **القالب بياناتٌ لا كود** — نسبة أبعاد
/// اللوحة، نمط توزيع الفتحات، لوحة الألوان، ولون شرائح النصوص. يرسمها
/// كلها مكوّن الاستوديو الواحد، فإضافة قالبٍ جديد سطرُ بياناتٍ فقط
/// (تمهيد م175/ب: التوسعة لعشرين قالباً).
///
/// عائلتان (قرار المالك — زر المقارنة يخيّر بينهما أولاً):
///   • smile: قوالب نشر الابتسامة (فيسبوك 1:1 و4:5 وعمودي مكدس).
///   • xray: قوالب مقارنة الأشعة (ثنائي، شريط أفقي 6-2، شبكة).
/// ومُصيغ المدة العربية بين أقدم وأحدث صورة («متابعة بعد ٦ أشهر...»).
library;

import 'package:flutter/material.dart';

/// نمط توزيع الفتحات داخل اللوحة.
enum SlotLayout {
  /// ثنائي جانبي (قبل يمين / بعد يسار).
  duo,

  /// شريط أفقي (2–6 صور بصفٍّ واحد) — كأمثلة تسلسل الحالة.
  row,

  /// شبكة صفين (4 صور 2×2، و6 صور 2×3).
  grid,

  /// عمودي مكدس (كمثال الابتسامة الذهبي — صورة فوق صورة).
  stacked,
}

/// قالب مقارنة — بيانات صرفة يرسمها الاستوديو.
class CompareTemplate {
  const CompareTemplate({
    required this.id,
    required this.name,
    required this.family,
    required this.aspect,
    required this.layout,
    required this.bgTop,
    required this.bgBottom,
    required this.frame,
    required this.titleColor,
    required this.textColor,
    required this.beforeChip,
    required this.afterChip,
    required this.stampBg,
    required this.stampText,
    this.lightOnDark = true,
  });

  final String id;
  final String name;

  /// 'smile' أو 'xray'.
  final String family;

  /// نسبة أبعاد اللوحة (عرض/ارتفاع) — 1 مربع فيسبوك، 0.8 = 4:5...
  final double aspect;

  final SlotLayout layout;

  // ── اللوحة اللونية ──
  final Color bgTop;
  final Color bgBottom;
  final Color frame;
  final Color titleColor;
  final Color textColor;
  final Color beforeChip;
  final Color afterChip;
  final Color stampBg;
  final Color stampText;

  /// خلفية داكنة؟ (لاختيار نسخة الشعار الأنسب افتراضياً).
  final bool lightOnDark;
}

/// ذهب العلامة (ثابت هنا كي يبقى الملف بياناتٍ صرفة بلا اعتماديات).
const _gold = Color(0xFFC9A24B);
const _goldDark = Color(0xFF9C7A2E);
const _green = Color(0xFF15604A);
const _green900 = Color(0xFF0A2A1F);

/// م175 — القوالب الثمانية المنتقاة (4 ابتسامة + 4 أشعة).
const kCompareTemplates = <CompareTemplate>[
  // ═══ عائلة الابتسامة (فيسبوك) ═══
  CompareTemplate(
    id: 'smile_gold',
    name: 'الذهبي الفاخر',
    family: 'smile',
    aspect: 1, // مربع فيسبوك.
    layout: SlotLayout.stacked,
    bgTop: Color(0xFFF6EFDF),
    bgBottom: Color(0xFFEFE3C8),
    frame: _gold,
    titleColor: _goldDark,
    textColor: Color(0xFF5B4A22),
    beforeChip: _goldDark,
    afterChip: _green,
    stampBg: Color(0x2EC9A24B),
    stampText: _goldDark,
    lightOnDark: false,
  ),
  CompareTemplate(
    id: 'smile_royal',
    name: 'الأخضر الملكي',
    family: 'smile',
    aspect: .8, // 4:5 فيسبوك/إنستغرام.
    layout: SlotLayout.duo,
    bgTop: Color(0xFF0F3528),
    bgBottom: _green900,
    frame: _gold,
    titleColor: _gold,
    textColor: Colors.white,
    beforeChip: _goldDark,
    afterChip: _green,
    stampBg: Color(0x29C9A24B),
    stampText: _gold,
  ),
  CompareTemplate(
    id: 'smile_pure',
    name: 'الأبيض النقي',
    family: 'smile',
    aspect: 1,
    layout: SlotLayout.duo,
    bgTop: Colors.white,
    bgBottom: Color(0xFFF3F6F4),
    frame: Color(0xFFD8E2DC),
    titleColor: _green,
    textColor: Color(0xFF33413A),
    beforeChip: Color(0xFF8A8F8B),
    afterChip: _green,
    stampBg: Color(0x14156048),
    stampText: _green,
    lightOnDark: false,
  ),
  CompareTemplate(
    id: 'smile_night',
    name: 'الليلي الأنيق',
    family: 'smile',
    aspect: .8,
    layout: SlotLayout.stacked,
    bgTop: Color(0xFF17181C),
    bgBottom: Color(0xFF0C0D10),
    frame: _gold,
    titleColor: _gold,
    textColor: Colors.white,
    beforeChip: Color(0xFF4A4E57),
    afterChip: _gold,
    stampBg: Color(0x26C9A24B),
    stampText: _gold,
  ),

  // ═══ عائلة الأشعة ═══
  CompareTemplate(
    id: 'xray_royal',
    name: 'الملكي (قبل/بعد)',
    family: 'xray',
    aspect: .9,
    layout: SlotLayout.duo,
    bgTop: Color(0xFF0F3528),
    bgBottom: _green900,
    frame: _gold,
    titleColor: _gold,
    textColor: Colors.white,
    beforeChip: _goldDark,
    afterChip: _green,
    stampBg: Color(0x29C9A24B),
    stampText: _gold,
  ),
  CompareTemplate(
    id: 'xray_strip',
    name: 'شريط التسلسل',
    family: 'xray',
    aspect: 2.4, // عريض كأمثلة تسلسل الحالة.
    layout: SlotLayout.row,
    bgTop: Color(0xFF101318),
    bgBottom: Color(0xFF0A0C10),
    frame: Color(0xFF3C4250),
    titleColor: Colors.white,
    textColor: Color(0xFFCBD2DC),
    beforeChip: Color(0xFF3C4250),
    afterChip: _green,
    stampBg: Color(0x24FFFFFF),
    stampText: Colors.white,
  ),
  CompareTemplate(
    id: 'xray_amber',
    name: 'الكهرماني الدافئ',
    family: 'xray',
    aspect: 2,
    layout: SlotLayout.row,
    bgTop: Color(0xFFF2B15C),
    bgBottom: Color(0xFFE99C3E),
    frame: Color(0xFF6B4A14),
    titleColor: Color(0xFF3D2A0A),
    textColor: Color(0xFF4A340F),
    beforeChip: Color(0xFF6B4A14),
    afterChip: Color(0xFF1F5C46),
    stampBg: Color(0x2E3D2A0A),
    stampText: Color(0xFF3D2A0A),
    lightOnDark: false,
  ),
  CompareTemplate(
    id: 'xray_grid',
    name: 'الشبكة السريرية',
    family: 'xray',
    aspect: 1,
    layout: SlotLayout.grid,
    bgTop: Color(0xFF10192B),
    bgBottom: Color(0xFF0B111E),
    frame: Color(0xFF33415C),
    titleColor: Colors.white,
    textColor: Color(0xFFC3CDDC),
    beforeChip: Color(0xFF33415C),
    afterChip: _green,
    stampBg: Color(0x22FFFFFF),
    stampText: Colors.white,
  ),
];

/// قوالب عائلةٍ ما بترتيب التعريف.
List<CompareTemplate> templatesOf(String family) =>
    [for (final t in kCompareTemplates) if (t.family == family) t];

// ═══════════ مُصيغ المدة العربية (النص التلقائي) ═══════════

/// عدد عربي بصيغة سليمة للوحدة: مفرد/مثنى/جمع 3-10/فوق 10.
String _arCount(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  return '$n $many';
}

/// المدة بين طابعين (ميلي ثانية) بصياغة عربية إنسانية:
/// «٦ أشهر» / «سنتين» / «سنة وشهرين» / «٢٠ يوماً» — فارغة إن تطابقا.
String arDurationBetween(int fromMs, int toMs) {
  if (fromMs <= 0 || toMs <= 0) return '';
  final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
  final to = DateTime.fromMillisecondsSinceEpoch(toMs);
  if (!to.isAfter(from)) return '';
  var years = to.year - from.year;
  var months = to.month - from.month;
  var days = to.day - from.day;
  if (days < 0) {
    months -= 1;
    days += DateTime(to.year, to.month, 0).day;
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  if (years > 0) {
    final y = _arCount(years, 'سنة', 'سنتين', 'سنوات', 'سنة');
    if (months > 0) {
      final m = _arCount(months, 'شهر', 'شهرين', 'أشهر', 'شهراً');
      return '$y و$m';
    }
    return y;
  }
  if (months > 0) {
    return _arCount(months, 'شهر', 'شهرين', 'أشهر', 'شهراً');
  }
  final d = to.difference(from).inDays;
  if (d <= 0) return '';
  return _arCount(d, 'يوم', 'يومين', 'أيام', 'يوماً');
}

/// جملة المتابعة الجاهزة — «متابعة الحالة بعد X من العلاج».
String followUpSentence(int fromMs, int toMs) {
  final d = arDurationBetween(fromMs, toMs);
  return d.isEmpty ? '' : 'متابعة الحالة بعد $d من العلاج';
}
