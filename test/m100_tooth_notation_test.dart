/// اختبارات م100 — وحدة عرض الترقيم: تطابق Palmer وFDI (دائم/لبني) مع
/// المراجع الرسمية (ISO 3950 / FDI / رموز Palmer)، وثباتُ التخزين.
///
///  كل قيمةٍ متوقَّعة هنا مأخوذةٌ من نص ISO 3950:2016 والجداول الرسمية
///  (انظر تقرير المرحلة الأولى) — فالاختبار حارسٌ للمطابقة المعيارية.
library;

import 'package:dental_clinic_flutter/features/records/tooth_notation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م100/أ — FDI (ISO 3950) دائم: الأرباع 1-4 والموضع', () {
    // الجدول الرسمي: أعلى يمين 11-18، أعلى يسار 21-28،
    // أسفل يسار 31-38، أسفل يمين 41-48.
    String fdi(String q, int n) =>
        toothLabel(q, n, system: NotationSystem.fdi).text;

    test('الأرباع الأربعة عند الموضع 6 (الرحى الأولى)', () {
      expect(fdi('UR', 6), '16');
      expect(fdi('UL', 6), '26');
      expect(fdi('LL', 6), '36');
      expect(fdi('LR', 6), '46');
    });
    test('حدود المدى: القاطع المركزي والرحى الثالثة', () {
      expect(fdi('UR', 1), '11');
      expect(fdi('UR', 8), '18');
      expect(fdi('LR', 1), '41');
      expect(fdi('LL', 8), '38');
    });
  });

  group('م100/ب — FDI لبني: الأرباع 5-8 والموضع 1-5', () {
    String fdiP(String q, int n) => toothLabel(q, n,
            system: NotationSystem.fdi, dentition: Dentition.primary)
        .text;
    test('الجدول الرسمي 51-85', () {
      expect(fdiP('UR', 1), '51');
      expect(fdiP('UL', 5), '65');
      expect(fdiP('LL', 1), '71');
      expect(fdiP('LR', 5), '85');
    });
  });

  group('م100/ج — Palmer: الموضع + إطار الربع، ولبني A-E', () {
    test('دائم: النص هو الموضع نفسه مع إطار ربعي', () {
      final t = toothLabel('UR', 6, system: NotationSystem.palmer);
      expect(t.text, '6');
      expect(t.palmerBorder, isTrue);
      expect(t.quadrant, 'UR');
    });
    test('لبني: حروف A→E من المنتصف وحشياً', () {
      String p(int n) => toothLabel('UL', n,
              system: NotationSystem.palmer, dentition: Dentition.primary)
          .text;
      expect([p(1), p(2), p(3), p(4), p(5)], ['A', 'B', 'C', 'D', 'E']);
    });
    test('FDI بلا إطار ربعي', () {
      expect(toothLabel('UR', 6, system: NotationSystem.fdi).palmerBorder,
          isFalse);
    });
  });

  group('م100/د — التوافق: قراءة الطقم والمفاتيح القديمة', () {
    test('غياب الوسم d ⇒ دائم (بيانات قديمة)', () {
      expect(dentitionOfTooth({'q': 'UR', 'n': 6}), Dentition.adult);
      expect(dentitionOfTooth({'q': 'UR', 'n': 5, 'd': 'P'}),
          Dentition.primary);
    });
    test('toothLabelFromTooth يقرأ الوسم', () {
      final adult = toothLabelFromTooth({'q': 'UR', 'n': 6},
          system: NotationSystem.fdi);
      expect(adult.text, '16');
      final primary = toothLabelFromTooth({'q': 'UR', 'n': 5, 'd': 'P'},
          system: NotationSystem.fdi);
      expect(primary.text, '55');
    });
    test('toothLabelFromKey يفكّ q:n', () {
      expect(
          toothLabelFromKey('LL:3', system: NotationSystem.fdi).text, '33');
    });
    test('مفتاح تالف ⇒ افتراضٌ آمن بلا رمي', () {
      final t = toothLabelFromKey('غريب', system: NotationSystem.fdi);
      expect(t.text, '11'); // UR:1 الافتراضي
    });
  });

  group('م100/هـ — تفضيل النظام (مُزامَن في app.config)', () {
    test('التحويل ذهاباً وإياباً، والغياب = Palmer (توافق النسخ السابقة)', () {
      expect(notationSystemFromConfig(null), NotationSystem.palmer);
      expect(notationSystemFromConfig('palmer'), NotationSystem.palmer);
      expect(notationSystemToConfig(NotationSystem.palmer), 'palmer');
      expect(notationSystemToConfig(NotationSystem.fdi), 'fdi');
    });
    test('عدد الأسنان في الربع حسب الطقم', () {
      expect(teethPerQuadrant(Dentition.adult), 8);
      expect(teethPerQuadrant(Dentition.primary), 5);
    });
  });

  group('م100/و — التبديل لا يغيّر التخزين (نفس q:n)', () {
    test('العرض يشتق فقط؛ لا يكتب في العنصر المخزَّن', () {
      final stored = {'q': 'UR', 'n': 6};
      final before = Map<String, Object?>.from(stored);
      toothLabelFromTooth(stored, system: NotationSystem.palmer);
      toothLabelFromTooth(stored, system: NotationSystem.fdi);
      expect(stored, before, reason: 'م100: دالة العرض نقيّة لا تعدّل');
    });
  });
}
