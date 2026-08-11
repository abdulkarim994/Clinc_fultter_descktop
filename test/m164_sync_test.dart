/// م164 — مزامنة المواعيد بنظام العيادات ودورة الحياة: جهازان حقيقيان
/// (Offline ثم Online) عبر الخادم المزيف — حقول العيادة والاستراحة وختم
/// الأرشفة تنجو بالمزامنة، وتنظيف الأرشيف يصل الجهاز الآخر شاهدةَ قبر،
/// ومواعيد عيادتين لا تختلط.
library;

import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show jsNow, jsNumOr0;
import 'package:dental_clinic_flutter/features/appointments/appt_lifecycle.dart'
    show archivedIdsToPurge;
import 'package:flutter_test/flutter_test.dart';

import 'm164_sync_device.dart';

void main() {
  late FakeServerBundle bundle;

  setUp(() => bundle = FakeServerBundle());
  tearDown(() => bundle.dispose());

  test('حقول م164 (عيادة/استراحة/ختم الأرشفة) تنجو من جهازٍ لآخر', () async {
    final a = bundle.a, b = bundle.b;
    a.repos.appointments.upsertLocal({
      'id': 'ap1',
      'name': 'وليد',
      'date': '2026-08-11',
      'time': '10:00',
      'service': 'كشف',
      'clinic': 'الصفوة',
      'clinic_id': 'c-safwa',
      'status': 'completed',
      'archivedOn': '2026-08-11',
      'durationMin': 45,
      '_t': 'a',
    });
    a.repos.appointments.upsertLocal({
      'id': 'br1',
      'name': 'غداء',
      'date': '2026-08-11',
      'time': '13:00',
      'isBreak': 1,
      'durationMin': 30,
      'clinic': 'الصفوة',
      'status': 'pending',
      '_t': 'a',
    });
    await bundle.converge();

    final onB = b.repos.appointments.getById('ap1')!;
    expect(onB['clinic'], 'الصفوة');
    expect(onB['clinic_id'], 'c-safwa');
    expect(onB['status'], 'completed');
    expect(onB['archivedOn'], '2026-08-11',
        reason: 'ختم الأرشفة (كتلة data) ينجو');
    expect(jsNumOr0(onB['durationMin']).toInt(), 45);

    final brB = b.repos.appointments.getById('br1')!;
    expect(jsNumOr0(brB['isBreak']).toInt(), 1,
        reason: 'علم الاستراحة الرقمي ينجو');
  });

  test('تنظيف الأرشيف بعد يومين يصل الجهاز الآخر شاهدةَ قبر', () async {
    final a = bundle.a, b = bundle.b;
    a.repos.appointments.upsertLocal({
      'id': 'old1',
      'name': 'قديم',
      'date': '2026-08-01',
      'clinic': 'الصفوة',
      'status': 'completed',
      'archivedOn': '2026-08-01',
      '_t': 'a',
    });
    await bundle.converge();
    expect(b.repos.appointments.getById('old1'), isNotNull);

    // التنظيف على أ (نفس مسار الشاشة: archivedIdsToPurge ثم delete).
    final ids =
        archivedIdsToPurge(a.repos.appointments.getAll(), '2026-08-11');
    expect(ids, ['old1']);
    for (final id in ids) {
      a.repos.appointments.delete(id);
    }
    await bundle.converge();

    expect(a.repos.appointments.getById('old1'), isNull);
    expect(b.repos.appointments.getById('old1'), isNull,
        reason: 'الحذف وصل ب عبر المزامنة (شاهدة قبر لا صف)');
  });

  test('عيادتان على جهازين Offline ثم Online — لا اختلاط ولا فقد', () async {
    final a = bundle.a, b = bundle.b;
    // كلٌّ يعمل Offline: أ يحجز للصفوة وب لكاريزما بنفس اليوم والوقت.
    a.repos.appointments.upsertLocal({
      'id': 'a-safwa',
      'name': 'مريض أ',
      'date': '2026-08-12',
      'time': '09:00',
      'clinic': 'الصفوة',
      'clinic_id': 'c-safwa',
      'status': 'pending',
      '_mod': jsNow(),
      '_t': 'a',
    });
    b.repos.appointments.upsertLocal({
      'id': 'b-karizma',
      'name': 'مريض ب',
      'date': '2026-08-12',
      'time': '09:00',
      'clinic': 'كاريزما',
      'clinic_id': 'c-karizma',
      'status': 'pending',
      '_mod': jsNow(),
      '_t': 'a',
    });
    await bundle.converge();

    for (final d in [a, b]) {
      final all = d.repos.appointments.getAll();
      expect(all, hasLength(2), reason: 'الصفان معاً على ${d.name}');
      expect(
          all.singleWhere((r) => r['id'] == 'a-safwa')['clinic'], 'الصفوة');
      expect(all.singleWhere((r) => r['id'] == 'b-karizma')['clinic'],
          'كاريزما');
    }
  });
}
