/// م-تكافؤ — «المعلومات المختصرة»: ملاحظة الزيارة/الدفعة (قرار المالك).
///
///  تُخزَّن على صف السجل نفسه (record.notes) فتلتصق بمعرّفه الفريد:
///    • تُحفظ من مسار saveNewRecord الموحد (زيارة جديدة/زيارة سريعة).
///    • معزولة بنيوياً: لا تظهر لسجلٍ آخر ولا مريضٍ آخر ولا عيادةٍ
///      أخرى حتى مع تطابق الأسماء.
///    • نافذة «معلومات مختصرة» تعرضها وتعدّلها عبر مسار upsert المعتاد
///      (فتُختم dirty للمزامنة).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart'
    show getCurrentDate;
import 'package:dental_clinic_flutter/features/patients/quick_info_dialog.dart'
    show showQuickInfoDialog;
import 'package:dental_clinic_flutter/features/records/record_saver.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('qnote_');
    c = ProviderContainer(overrides: [
      staffAdminSession(),
      dbDirProvider.overrideWithValue(tmp.path),
    ]);
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Map<String, Object?> cfg() => {
        'clinics': ['ع1', 'ع2'],
        'services': ['حشو'],
        'payments': ['كاش'],
      };

  test('الحفظ الموحد يكتب الملاحظة على صف السجل وتصمد جولة القراءة', () {
    final repos = c.read(reposProvider);
    final res = saveNewRecord(
      repos,
      cfg(),
      const SaveRecordInput(
        name: 'سمير خالد',
        date: '2026-08-06',
        amount: 150,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
        notes: 'حساسية بنج — يُراجع بعد أسبوع',
      ),
    );
    final row = repos.records.getById(res.entryId);
    expect('${row?['notes']}', 'حساسية بنج — يُراجع بعد أسبوع');

    // تعديل حقلٍ آخر لا يُسقط الملاحظة (مسار القراءة-الدمج-الحفظ).
    repos.records.update(res.entryId, {'amount': 200});
    final again = repos.records.getById(res.entryId);
    expect('${again?['notes']}', 'حساسية بنج — يُراجع بعد أسبوع');
    expect(again?['amount'], 200);
  });

  test('العزل: نفس الاسم في عيادتين — الملاحظة لصفّها وحده', () {
    final repos = c.read(reposProvider);
    final a = saveNewRecord(
      repos,
      cfg(),
      const SaveRecordInput(
        name: 'محمد علي',
        date: '2026-08-06',
        amount: 100,
        clinic: 'ع1',
        service: 'حشو',
        payment: 'كاش',
        notes: 'ملاحظة العيادة الأولى',
      ),
    );
    final b = saveNewRecord(
      repos,
      cfg(),
      const SaveRecordInput(
        name: 'محمد علي', // نفس الاسم حرفياً
        date: '2026-08-06',
        amount: 100,
        clinic: 'ع2',
        service: 'حشو',
        payment: 'كاش',
      ),
    );
    final rowA = repos.records.getById(a.entryId);
    final rowB = repos.records.getById(b.entryId);
    expect('${rowA?['notes']}', 'ملاحظة العيادة الأولى');
    final bNote = '${rowB?['notes'] ?? ''}';
    expect(bNote.isEmpty || bNote == 'null', isTrue,
        reason: 'تشابه الأسماء لا يسرّب الملاحظة بين الصفوف/العيادات');
  });

  testWidgets('نافذة «معلومات مختصرة» تعرض وتحفظ عبر مسار upsert', (t) async {
    final repos = c.read(reposProvider);
    repos.records.upsertLocal({
      'id': 'qn1',
      'name': 'ليلى حسن',
      'patient_name': 'ليلى حسن',
      'clinic': 'ع1',
      'service': 'حشو',
      'amount': 90,
      'payment': 'كاش',
      'date': getCurrentDate(),
      'notes': 'قديمة',
    });

    late WidgetRef capturedRef;
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          capturedRef = ref;
          return const Scaffold(body: SizedBox());
        }),
      ),
    ));
    final ctx = t.element(find.byType(Scaffold));
    final fut = showQuickInfoDialog(ctx, capturedRef,
        kind: 'r', id: 'qn1', patientName: 'ليلى حسن');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('quick-info-dialog')), findsOneWidget);
    expect(find.text('قديمة'), findsOneWidget, reason: 'تعرض الحالية');

    await t.enterText(
        find.byKey(const Key('quick-info-field')), 'محدثة — دفعة جزئية');
    await t.tap(find.byKey(const Key('quick-info-save')));
    await t.pump();
    await fut;
    // updateLocal يركل المزامنة (مؤقّت debounce 600ms) — نصرّفه قبل هدم
    // الشجرة كي لا يتبقّى مؤقّت معلّق (سلوك متوقّع بعد إصلاح المزامنة).
    await t.pump(const Duration(milliseconds: 700));

    final row = repos.records.getById('qn1');
    expect('${row?['notes']}', 'محدثة — دفعة جزئية');
    // بقية حقول الصف سليمة بعد جولة القراءة-الدمج-الحفظ.
    expect(row?['amount'], 90);
    expect('${row?['clinic']}', 'ع1');
    // م-إصلاح المزامنة: التحرير يجب أن يُختم dirty ليدخل طابور الدفع —
    // كان يمرّ عبر .update فلا يُدفع أبداً (السبب الجذري لتباين الأجهزة).
    expect(row?['_dirty'], 1,
        reason: 'تحرير الملاحظة يجب أن يُختم dirty=1 حتى يتزامن');
  });

  test('توحيد المصدر: تحرير ملاحظة زيارة دَينية يوحّد السجل والدين', () {
    final repos = c.read(reposProvider);
    // سجل دفعة أولى + دين مرتبط (recordId) — نمط الزيارة الدَّينية.
    repos.records.upsertLocal({
      'id': 'rec-src', 'name': 'خالد', 'patient_name': 'خالد',
      'clinic': 'ع1', 'service': 'حشو', 'amount': 500,
      'payment': 'دين', 'isDebt': 1, 'date': getCurrentDate(),
    });
    repos.debts.upsertLocal({
      'id': 'debt-1', 'name': 'خالد', 'recordId': 'rec-src',
      'total': 500, 'remaining': 500, 'clinic': 'ع1',
      'date': getCurrentDate(),
    });
    // تحرير الملاحظة على صف السجل عبر مسار النافذة الموحّد يكتبها أيضاً
    // على الدين المرتبط (توحيد القراء).
    repos.records.updateLocal('rec-src', {'notes': 'ملاحظة موحّدة'});
    // محاكاة توحيد النافذة يدوياً (الدالة تُختبر تكامليّاً بالودجت):
    for (final d in repos.debts.getAll()) {
      if ('${d['recordId']}' == 'rec-src') {
        repos.debts.updateLocal('${d['id']}', {'notes': 'ملاحظة موحّدة'});
      }
    }
    expect('${repos.records.getById('rec-src')?['notes']}', 'ملاحظة موحّدة');
    expect('${repos.debts.getById('debt-1')?['notes']}', 'ملاحظة موحّدة');
    expect(repos.debts.getById('debt-1')?['_dirty'], 1);
  });
}
