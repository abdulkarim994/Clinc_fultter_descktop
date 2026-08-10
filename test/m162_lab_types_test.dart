/// م162 — تركيبات وأسعار خاصة بكل مختبر: labTypesFor تقرأ قائمة
/// المختبر من labTypesByLab وتتراجع للقائمة العامة القديمة عند غيابها
/// (توافق خلفي كامل — لا جهاز ينكسر ولا بيانات تُفقد).
library;

import 'package:dental_clinic_flutter/features/records/add_record_screen.dart'
    show labTypesFor, labTypesList;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cfg = <String, Object?>{
    'labTypes': [
      {'name': 'زيركون', 'defaultPrice': 100},
      {'name': 'ببك', 'defaultPrice': 80},
    ],
    'labTypesByLab': {
      'النور': [
        {'name': 'Zirconia', 'defaultPrice': 150},
        {'name': 'Ifk', 'defaultPrice': 200},
      ],
      'الفجر': <Object?>[],
    },
  };

  test('مختبر له قائمة خاصة ⇒ أنواعه وأسعاره هو', () {
    final ts = labTypesFor(cfg, 'النور');
    expect(ts.map((t) => t['name']).toList(), ['Zirconia', 'Ifk']);
    expect(ts.first['defaultPrice'], 150);
  });

  test('مختبر بلا قائمة (أو قائمته فارغة) ⇒ التراجع للقائمة العامة', () {
    // «الفجر» قائمته فارغة و«الأمل» غير موجود أصلاً.
    for (final lab in ['الفجر', 'الأمل']) {
      final ts = labTypesFor(cfg, lab);
      expect(ts.map((t) => t['name']).toList(), ['زيركون', 'ببك'],
          reason: 'التراجع للقائمة العامة القديمة ($lab)');
    }
  });

  test('بلا اختيار مختبر ⇒ القائمة العامة (سلوك ما قبل م162 حرفياً)', () {
    expect(labTypesFor(cfg, ''), labTypesList(cfg));
  });

  test('إعدادات قديمة بلا labTypesByLab إطلاقاً ⇒ القائمة العامة', () {
    final old = <String, Object?>{
      'labTypes': [
        {'name': 'قديم', 'defaultPrice': 55},
      ],
    };
    expect(labTypesFor(old, 'النور').single['name'], 'قديم');
  });
}
