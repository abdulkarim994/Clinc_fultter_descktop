/// م-تكافؤ — فصل الاتصال عن عرض الرقم (قرار المالك، مهمة التكافؤ ٦).
///
///  كانت صلاحية patients.phones تحجب الرقم **وزر الاتصال معاً** فيعجز
///  الموظف عن الاتصال بالمريض. بعد الفصل:
///    • زر الاتصال (وأزرار واتساب/رسالة في الديون) متاح دائماً.
///    • رؤية الرقم نصاً تبقى خلف الصلاحية (شاشةً وطباعةً).
///  ويغطي أيضاً القسم الرئيسي الجديد «الموظفون والصلاحيات» في الإعدادات.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/theme/app_theme.dart';
import 'package:dental_clinic_flutter/features/staff/staff_session.dart'
    show currentStaffProvider, kCurrentStaff, applyStaffSession;
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// موظف استعلامات **بلا** صلاحية عرض الهواتف.
const restrictedStaff = <String, Object?>{
  'id': 'test-recep',
  'username': 'recep',
  'name': 'موظف الاستقبال',
  'role': 'staff',
  'perms': <String, Object?>{
    'patients.view': true,
    'records.add': true,
    'patients.phones': false, // ← محور الاختبار
  },
};

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('permsep_'));
  tearDown(() {
    BrandColors.darkMode = false;
    applyStaffSession(null); // إعادة مرآة kCurrentStaff لحال الاختبارات
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  Future<void> boot(WidgetTester tester,
      {required Map<String, Object?> staff}) async {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    final auth = c.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    c.read(reposProvider).settings.set('app.config', {
      'centerName': 'مركز الفصل',
      'clinics': ['ع1'],
      'services': ['حشو'],
      'payments': ['كاش'],
    });
    c.read(reposProvider).records.upsertLocal({
      'id': 'r1',
      'name': 'أحمد',
      'patient_name': 'أحمد',
      'clinic': 'ع1',
      'amount': 100,
      'date': '2026-07-01',
      'service': 'حشو',
      'payment': 'كاش',
      'phone': '0911111111',
    });
    c.dispose();
    // الجلسة المقيدة: المزود + المرآة العامة معاً (staffAllowed يقرأ المرآة).
    applyStaffSession(staff);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentStaffProvider.overrideWith((ref) => staff),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
      child: const DentalApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('السجلات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openProfile(WidgetTester t, String name) async {
    await t.enterText(find.byKey(const Key('patient-search')), name);
    await settle(t);
    await t.tap(find.byKey(Key('patient-card-$name')), warnIfMissed: false);
    await settle(t);
  }

  testWidgets('بلا patients.phones: زر الاتصال يبقى (الرؤية وحدها محجوبة)',
      (tester) async {
    await boot(tester, staff: restrictedStaff);
    expect(kCurrentStaff, isNotNull, reason: 'المرآة مضبوطة على المقيد');
    await openProfile(tester, 'أحمد');
    // جوهر الفصل: قبل الإصلاح كان pp-call يختفي مع الصلاحية.
    expect(find.byKey(const Key('pp-call')), findsOneWidget,
        reason: 'إخفاء الرقم يجب ألا يمنع الاتصال بالمريض');
  });

  testWidgets('قسم «الموظفون والصلاحيات» قسمٌ رئيسي في الإعدادات',
      (tester) async {
    await boot(tester, staff: const <String, Object?>{
      'id': 'test-admin',
      'username': 'admin',
      'name': 'الإدارة',
      'role': 'admin',
      'perms': <String, Object?>{},
    });
    await tester.tap(find.byTooltip('الإعدادات'));
    await settle(tester);
    expect(find.text('الموظفون والصلاحيات'), findsWidgets,
        reason: 'القسم انتقل من «المظهر» إلى القائمة الرئيسية');
  });
}
