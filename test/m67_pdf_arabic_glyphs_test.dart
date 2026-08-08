/// اختبارات م67/دفعة أول-ج — تغطية محارف العربية في خطوط PDF.
///
/// العيب الأصلي (PDF-1): خط Cairo ينقصه الشكل المعزول للياء U+FEF1 (وأشكال
/// أخرى من كتلة FE70–FEFF). مشكّل النص في حزمة pdf يحوّل النص إلى أشكال
/// العرض ثم يبحث عنها في `TtfParser.charToGlyphIndexMap`؛ فإن غابت رُسم
/// فراغٌ صامت (تحذير داخل assert لا يرمي). النتيجة: 23 من 31 اسماً شائعاً
/// ناقص، و«السكري» تصير «السكر». (تحقّقنا أيضاً أن خريطة pdf الداخلية
/// تُسقِط 064A على FEEF لا FEF1، فالمحرف مفقود فعلاً حتى بعد اصطناع الحزمة.)
///
/// الاختبار يستعمل `TtfParser` — الأداة نفسها التي تبحث بها الحزمة وقت
/// الرسم (isRuneSupported = charToGlyphIndexMap.containsKey) — فيحاكي منطق
/// الحل: خط الأساس أولاً ثم الاحتياط لكل محرف على حدة (text.dart:817-832).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bidi/bidi.dart' as bidi;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show TtfParser;

void main() {
  final root = Directory.current.path;
  TtfParser parse(String name) {
    final b = File('$root/assets/fonts/$name').readAsBytesSync();
    return TtfParser(ByteData.view(b.buffer, b.offsetInBytes, b.length));
  }

  late TtfParser cairo;
  late TtfParser amiri;
  setUpAll(() {
    cairo = parse('Cairo-Regular.ttf');
    amiri = parse('Amiri-Regular.ttf');
  });

  bool inBase(int r) => cairo.charToGlyphIndexMap.containsKey(r);
  bool inFallback(int r) => amiri.charToGlyphIndexMap.containsKey(r);

  // الأشكال العربية بعد التشكيل، مستبعدين المحايدات التي يرسمها الأساس دوماً.
  Set<int> shapedArabicRunes(String s) =>
      bidi.logicalToVisual(s).where((r) => r > 0x0600).toSet();

  // أسماء وحالات عربية شائعة تشمل ياءً آخر كلمة بعد حرف غير موصول
  // (المصدر الأصلي للعيب) وحالات طبية من نافذة السجل.
  const corpus = [
    'مهدي', 'حمدي', 'مجدي', 'رشدي', 'صبري', 'خيري', 'بدري', 'نوري',
    'المصري', 'الزاوي', 'البدوي', 'الأزهري', 'الترهوني', 'الوردي',
    'عبد الهادي', 'يسري', 'السكري', 'ضغط الدم', 'حساسية الأدوية',
    'مضاد حيوي', 'تقرير الشهر', 'دفعة دين — تركيبات',
  ];

  group('م67 — تغطية محارف PDF', () {
    test('REPRO: الأساس Cairo وحده يُسقط محارف (العيب قائم)', () {
      final dropped = <String>{};
      for (final s in corpus) {
        for (final r in shapedArabicRunes(s)) {
          if (!inBase(r)) dropped.add(s);
        }
      }
      expect(dropped, isNotEmpty,
          reason: 'الأساس وحده يُسقط محارف من هذه الأسماء');
      expect(inBase(0xFEF1), isFalse, reason: 'U+FEF1 غير مدعوم في Cairo');
    });

    test('FIX: الأساس + الاحتياط يغطّيان كل محرف بلا إسقاط', () {
      final stillMissing = <String, List<String>>{};
      for (final s in corpus) {
        final miss = [
          for (final r in shapedArabicRunes(s))
            if (!inBase(r) && !inFallback(r)) '0x${r.toRadixString(16)}'
        ];
        if (miss.isNotEmpty) stillMissing[s] = miss;
      }
      expect(stillMissing, isEmpty,
          reason: 'م67: لا محرف مفقود بعد إضافة الاحتياط Amiri');
    });

    test('الاحتياط يغطّي الياء المعزولة والنهائية صراحةً', () {
      expect(inFallback(0xFEF1), isTrue); // يـ معزولة
      expect(inFallback(0xFEF2), isTrue); // ي نهائية
    });

    test('كتلة الأشكال FE70–FEFF: الاحتياط يغطّي ما يفوت الأساس', () {
      final baseHas = [for (var c = 0xFE70; c <= 0xFEFF; c++) if (inBase(c)) c];
      final union = [
        for (var c = 0xFE70; c <= 0xFEFF; c++) if (inBase(c) || inFallback(c)) c
      ];
      expect(union.length, greaterThan(baseHas.length),
          reason: 'الاحتياط يوسّع التغطية');
      // كل ما يملكه الأساس يبقى مغطّى (الاتحاد لا ينقص)
      expect(union.length, greaterThanOrEqualTo(baseHas.length));
    });
  });
}
