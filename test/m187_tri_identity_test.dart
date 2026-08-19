/// اختبارات م187/أ — هوية التحليل الثلاثي: الهاتف لا الاسم، ونطاق المركز
/// لا العيادة، وتحذيرٌ قابل للتجاوز بدل الرفض عند الهوية غير المؤكَّدة.
///
/// بلاغ المالك: «عند تشابه الأسماء بالتحاليل يرفض أن يعمل تحاليل —
/// يعتبرهم نفس الشخص»، وسؤاله: «نفس المريض يشتغل عند دكتور تاني شو حلها؟».
///
/// الجذران المُثبَتان قبل الإصلاح:
///   ١) هاتف الصفّ المخزَّن كان يُقرأ من `patient_id` **وحده** — فصفٌّ
///      معرّفه `n:اسم` يبدو «بلا هاتف» ولو حمل عمودُه رقماً، فيُحجب سميُّه.
///   ٢) النطاق كان بالعيادة، فنفس الشخص يأخذ تحليلاً ثانياً عند طبيبٍ آخر
///      داخل المدة — ثغرة، والقيد طبّيٌّ على الشخص لا على العيادة.
///
/// العقد الجديد (قرار المالك): **حجبٌ قاطع حين الهوية مؤكَّدة (هاتف/معرّف)
/// في أي عيادة بالمركز، وتحذيرٌ يمضي بموافقة الطبيب حين التطابق بالاسم
/// وحده** — فلا يُحبس الطبيب أمام سميٍّ، ولا تُخترق القاعدة صامتةً.
library;

import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart'
    show arNorm, normPhone;
import 'package:dental_clinic_flutter/features/settings/analyses3.dart';
import 'package:flutter_test/flutter_test.dart';

typedef JMap = Map<String, Object?>;

/// صفّ تحليلٍ ثلاثيّ جاهز.
JMap tri({
  required String name,
  required String date,
  String clinic = 'ع1',
  String phone = '',
  String? patientId,
}) => {
      'isAnalysis': 1,
      'analysisName': kTriAnalysesName,
      'name': name,
      'patient_name': name,
      'date': date,
      'clinic': clinic,
      'clinic_id': clinic,
      if (phone.isNotEmpty) 'phone': phone,
      'patient_id': ?patientId,
    };

TriRepeatHit? hitFor(
  List<JMap> rows, {
  required String name,
  String phone = '',
  String? patientId,
}) =>
    lastTriAnalysisHit(rows,
        patientId: patientId,
        patientName: name,
        phone: phone,
        normalize: arNorm,
        normPhone: normPhone);

TriGate gateFor(
  List<JMap> rows, {
  required String name,
  String phone = '',
  String? patientId,
  String today = '2026-08-19',
  num months = 6,
}) =>
    triRepeatGate(
        hit: hitFor(rows, name: name, phone: phone, patientId: patientId),
        today: today,
        repeatMonths: months);

