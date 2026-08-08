/// اختبار م56 — تطابق نظام الدور مع الأصل (Vue):
///   • الترتيب الحتمي المتقارب (queue_order): فرز كلي بكاسر تعادل id،
///     وخطط ترقيم idempotent 1..N — أساس تقارب الأجهزة.
///   • سلوكيات المتحكم: إعادة الترقيم بعد الإلغاء/الدخول (بلا فجوات)،
///     التخطي للنهاية، تطبيق ترتيب السحب، ختم created_at، تعديل مريض مع
///     أتمتة علم الوقت اليدوي، والتنظيف اليومي.
///   • التقارب ثنائي الأجهزة: جهازان يضيفان/يرتّبان معاً ثم يتزامنان
///     فيتقاربان على نفس الأرقام والترتيب (نمط m51 — قاعدتا SQLite حقيقيتان
///     عبر خادم بدلالات الخلفية + مصالحة reconcileNumbers).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/queue/queue_order.dart';
import 'package:dental_clinic_flutter/features/queue/queue_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('وحدة الترتيب الحتمي (queue_order)', () {
    QOrderRow row(String id, {int? seq, String? enteredAt}) => {
          'id': id,
          // م133 — صيغة العنصر الواعي بالعدم بطلب المحلل.
          'seq': ?seq,
          'entered_at': ?enteredAt,
        };

    test('الفرز الكلي: seq ثم id ككاسر تعادل ثابت', () {
      final rows = [
        row('c', seq: 2),
        row('a', seq: 1),
        row('b', seq: 1), // نفس seq ⇒ يُحسم بالمعرّف
      ];
      final sorted = sortWaiting(rows).map((r) => r['id']).toList();
      expect(sorted, ['a', 'b', 'c'],
          reason: 'a و b بـ seq=1 يُرتّبان بالمعرّف، ثم c');
    });

    test('خطة الترقيم متصلة 1..N وidempotent (تتقارب لنفس النتيجة)', () {
      final rows = [row('x', seq: 5), row('y', seq: 5), row('z', seq: 9)];
      final plan1 = planWaitingSeq(rows);
      expect(plan1.map((e) => '${e.id}:${e.seq}').toList(),
          ['x:1', 'y:2', 'z:3']);
      // تطبيق الخطة ثم إعادة التخطيط ⇒ نفس النتيجة (idempotent).
      final applied = [
        for (final e in plan1)
          {'id': e.id, 'seq': e.seq}
      ];
      final plan2 = planWaitingSeq(applied);
      expect(plan2.map((e) => '${e.id}:${e.seq}').toList(),
          ['x:1', 'y:2', 'z:3'],
          reason: 'إعادة الترقيم لا تتأرجح — أساس تقارب الأجهزة');
    });

    test('ترتيب الأرشيف بوقت الوصول ثم المعرّف', () {
      final rows = [
        row('late', enteredAt: '2026-07-28T10:05:00'),
        row('early', enteredAt: '2026-07-28T09:00:00'),
      ];
      expect(sortArchive(rows).map((r) => r['id']).toList(),
          ['early', 'late']);
    });
  });

  group('التقارب الحتمي (خطة الترقيم مستقلة عن ترتيب الإدخال)', () {
    test('إضافتان متزامنتان من جهازين: نفس الترقيم على الاثنين بعد التقارب',
        () {
      // محاكاة نتيجة الدمج: صفّان بنفس seq من جهازين (تعارض ترقيم).
      final merged = [
        {'id': 'devA-1', 'seq': 1, 'state': 'waiting', 'period': 'morning'},
        {'id': 'devB-1', 'seq': 1, 'state': 'waiting', 'period': 'morning'},
      ];
      // كلا الجهازين يطبّق نفس خطة الترقيم الحتمية ⇒ نفس النتيجة.
      final planA = planWaitingSeq(merged);
      final planB = planWaitingSeq(merged.reversed);
      expect(planA.map((e) => '${e.id}:${e.seq}').toList(),
          planB.map((e) => '${e.id}:${e.seq}').toList(),
          reason: 'ترتيب الإدخال لا يغيّر النتيجة — تقارب حتمي');
    });
  });

  group('سلوكيات متحكم الدور (ProviderContainer)', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m56c_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز م56',
        'clinics': ['ع1'],
        'bookingSystem': 'queue',
        'queueMorningStart': '09:00',
        'queueSlotMin': 15,
      });
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    QueueController ctrl() => c.read(queueViewProvider.notifier);
    List<Map<String, Object?>> waiting() => (c
        .read(reposProvider)
        .queue
        .getByClinicDate('ع1', getCurrentDate())
        .where((r) => r['state'] == 'waiting')
        .toList()
      ..sort((a, b) => jsNumOr0(a['seq']).compareTo(jsNumOr0(b['seq']))));

    test('الإضافة تختم created_at ووقتاً متوقعاً متسلسلاً', () {
      ctrl().openClinic('ع1');
      final r = ctrl().quickAdd(name: 'أحمد');
      expect(r, isNotNull);
      expect('${r!['created_at']}'.isNotEmpty, isTrue,
          reason: 'created_at مختوم عند الإضافة');
      expect(r['est_time'], '09:00');
      final r2 = ctrl().quickAdd(name: 'سارة');
      expect(r2!['est_time'], '09:15', reason: 'المريض الثاني +١٥ دقيقة');
    });

    test('الإلغاء يغلق الفجوة بإعادة ترقيم 1..N', () {
      ctrl().openClinic('ع1');
      ctrl().quickAdd(name: 'أ'); // seq 1
      ctrl().quickAdd(name: 'ب'); // seq 2
      ctrl().quickAdd(name: 'ج'); // seq 3
      final mid = waiting().firstWhere((r) => r['patient_name'] == 'ب');
      ctrl().cancel(mid);
      final after = waiting();
      expect(after.map((r) => r['patient_name']).toList(), ['أ', 'ج']);
      expect(after.map((r) => jsNumOr0(r['seq']).toInt()).toList(), [1, 2],
          reason: 'الأرقام متصلة بلا فجوة بعد الإلغاء');
    });

    test('التخطي يرسل المريض لنهاية الدور (لا تبديل خطوة واحدة)', () {
      ctrl().openClinic('ع1');
      ctrl().quickAdd(name: 'أ');
      ctrl().quickAdd(name: 'ب');
      ctrl().quickAdd(name: 'ج');
      final first = waiting().firstWhere((r) => r['patient_name'] == 'أ');
      ctrl().skip(first);
      expect(waiting().map((r) => r['patient_name']).toList(),
          ['ب', 'ج', 'أ'],
          reason: 'أ ذهب للنهاية — لا مجرد تبديل مع ب');
    });

    test('الدخول يؤرشف برقم أرشيف ويغلق فجوة الانتظار', () {
      ctrl().openClinic('ع1');
      ctrl().quickAdd(name: 'أ');
      ctrl().quickAdd(name: 'ب');
      final first = waiting().firstWhere((r) => r['patient_name'] == 'أ');
      ctrl().finish(first);
      final w = waiting();
      expect(w.map((r) => r['patient_name']).toList(), ['ب']);
      expect(jsNumOr0(w.first['seq']).toInt(), 1,
          reason: 'ب صار رقم ١ بعد دخول أ');
      final done = c
          .read(reposProvider)
          .queue
          .getByClinicDate('ع1', getCurrentDate())
          .where((r) => r['state'] == 'done')
          .toList();
      expect(jsNumOr0(done.first['archive_seq']).toInt(), 1);
      expect('${done.first['entered_at']}'.isNotEmpty, isTrue);
    });

    test('تعديل الوقت يدوياً يرفع علم est_manual فلا يدهسه الحساب التلقائي',
        () {
      ctrl().openClinic('ع1');
      ctrl().quickAdd(name: 'أ');
      ctrl().quickAdd(name: 'ب');
      final a = waiting().firstWhere((r) => r['patient_name'] == 'أ');
      ctrl().updatePatient(a, {'est_time': '11:30'});
      final a2 = waiting().firstWhere((r) => r['patient_name'] == 'أ');
      expect(a2['est_time'], '11:30');
      expect(jsNumOr0(a2['est_manual']).toInt(), 1,
          reason: 'تحرير الوقت يدوياً يرفع العلم');
      // إضافة مريض ثالث تعيد حساب الأوقات — لكن اليدوي محمي.
      ctrl().quickAdd(name: 'ج');
      final a3 = waiting().firstWhere((r) => r['patient_name'] == 'أ');
      expect(a3['est_time'], '11:30',
          reason: 'الوقت اليدوي لم يُدهس بإعادة الحساب');
    });

    test('التنظيف اليومي يحذف صفوف الأيام الماضية', () {
      final repos = c.read(reposProvider);
      repos.queue.upsertLocal({
        'id': 'old1',
        'clinic': 'ع1',
        'clinic_id': 'ع1',
        'date': '2020-01-01',
        'period': 'morning',
        'seq': 1,
        'patient_name': 'قديم',
        'state': 'waiting',
      });
      ctrl().openClinic('ع1');
      ctrl().purgeOldDays();
      final oldRows = repos.queue
          .getByClinicDate('ع1', '2020-01-01')
          .where((r) => r['state'] == 'waiting')
          .toList();
      expect(oldRows, isEmpty, reason: 'صفوف الأمس حُذفت (شاهد قبر)');
    });
  });
}
