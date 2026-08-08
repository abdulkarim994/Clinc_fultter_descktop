/// اختبارات «حذف التحاليل من الجدول» — بلا قاعدة بيانات ولا ودجات.
///
/// التغطية:
///   (أ) التوافق الخلفي: AnalysisLink بدون id يعطي '' ولا يكسر المنشئ القائم.
///   (ب) buildAnalysisIndex يملأ id في الروابط عبر مسار byRecord (عبر analysisOf).
///   (ج) buildAnalysisIndex يملأ id في الروابط عبر مسار byPatDay (الاسم+اليوم).
///   (د) سجلٌ بلا 'id' يُعطي رابطاً بـ id == '' (لا استثناء).
library;

import 'package:dental_clinic_flutter/features/records/home_logic.dart'
    show AnalysisLink, AnalysisIndex, buildAnalysisIndex;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── (أ) التوافق الخلفي: AnalysisLink بدون id ─────────────────────────────
  group('AnalysisLink — التوافق الخلفي', () {
    test('إنشاء بلا id يعطي سلسلة فارغة', () {
      // المنشئ القديم بلا id يجب ألا يكسر أي كود قائم.
      const link = AnalysisLink(
        name: 'تحليل دم',
        amount: 5000,
        payment: 'كاش',
      );
      expect(link.id, equals(''));
    });

    test('إنشاء مع id يحتفظ بقيمته', () {
      const link = AnalysisLink(
        name: 'تحليل دم',
        amount: 5000,
        payment: 'تحويل',
        id: 'rec-42',
      );
      expect(link.id, equals('rec-42'));
    });

    test('isCash يعمل بشكل مستقل عن id', () {
      const cash = AnalysisLink(name: 'أ', amount: 100, payment: 'كاش');
      const transfer = AnalysisLink(name: 'ب', amount: 200, payment: 'تحويل');
      expect(cash.isCash, isTrue);
      expect(transfer.isCash, isFalse);
    });
  });

  // ── (ب) buildAnalysisIndex — مسار byRecord (analysisOf) ──────────────────
  group('buildAnalysisIndex — مسار byRecord', () {
    // بناء قوائم خرائط السجلات يدوياً (الدالة نقية على List of Map).
    final records = <Map<String, Object?>>[
      {
        'id': 'anal-001',
        'isAnalysis': true,
        'analysisOf': 'visit-100',
        'analysisName': 'تحليل الدم الكامل',
        'amount': 15000,
        'payment': 'كاش',
        'name': 'أحمد خالد',
        'date': '2026-08-08',
      },
      {
        'id': 'anal-002',
        'isAnalysis': true,
        'analysisOf': 'visit-100',
        'analysisName': 'تحليل البول',
        'amount': 8000,
        'payment': 'تحويل',
        'name': 'أحمد خالد',
        'date': '2026-08-08',
      },
      {
        'id': 'anal-003',
        'isAnalysis': true,
        'analysisOf': 'visit-200',
        'analysisName': 'أشعة سينية',
        'amount': 25000,
        'payment': 'كاش',
        'name': 'سارة محمد',
        'date': '2026-08-08',
      },
    ];

    late AnalysisIndex index;
    setUp(() => index = buildAnalysisIndex(records));

    test('عدد الروابط صحيح لكل معرّف زيارة', () {
      expect(index.byRecord['visit-100']?.length, equals(2));
      expect(index.byRecord['visit-200']?.length, equals(1));
    });

    test('id يُمرَّر في رابط byRecord للزيارة الأولى', () {
      final links = index.byRecord['visit-100']!;
      // الترتيب حسب ورود السجلات في القائمة.
      expect(links[0].id, equals('anal-001'));
      expect(links[1].id, equals('anal-002'));
    });

    test('id يُمرَّر في رابط byRecord للزيارة الثانية', () {
      final links = index.byRecord['visit-200']!;
      expect(links[0].id, equals('anal-003'));
    });

    test('name وamount وpayment محفوظة بدقة', () {
      final link = index.byRecord['visit-100']![0];
      expect(link.name, equals('تحليل الدم الكامل'));
      expect(link.amount, equals(15000));
      expect(link.payment, equals('كاش'));
      expect(link.isCash, isTrue);
    });
  });

  // ── (ج) buildAnalysisIndex — مسار byPatDay (الاسم+اليوم) ────────────────
  group('buildAnalysisIndex — مسار byPatDay', () {
    // سجلات بلا analysisOf — يسقط في مسار الاحتياط (الاسم+اليوم).
    final records = <Map<String, Object?>>[
      {
        'id': 'anal-010',
        'isAnalysis': true,
        'analysisOf': '',
        'analysisName': 'تحليل السكر',
        'amount': 6000,
        'payment': 'تحويل',
        'name': 'ليلى عمر',
        'date': '2026-08-08',
      },
      {
        'id': 'anal-011',
        'isAnalysis': true,
        // analysisOf غائبة — يُعامَل كفارغ.
        'analysisName': 'تحليل الكوليسترول',
        'amount': 7000,
        'payment': 'كاش',
        'name': 'ليلى عمر',
        'date': '2026-08-08',
      },
    ];

    late AnalysisIndex index;
    setUp(() => index = buildAnalysisIndex(records));

    test('لا توجد إدخالات byRecord لسجلات بلا analysisOf', () {
      // المفتاح الفارغ لا يُضاف إلى byRecord.
      expect(index.byRecord.containsKey(''), isFalse);
      expect(index.byRecord.containsKey('null'), isFalse);
    });

    test('الروابط موجودة في byPatDay بالمفتاح الصحيح', () {
      const key = 'ليلى عمر|2026-08-08';
      expect(index.byPatDay[key]?.length, equals(2));
    });

    test('id يُمرَّر في روابط byPatDay', () {
      const key = 'ليلى عمر|2026-08-08';
      final links = index.byPatDay[key]!;
      expect(links[0].id, equals('anal-010'));
      expect(links[1].id, equals('anal-011'));
    });

    test('forRow يجد الروابط عبر byPatDay حين analysisOf غائبة', () {
      // recId فارغ — يرجع إلى byPatDay.
      final links = index.forRow('', 'ليلى عمر', '2026-08-08');
      expect(links.length, equals(2));
    });
  });

  // ── (د) سجل بلا حقل 'id' لا يُسبّب استثناءً ─────────────────────────────
  group('buildAnalysisIndex — سجل بلا id', () {
    final records = <Map<String, Object?>>[
      {
        // 'id' غائب عمداً.
        'isAnalysis': true,
        'analysisOf': 'visit-999',
        'analysisName': 'تحليل مجهول',
        'amount': 3000,
        'payment': 'كاش',
        'name': 'مجهول',
        'date': '2026-08-08',
      },
    ];

    test('رابط id == "" لسجل بلا حقل id — لا استثناء', () {
      final index = buildAnalysisIndex(records);
      final links = index.byRecord['visit-999']!;
      expect(links.length, equals(1));
      // id يجب أن يكون سلسلة فارغة وليس 'null'.
      expect(links[0].id, equals(''));
    });
  });
}