void main() {
  group('م187/أ — السميّان بهاتفين مختلفين لا يتحاجبان', () {
    test('هاتف الصفّ يُقرأ من عمود phone لا من المعرّف وحده (الجذر ١)', () {
      // الصفّ القديم: معرّفه بلا هاتف (n:اسم) لكن عموده يحمل رقماً.
      final rows = [
        tri(
            name: 'محمد حسين',
            date: '2026-08-01',
            phone: '0911111111',
            patientId: 'n:محمد حسين'),
      ];
      // سميٌّ آخر بهاتفٍ مختلف: كان يُحجب لأن هاتف الصف بدا غائباً.
      final g = gateFor(rows, name: 'محمد حسين', phone: '0922222222');
      expect(g.isAllowed, isTrue,
          reason: 'م187: هاتفان صريحان مختلفان = شخصان مختلفان');
      expect(hitFor(rows, name: 'محمد حسين', phone: '0922222222'), isNull);
    });

    test('نفس الهاتف ⇒ حجبٌ قاطع ولو اختلف الاسم إملائياً', () {
      final rows = [
        tri(name: 'ابراهيم علي', date: '2026-08-01', phone: '0911111111'),
      ];
      final g = gateFor(rows, name: 'إبراهيم علي', phone: '0911111111');
      expect(g.isBlocked, isTrue);
      expect(g.message, contains('2026-08-01'));
      expect(g.message, contains('6'));
    });

    test('تطابق المعرّفين ⇒ حجبٌ مؤكَّد ولو غاب الهاتف', () {
      final rows = [
        tri(name: 'سالم', date: '2026-08-05', patientId: 'p:0933:سالم'),
      ];
      expect(
          gateFor(rows, name: 'سالم مختلف', patientId: 'p:0933:سالم')
              .isBlocked,
          isTrue);
    });
  });

  group('م187/أ — النطاق: المركز كله لا العيادة', () {
    test('نفس الشخص (نفس الهاتف) في عيادة أخرى ⇒ حجب (الثغرة أُغلقت)', () {
      final rows = [
        tri(
            name: 'هدى',
            date: '2026-08-10',
            clinic: 'عيادة أ',
            phone: '0955555555'),
      ];
      final g = gateFor(rows, name: 'هدى', phone: '0955555555');
      expect(g.isBlocked, isTrue,
          reason: 'م187: التحليل قيدٌ على الشخص — أي عيادة بالمركز');
    });

    test('انقضاء المدة يسمح بالطبع (الحدّ بالضبط مسموح)', () {
      final rows = [
        tri(name: 'هدى', date: '2026-02-19', phone: '0955555555'),
      ];
      expect(
          gateFor(rows, name: 'هدى', phone: '0955555555',
                  today: '2026-08-19')
              .isAllowed,
          isTrue);
      expect(
          gateFor(rows, name: 'هدى', phone: '0955555555',
                  today: '2026-08-18')
              .isBlocked,
          isTrue);
    });

    test('القاعدة معطّلة (0 شهر) ⇒ مسموح دائماً', () {
      final rows = [
        tri(name: 'هدى', date: '2026-08-18', phone: '0955555555'),
      ];
      expect(
          gateFor(rows, name: 'هدى', phone: '0955555555', months: 0)
              .isAllowed,
          isTrue);
    });
  });

  group('م187/أ — الهوية غير المؤكَّدة: تحذيرٌ لا رفض', () {
    test('اسمٌ مكرر وكلا الطرفين بلا هاتف ⇒ تحذير قابل للتجاوز', () {
      final rows = [tri(name: 'محمد حسين', date: '2026-08-01')];
      final g = gateFor(rows, name: 'محمد حسين');
      expect(g.isWarning, isTrue);
      expect(g.isBlocked, isFalse,
          reason: 'م187: لا يُحبس الطبيب أمام تخمينٍ بالاسم');
      expect(g.message, contains('نفس الاسم'));
      expect(g.message, contains('2026-08-01'));
    });

    test('الجديد بهاتف والقديم بلا هاتف ⇒ تحذير (لا يقين بالتمييز)', () {
      final rows = [tri(name: 'محمد حسين', date: '2026-08-01')];
      expect(gateFor(rows, name: 'محمد حسين', phone: '0999').isWarning,
          isTrue);
    });

    test('عند تساوي التاريخ يفوز المؤكَّد على المُخمَّن (حجبٌ أدقّ)', () {
      final rows = [
        tri(name: 'محمد حسين', date: '2026-08-01'), // بلا هاتف ⇒ تخمين
        tri(name: 'محمد حسين', date: '2026-08-01', phone: '0911111111'),
      ];
      final g = gateFor(rows, name: 'محمد حسين', phone: '0911111111');
      expect(g.isBlocked, isTrue);
    });

    test('لا تحليلَ سابقاً ⇒ مسموح، وصفوف غير الثلاثي لا تُحتسب', () {
      expect(gateFor(const [], name: 'أحمد').isAllowed, isTrue);
      final other = [
        {
          'isAnalysis': 1,
          'analysisName': 'تحليل قديم مختلف',
          'name': 'أحمد',
          'date': '2026-08-18',
          'phone': '0911111111',
        },
      ];
      expect(gateFor(other, name: 'أحمد', phone: '0911111111').isAllowed,
          isTrue,
          reason: 'القاعدة للتحليل الثلاثي نصاً — لا لصفوف النظام القديم');
    });
  });

  group('م187/أ — التوافق الخلفي', () {
    test('lastTriAnalysisDate يبقى يعيد التاريخ نفسه', () {
      final rows = [
        tri(name: 'نور', date: '2026-07-01', phone: '0911111111'),
        tri(name: 'نور', date: '2026-08-01', phone: '0911111111'),
      ];
      expect(
          lastTriAnalysisDate(rows,
              patientName: 'نور',
              phone: '0911111111',
              normalize: arNorm,
              normPhone: normPhone),
          '2026-08-01',
          reason: 'الأحدث دائماً');
    });

    test('triRepeatBlockMessage القديمة لم تتغيّر (لا انحدار في م149)', () {
      expect(
          triRepeatBlockMessage(
              lastDate: '2026-08-01', today: '2026-08-19', repeatMonths: 6),
          contains('لا يمكن إجراء تحليل ثلاثي جديد'));
      expect(
          triRepeatBlockMessage(
              lastDate: '2026-01-01', today: '2026-08-19', repeatMonths: 6),
          isNull);
    });
  });
}
