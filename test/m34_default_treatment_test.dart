/// اختبارات م34 — المعالجة الافتراضية (توأم defaultService في الأصل):
/// الأولوية: آخر اختيار للمستخدم ← المُعدّة في الإعدادات ← أول القائمة،
/// مع التحصين ضد قيمة لم تعد في القائمة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/records/default_treatment.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m34_');
    c = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('سلسلة الأولوية: آخر اختيار ← المُعدّة ← الأولى', () {
    final db = c.read(localDbProvider);
    const services = ['حشو عصب', 'تنظيف', 'تقويم'];

    // لا آخر اختيار ولا إعداد ⇒ الأولى.
    expect(defaultServiceFor(db, {}, services), 'حشو عصب');

    // إعداد فقط ⇒ المُعدّة.
    expect(
      defaultServiceFor(db, {'defaultTreatment': 'تنظيف'}, services),
      'تنظيف',
    );

    // آخر اختيار يتقدم على المُعدّة.
    rememberTreatment(db, 'تقويم');
    expect(
      defaultServiceFor(db, {'defaultTreatment': 'تنظيف'}, services),
      'تقويم',
    );
  });

  test('v57 — الضبط الصريح الأحدث يفوز على آخر اختيار أقدم', () {
    final db = c.read(localDbProvider);
    const services = ['حشو', 'تنظيف', 'تقويم'];
    String stamp(Duration offset) => DateTime.now()
        .toUtc()
        .add(offset)
        .toIso8601String()
        .substring(0, 19)
        .replaceAll('T', ' ');

    // آخر اختيار (الآن) ثم ضبط أحدث منه ⇒ الضبط يفوز.
    rememberTreatment(db, 'تقويم');
    expect(
      defaultServiceFor(db, {
        'defaultTreatment': 'تنظيف',
        'defaultTreatmentAt': stamp(const Duration(minutes: 5)),
      }, services),
      'تنظيف',
      reason: 'الضبط أحدث من آخر الاختيار ⇒ يفوز',
    );

    // اختيار جديد بعد الضبط (ختم الضبط في الماضي) ⇒ آخر الاختيار يعود.
    rememberTreatment(db, 'تقويم');
    expect(
      defaultServiceFor(db, {
        'defaultTreatment': 'تنظيف',
        'defaultTreatmentAt': stamp(const Duration(minutes: -5)),
      }, services),
      'تقويم',
      reason: 'آخر الاختيار أحدث من الضبط ⇒ يفوز',
    );

    // مسح آخر الاختيار (كما تفعل الإعدادات لحظة الضبط) ⇒ المُعدّة.
    clearLastTreatment(db);
    expect(
      defaultServiceFor(db, {
        'defaultTreatment': 'تنظيف',
        'defaultTreatmentAt': stamp(const Duration(minutes: -5)),
      }, services),
      'تنظيف',
    );
  });

  test('التحصين: قيمة محفوظة/مُعدّة لم تعد في القائمة تُتجاهل', () {
    final db = c.read(localDbProvider);
    rememberTreatment(db, 'خدمة محذوفة');
    expect(
      defaultServiceFor(
        db,
        {'defaultTreatment': 'خدمة مُعاد تسميتها'},
        ['حشو', 'خلع'],
      ),
      'حشو',
      reason: 'كلاهما بائد ⇒ السقوط لأول القائمة',
    );
  });

  test('قائمة فارغة ⇒ سلسلة فارغة (لا انهيار)', () {
    final db = c.read(localDbProvider);
    expect(defaultServiceFor(db, {}, const []), '');
  });

  testWidgets(
    'الخيار ظاهر داخل «العيادات والمعالجات» واختياره يُحفظ في config',
    (tester) async {
      final auth = c.read(authServiceProvider);
      await auth.register('doc@clinic.ly', 'secret12');
      await auth.login('doc@clinic.ly', 'secret12', remember: true);
      c.read(reposProvider).settings.set('app.config', {
        'centerName': 'مركز الاختبار',
        'clinics': ['ع1'],
        'services': ['حشو', 'تنظيف', 'تقويم'],
        'payments': ['كاش'],
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffAdminSession(),
            dbDirProvider.overrideWithValue(tmp.path),
          ],
          child: const DentalApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // فتح الإعدادات ← مجموعة «العيادات والمعالجات».
      await tester.tap(find.byTooltip('الإعدادات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.byKey(const Key('group-clinic')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // الخيار موجود في هذه المجموعة.
      final dd = find.byKey(const Key('default-treatment-select'));
      await tester.scrollUntilVisible(
        dd,
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) =>
                  w is Scrollable &&
                  axisDirectionToAxis(w.axisDirection) == Axis.vertical,
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(dd, findsOneWidget);
      expect(find.text('المعالجة الافتراضية'), findsOneWidget);

      // اختيار «تنظيف» يحفظ فوراً.
      await tester.tap(dd);
      await tester.pumpAndSettle();
      await tester.tap(find.text('تنظيف').last);
      await tester.pumpAndSettle();
      final cfg = c.read(reposProvider).settings.get('app.config') as Map;
      expect(cfg['defaultTreatment'], 'تنظيف');
      // v57 — الختم الزمني يُحفظ ويُمسح آخر الاختيار المحلي فوراً.
      expect(
        '${cfg['defaultTreatmentAt'] ?? ''}'.isNotEmpty,
        isTrue,
        reason: 'ختم الضبط الصريح محفوظ ومتزامن',
      );
      expect(
        lastTreatment(c.read(localDbProvider)),
        '',
        reason: 'آخر الاختيار المحلي مُسح لحظة الضبط',
      );
    },
  );
}
