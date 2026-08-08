/// ============================================================================
///  سلامة إعداد السحابة — كشف العبث بملف `cloud_config.json`
/// ============================================================================
///
///  (قرار المالك — Windows Desktop Security §سادساً «حماية ملفات الإعدادات
///  من العبث»):
///
///  الخطر
///  ─────
///  `cloud_config.json` يُقرأ **قبل** حسم مفتاح القاعدة، فلا يمكن تشفيره
///  بمفتاحها (بيضة ودجاجة). وهو يحمل عنوان خادم Supabase ومفتاح anon —
///  ومن يعدّل العنوان خلسةً إلى خادمٍ خبيث يوجّه مزامنة العيادة إليه.
///  التشفير غير ممكن هنا، لكن **كشف العبث ممكن**.
///
///  الحل
///  ────
///  ختم HMAC-SHA256 بمفتاحٍ يعيش في مخزن أسرار النظام نفسه (DPAPI على
///  ويندوز) الذي يحمي مفتاح القاعدة. عند كل حفظ يُكتب ختمٌ بجانب الملف
///  (`cloud_config.hmac`)، وعند كل قراءةٍ حسّاسة يُتحقَّق منه: ختمٌ غائبٌ
///  أو غيرُ مطابق ⇒ الملف عُبِث به (أو نُسخ من جهازٍ آخر بمفتاحٍ مختلف)
///  ⇒ يُرفَض ويُبلَّغ، فلا تُوجَّه المزامنة إلى وجهةٍ غير موثوقة صامتةً.
///
///  ⚠ النطاق: سطح المكتب فقط. الهاتف لا يستدعي هذه الطبقة (قراءته للإعداد
///  تبقى كما هي)؛ ومفتاح HMAC محليٌّ للجهاز فلا يعبر المزامنة.
///
///  حدود التحقق: توليد مفتاح HMAC وحفظه في DPAPI يحتاج منصّةً حقيقية،
///  فالمنطق النقي (الختم/التحقق فوق مفتاحٍ مُعطى) هو المُختبَر هنا، وربطُه
///  بالمخزن الآمن رقيقٌ عمداً.
library;

import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' show Hmac, sha256;

/// اسم مفتاح ختم الإعداد في مخزن أسرار النظام (مستقل عن مفتاح القاعدة).
const String kConfigHmacKeyName = 'dental.cfg.hmac.v1';

/// لاحقة ملف الختم بجانب `cloud_config.json`.
const String kConfigHmacSuffix = '.hmac';

/// يحسب ختم HMAC-SHA256 السداسي لمحتوى نصّي بمفتاحٍ سداسي.
///
/// نقيّ تماماً — لا منصّة ولا ملفات — فهو المُختبَر مباشرةً.
String computeConfigSeal(String content, String hexKey) {
  final key = _hexToBytes(hexKey);
  final mac = Hmac(sha256, key).convert(utf8.encode(content));
  return mac.toString();
}

/// يتحقق من ختمٍ مقابل محتوى ومفتاح — مقارنةٌ ثابتة الزمن ضدّ هجمات
/// التوقيت (لا `==` مبكّرة الخروج).
bool verifyConfigSeal(String content, String hexKey, String expectedSeal) {
  final actual = computeConfigSeal(content, hexKey);
  if (actual.length != expectedSeal.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expectedSeal.codeUnitAt(i);
  }
  return diff == 0;
}

List<int> _hexToBytes(String hex) {
  final clean = hex.length.isOdd ? '0$hex' : hex;
  final out = <int>[];
  for (var i = 0; i < clean.length; i += 2) {
    out.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return out;
}
