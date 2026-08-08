// اختبارات نقية لدالة filterAnalysesRows من analyses_filter.dart —
// بلا قاعدة بيانات ولا Riverpod ولا Flutter: نمرّر خرائط مباشرةً.
//
// الأوضاع المختبَرة: all/cash/transfer، البحث بالاسم، البحث بالتطبيع
// العربي (همزات وتاء مربوطة)، البحث باسم التحليل، تركيب بحث+وضع،
// قائمة فارغة وquery فارغة.
library;

import 'package:dental_clinic_flutter/features/finance/analyses_filter.dart'
    show filterAnalysesRows;
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

// ── بيانات اختبار ثابتة ───────────────────────────────────────────────────

/// صفوف تحاليل تمثّل حالات متنوعة
const List<JMap> _rows = [
  // كاش — الثلاثية
  {
    'id': '1',
    'name': 'الثلاثية بنت أحمد',
    'analysisName': 'تحليل دم شامل',
    'payment': 'كاش',
    'amount': 120,
  },
  // كاش — إبراهيم (همزة)
  {
    'id': '2',
    'name': 'إبراهيم محمد',
    'service': 'صورة أشعة',
    'payment': 'كاش',
    'amount': 80,
  },
  // تحويل — فاطمة (تاء مربوطة في الاسم)
  {
    'id': '3',
    'name': 'فاطمة علي',
    'analysisName': 'تحليل بول',
    'payment': 'تحويل',
    'amount': 60,
  },
  // تحويل — مريض باسم patient_name
  {
    'id': '4',
    'patient_name': 'أسماء سالم',
    'analysisName': 'زراعة بكتيرية',
    'payment': 'تحويل',
    'amount': 200,
  },
  // كاش — بدون payment (لا يُصنَّف كاشاً → تحويل افتراضياً)
  {
    'id': '5',
    'name': 'سالم ناصر',
    'service': 'صورة صدر',
    'payment': null,
    'amount': 50,
  },
];

