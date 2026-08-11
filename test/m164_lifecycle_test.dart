/// م164 — دورة حياة الموعد ونظام العيادات (المنطق النقي):
/// الكتالوج والتطبيع والحالات النهائية والانتقال بنقرة، أرشيف اليومين
/// وتنظيفه، العيادة الإلزامية والفلترة، الاستراحة واستثناءاتها، شبكة
/// أوقات الدوام وكشف التعارض، وbookingSystemOf كمصدرٍ وحيد.
library;

import 'package:dental_clinic_flutter/features/appointments/appt_lifecycle.dart';
import 'package:dental_clinic_flutter/features/appointments/appointments_logic.dart'
    show buildApptMap, upcomingAppts;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('كتالوج الحالات', () {
    test('القيم القديمة pending/scheduled/الفارغ تُقرأ «قادم»', () {
      for (final v in ['pending', 'scheduled', 'upcoming', '', null, 'x']) {
        expect(normApptStatus(v), 'upcoming', reason: '$v');
      }
    });

    test('الاسم يظهر دائماً لكل حالة (اللون ليس وحده)', () {
      expect(apptStatusLabel('pending'), 'قادم');
      expect(apptStatusLabel('confirmed'), 'مؤكد');
      expect(apptStatusLabel('arrived'), 'حضر');
      expect(apptStatusLabel('waiting'), 'بالانتظار');
      expect(apptStatusLabel('in_treatment'), 'داخل المعالجة');
      expect(apptStatusLabel('completed'), 'مكتمل');
      expect(apptStatusLabel('cancelled'), 'ملغى');
      expect(apptStatusLabel('no_show'), 'لم يحضر');
    });

    test('النهائية: مكتمل/ملغى/لم يحضر فقط', () {
      expect(isTerminalStatus('completed'), isTrue);
      expect(isTerminalStatus('cancelled'), isTrue);
      expect(isTerminalStatus('no_show'), isTrue);
      for (final v in ['pending', 'confirmed', 'arrived', 'waiting',
          'in_treatment']) {
        expect(isTerminalStatus(v), isFalse, reason: v);
      }
    });

    test('الحالة التالية بنقرة تتبع سير العمل وتنتهي عند مكتمل', () {
      expect(nextApptStatus('pending'), 'confirmed');
      expect(nextApptStatus('confirmed'), 'arrived');
      expect(nextApptStatus('arrived'), 'waiting');
      expect(nextApptStatus('waiting'), 'in_treatment');
      expect(nextApptStatus('in_treatment'), 'completed');
      expect(nextApptStatus('completed'), isNull);
      expect(nextApptStatus('cancelled'), isNull);
    });
  });

  group('أرشيف اليومين', () {
    test('التقسيم: النشِط في الجدول والنهائي في الأرشيف — لا ازدواج', () {
      final rows = [
        {'id': 'a', 'status': 'pending'},
        {'id': 'b', 'status': 'completed'},
        {'id': 'c', 'status': 'no_show'},
        {'id': 'd', 'status': 'in_treatment'},
        // صف السجل للقراءة لا يُؤرشف أبداً.
        {'id': 'rec-1', 'status': 'completed', '_src': 'rec'},
      ];
      final (active, archived) = splitDayRows(rows);
      expect(active.map((a) => a['id']), ['a', 'd', 'rec-1']);
      expect(archived.map((a) => a['id']), ['b', 'c']);
    });

    test('يوم الأرشفة: ختم archivedOn وإلا تاريخ الموعد (توافق خلفي)', () {
      expect(
          archiveDayOf({'archivedOn': '2026-08-10', 'date': '2026-08-01'}),
          '2026-08-10');
      expect(archiveDayOf({'date': '2026-08-01'}), '2026-08-01');
    });

    test('التنظيف: يبقى يومَي الأرشفة والتالي ويُحذف بعد يومين كاملين', () {
      final appts = [
        {'id': 'today', 'status': 'completed', 'archivedOn': '2026-08-11'},
        {'id': 'yest', 'status': 'cancelled', 'archivedOn': '2026-08-10'},
        {'id': 'old', 'status': 'completed', 'archivedOn': '2026-08-09'},
        {'id': 'older', 'status': 'no_show', 'archivedOn': '2026-08-01'},
        // غير النهائي لا يُحذف مهما قدم تاريخه.
        {'id': 'act', 'status': 'pending', 'date': '2026-01-01'},
        // قديم مكتمل بلا ختم ⇒ تاريخه هو يوم الأرشفة.
        {'id': 'legacy', 'status': 'completed', 'date': '2026-08-05'},
      ];
      expect(archivedIdsToPurge(appts, '2026-08-11'),
          ['old', 'older', 'legacy']);
    });
  });

  group('العيادات', () {
    test('الإلزام عند التعدد فقط — الواحدة تُختار تلقائياً', () {
      expect(clinicRequired({'clinics': ['أ', 'ب']}), isTrue);
      expect(clinicRequired({'clinics': ['أ']}), isFalse);
      expect(clinicRequired(<String, Object?>{}), isFalse);
    });

    test('الفلترة: عيادة/الكل/غير المحددة — لا اختلاط بين عيادتين', () {
      final rows = [
        {'id': '1', 'clinic': 'أ'},
        {'id': '2', 'clinic': 'ب'},
        {'id': '3', 'clinic': ''},
      ];
      expect(filterByClinic(rows, 'أ').single['id'], '1');
      expect(filterByClinic(rows, 'ب').single['id'], '2');
      expect(filterByClinic(rows, '').length, 3);
      expect(filterByClinic(rows, kNoClinic).single['id'], '3');
    });

    test('فلتر «غير محددة» يظهر فقط عند وجود قديمٍ بلا عيادة', () {
      expect(hasUnassignedClinic([{'id': '1', 'clinic': ''}]), isTrue);
      expect(hasUnassignedClinic([{'id': '1', 'clinic': 'أ'}]), isFalse);
      // صف السجل بلا عيادة لا يُحسب (ليس صفاً حقيقياً).
      expect(
          hasUnassignedClinic([
            {'id': 'r', 'clinic': '', '_src': 'rec'},
          ]),
          isFalse);
    });

    test('صفوف السجل/التركيبة تحمل عيادة مصدرها في apptMap', () {
      final map = buildApptMap(
        appointments: const [],
        records: [
          {'id': 'r1', 'name': 'س', 'appointment': '2026-08-12',
            'service': 'حشو', 'clinic': 'أ'},
        ],
        prosthetics: [
          {'id': 'p1', 'name': 'ص', 'appointment': '2026-08-13',
            'clinic': 'ب'},
        ],
      );
      expect(map['2026-08-12']!.single['clinic'], 'أ');
      expect(map['2026-08-13']!.single['clinic'], 'ب');
    });
  });

  group('نوع الحجز — مصدر وحيد', () {
    test('bookingSystemOf: queue فقط عند الإعداد الصريح', () {
      expect(bookingSystemOf({'bookingSystem': 'queue'}), 'queue');
      expect(bookingSystemOf({'bookingSystem': 'traditional'}),
          'traditional');
      expect(bookingSystemOf(<String, Object?>{}), 'traditional');
    });
  });

  group('الاستراحة ☕', () {
    test('علم رقمي isBreak: 1 — والمدة الافتراضية 30', () {
      expect(isBreakRow({'isBreak': 1}), isTrue);
      expect(isBreakRow({'isBreak': 0}), isFalse);
      expect(isBreakRow(<String, Object?>{}), isFalse);
      expect(apptDurationMin({'durationMin': 45}), 45);
      expect(apptDurationMin(<String, Object?>{}), 30);
    });

    test('لا تدخل «القادمة» أبداً (ليست مريضاً)', () {
      final map = buildApptMap(
        appointments: [
          {'id': 'b1', 'name': 'استراحة', 'date': '2099-01-01',
            'isBreak': 1, 'status': 'pending'},
          {'id': 'a1', 'name': 'مريض', 'date': '2099-01-01',
            'status': 'pending'},
          {'id': 'n1', 'name': 'غائب', 'date': '2099-01-02',
            'status': 'no_show'},
        ],
        records: const [],
        prosthetics: const [],
      );
      final up = upcomingAppts(map);
      expect(up.single['id'], 'a1',
          reason: 'الاستراحة و«لم يحضر» مستبعدان');
    });
  });

  group('شبكة الأوقات وكشف التعارض', () {
    test('الشبكة من ساعات الدوام بخطوة 30', () {
      final slots = buildTimeSlots(
          {'workdayStart': '09:00', 'workdayEnd': '11:00'});
      expect(slots, ['09:00', '09:30', '10:00', '10:30']);
      // الافتراضي 09:00–21:00 = 24 خانة.
      expect(buildTimeSlots(<String, Object?>{}).length, 24);
    });

    test('التداخل [الوقت، الوقت+المدة): موعد قائم يتعارض والاستراحة تحجب',
        () {
      final day = [
        {'id': 'a', 'time': '10:00', 'durationMin': 30,
          'status': 'pending'},
        {'id': 'b', 'time': '12:00', 'durationMin': 60, 'isBreak': 1,
          'status': 'pending'},
        // المؤرشف لا يحجب وقته.
        {'id': 'done', 'time': '14:00', 'status': 'completed'},
      ];
      expect(overlappingRow(day, '10:15', 30)!['id'], 'a');
      expect(overlappingRow(day, '10:30', 30), isNull);
      expect(overlappingRow(day, '12:30', 30)!['id'], 'b');
      expect(overlappingRow(day, '14:00', 30), isNull,
          reason: 'المكتمل مؤرشف — لا يحجب');
      // استثناء الصف نفسه عند التعديل.
      expect(overlappingRow(day, '10:00', 30, exceptId: 'a'), isNull);
    });

    test('القادمة لعيادة: فلترة العيادة واستبعاد النهائي والاستراحة', () {
      final map = buildApptMap(
        appointments: [
          {'id': '1', 'name': 'م1', 'date': '2099-01-01', 'clinic': 'أ',
            'status': 'pending', 'time': '10:00'},
          {'id': '2', 'name': 'م2', 'date': '2099-01-01', 'clinic': 'ب',
            'status': 'pending'},
          {'id': '3', 'name': 'م3', 'date': '2099-01-02', 'clinic': 'أ',
            'status': 'completed'},
          {'id': '4', 'name': 'ب', 'date': '2099-01-02', 'clinic': 'أ',
            'isBreak': 1, 'status': 'pending'},
        ],
        records: const [],
        prosthetics: const [],
      );
      final up = upcomingForClinic(map, 'أ', today: '2098-12-31');
      expect(up.single['id'], '1');
      expect(upcomingForClinic(map, '', today: '2098-12-31').length, 2);
    });
  });
}