void main() {
  // ── وضع 'all' ─────────────────────────────────────────────────────────────

  group("وضع 'all' — يُعيد الكل", () {
    test('query فارغة تُعيد جميع الصفوف', () {
      final result = filterAnalysesRows(_rows, query: '', mode: 'all');
      expect(result.length, equals(_rows.length),
          reason: 'لا فلترة عند query فارغة');
    });

    test('قائمة فارغة تُعيد قائمة فارغة', () {
      final result =
          filterAnalysesRows(const [], query: '', mode: 'all');
      expect(result, isEmpty);
    });

    test('الترتيب لا يتغير', () {
      final result = filterAnalysesRows(_rows, query: '', mode: 'all');
      final ids = result.map((r) => r['id']).toList();
      expect(ids, orderedEquals(['1', '2', '3', '4', '5']));
    });
  });

  // ── وضع 'cash' ────────────────────────────────────────────────────────────

  group("وضع 'cash' — يُعيد كاش فقط", () {
    test('يُعيد صفوف payment==كاش فقط', () {
      final result = filterAnalysesRows(_rows, query: '', mode: 'cash');
      // الصفوف 1 و2 كاش فقط (الصف 5 payment=null → ليس كاشاً)
      expect(result.length, equals(2));
      expect(result.map((r) => r['id']),
          containsAll(['1', '2']));
    });

    test('صف payment=null لا يُعدّ كاشاً', () {
      final result = filterAnalysesRows(_rows, query: '', mode: 'cash');
      expect(result.any((r) => r['id'] == '5'), isFalse);
    });
  });

  // ── وضع 'transfer' ────────────────────────────────────────────────────────

  group("وضع 'transfer' — يُعيد غير الكاش", () {
    test('يُعيد الصفوف التي payment != كاش', () {
      final result =
          filterAnalysesRows(_rows, query: '', mode: 'transfer');
      // الصفوف 3 و4 و5 (5 payment=null → غير كاش → تحويل)
      expect(result.length, equals(3));
      expect(result.map((r) => r['id']),
          containsAll(['3', '4', '5']));
    });

    test('لا يُعيد أي صف payment==كاش', () {
      final result =
          filterAnalysesRows(_rows, query: '', mode: 'transfer');
      expect(result.any((r) => r['payment'] == 'كاش'), isFalse);
    });
  });

  // ── بحث بالاسم (حقل name) ────────────────────────────────────────────────

  group('بحث بالاسم', () {
    test('بحث بالاسم العادي يجد الصف المطابق', () {
      final result =
          filterAnalysesRows(_rows, query: 'سالم', mode: 'all');
      // الصف 5 (سالم ناصر) والصف 4 (أسماء سالم patient_name)
      expect(result.length, equals(2));
    });

    test('بحث بجزء من الاسم يعمل (مطابقة جزئية)', () {
      final result =
          filterAnalysesRows(_rows, query: 'فاطم', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('3'));
    });

    test('query لا تطابق أي اسم تُعيد فارغة', () {
      final result =
          filterAnalysesRows(_rows, query: 'خالد منصور', mode: 'all');
      expect(result, isEmpty);
    });
  });

  // ── بحث بالتطبيع العربي (همزات وتاء مربوطة) ─────────────────────────────

  group('التطبيع العربي (arNorm)', () {
    test('«الثلاثيه» يجد «الثلاثية» (تاء مربوطة → هاء)', () {
      final result =
          filterAnalysesRows(_rows, query: 'الثلاثيه', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('1'),
          reason: 'الثلاثية بنت أحمد — تُوحَّد التاء المربوطة');
    });

    test('«ابراهيم» (بلا همزة) يجد «إبراهيم» (بهمزة)', () {
      final result =
          filterAnalysesRows(_rows, query: 'ابراهيم', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('2'),
          reason: 'إبراهيم — توحيد الهمزة');
    });

    test('«فاطمه» يجد «فاطمة» (تاء مربوطة → هاء)', () {
      final result =
          filterAnalysesRows(_rows, query: 'فاطمه', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('3'));
    });

    test('«اسماء» (بلا همزة) يجد «أسماء» (patient_name)', () {
      final result =
          filterAnalysesRows(_rows, query: 'اسماء', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('4'));
    });
  });

  // ── بحث باسم التحليل (analysisName / service) ────────────────────────────

  group('بحث باسم التحليل', () {
    test('بحث بـ analysisName يجد الصف الصحيح', () {
      final result =
          filterAnalysesRows(_rows, query: 'تحليل دم', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('1'));
    });

    test('بحث بـ service يجد الصف الصحيح', () {
      final result =
          filterAnalysesRows(_rows, query: 'صورة أشعة', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('2'));
    });

    test('«اشعه» (بلا همزة/تاء) يجد «أشعة»', () {
      final result =
          filterAnalysesRows(_rows, query: 'اشعه', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('2'));
    });

    test('بحث في analysisName بالتطبيع يجد «تحليل بول»', () {
      final result =
          filterAnalysesRows(_rows, query: 'بول', mode: 'all');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('3'));
    });
  });

  // ── تركيب بحث + وضع ──────────────────────────────────────────────────────

  group('تركيب query + mode', () {
    test('كاش + بحث بالاسم يُعيد تقاطع الشرطين', () {
      // الصف 1 كاش + اسمه يحوي «أحمد»
      final result =
          filterAnalysesRows(_rows, query: 'أحمد', mode: 'cash');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('1'));
    });

    test('تحويل + بحث باسم التحليل «بكتيري»', () {
      // الصف 4 تحويل + analysisName يحوي «بكتيرية»
      final result =
          filterAnalysesRows(_rows, query: 'بكتيري', mode: 'transfer');
      expect(result.length, equals(1));
      expect(result.first['id'], equals('4'));
    });

    test('cash + query غير موجودة → فارغة', () {
      final result =
          filterAnalysesRows(_rows, query: 'xyzغير موجود', mode: 'cash');
      expect(result, isEmpty);
    });

    test('transfer + query فارغة → كل غير الكاش', () {
      final result =
          filterAnalysesRows(_rows, query: '', mode: 'transfer');
      expect(result.length, equals(3));
    });
  });

  // ── حالات حدية ───────────────────────────────────────────────────────────

  group('حالات حدية', () {
    test('صف بلا name ولا patient_name لا يُرمى استثناء', () {
      const noName = <JMap>[
        {'id': 'x', 'analysisName': 'اختبار', 'payment': 'كاش', 'amount': 10},
      ];
      expect(
        () => filterAnalysesRows(noName, query: 'أحمد', mode: 'all'),
        returnsNormally,
      );
    });

    test('صف بلا analysisName ولا service لا يُرمى استثناء', () {
      const noSvc = <JMap>[
        {'id': 'y', 'name': 'مريض', 'payment': 'كاش', 'amount': 30},
      ];
      expect(
        () => filterAnalysesRows(noSvc, query: 'شيء', mode: 'all'),
        returnsNormally,
      );
    });

    test('query من مسافات فارغة تُعيد الكل (تُعامَل فارغة)', () {
      final result =
          filterAnalysesRows(_rows, query: '   ', mode: 'all');
      expect(result.length, equals(_rows.length));
    });
  });
}
