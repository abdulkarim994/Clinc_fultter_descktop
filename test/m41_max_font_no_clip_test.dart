/// اختبار م41 — «التكبير بلا قص»: التطبيق على **المقياس الأقصى**
/// (خيار «أكبر» 1.45 × معايرة 1.12 = ‎1.624) يقلّب التبويبات الخمسة
/// وملف مريض والإعدادات — وأي فيضان RenderFlex يُعدّ **فشلاً**.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m41_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('المقياس الأقصى: تقليب الشاشات كلها بلا أي فيضان', (
    tester,
  ) async {
    // نافذة هاتف واقعية (كالجهاز): 1080×2400 بكثافة 2.75 ≈ 393dp.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    // اعتبر أي فيضان RenderFlex فشلاً صريحاً (مع موقعه).
    final overflows = <String>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = '${details.exception}';
      if (msg.contains('RenderFlex overflowed')) {
        // موقع الودجت المسبب (أول سطر lib/ في التفاصيل).
        final full = details.toString();
        final m = RegExp(r'lib/[^\s:]+\.dart:\d+').firstMatch(full);
        overflows.add('${details.summary} @ ${m?.group(0) ?? 'unknown'}');
        return; // سجّل وتابع — نجمع كل المواضع بدل السقوط عند الأول.
      }
      oldOnError?.call(details);
    };

    final seed = ProviderContainer(
      overrides: [
        staffAdminSession(),
        dbDirProvider.overrideWithValue(tmp.path),
      ],
    );
    final auth = seed.read(authServiceProvider);
    await auth.register('doc@clinic.ly', 'secret12');
    await auth.login('doc@clinic.ly', 'secret12', remember: true);
    final repos = seed.read(reposProvider);
    repos.settings.set('app.config', {
      'centerName': 'مركز الابتسامة الوطني للأسنان',
      'clinics': ['العيادة الاستشارية الأولى', 'ع2'],
      'services': ['حشو عصب تجميلي', 'تنظيف'],
      'payments': ['كاش', 'تحويل بنكي'],
    });
    // بيانات واقعية: سجل + دين + تركيبة + موعد لمريض باسم طويل.
    repos.records.upsertLocal({
      'id': 'r1',
      'name': 'عبدالرحمن الهاشمي الطويل',
      'patient_name': 'عبدالرحمن الهاشمي الطويل',
      'clinic': 'العيادة الاستشارية الأولى',
      'service': 'حشو عصب تجميلي',
      'date': '2026-07-20',
      'amount': 12500,
      'payment': 'تحويل بنكي',
    });
    repos.debts.upsertLocal({
      'id': 'd1',
      'name': 'عبدالرحمن الهاشمي الطويل',
      'patient_name': 'عبدالرحمن الهاشمي الطويل',
      'clinic': 'العيادة الاستشارية الأولى',
      'service': 'تقويم شامل',
      'date': '2026-07-21',
      'totalAmount': 90000,
      'paidAmount': 1500,
      'remaining': 88500,
      'status': 'partial',
      'installments': const [],
    });
    // مقياس الخط: خيار «أكبر» (قيمة Vue الحرفية).
    seed
        .read(localDbProvider)
        .execute(
          "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
          "VALUES ('dental_font_size', '1.45', datetime('now'))",
        );
    seed.dispose();

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
    await tester.pump(const Duration(milliseconds: 250));

    // تقليب التبويبات الخمسة.
    for (final tab in ['الرئيسية', 'السجلات', 'المالية', 'إضافي', 'الحجوزات']) {
      debugPrint('M41-STEP: $tab');
      await tester.tap(find.text(tab).first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
    }
    debugPrint('M41-STEP: tabs done');

    // ملف المريض (بحث ثم فتح).
    await tester.tap(find.text('السجلات').first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 350));
    debugPrint('M41-STEP: search');
    await tester.enterText(
      find.byKey(const Key('patient-search')),
      'عبدالرحمن',
    );
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('M41-STEP: open profile');
    await tester.tap(
      find.byKey(const Key('patient-card-عبدالرحمن الهاشمي الطويل')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('M41-STEP: profile ok');

    // الإعدادات.
    await tester.tap(find.byTooltip('الإعدادات'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    debugPrint('M41-STEP: settings ok');

    // إعادة المعالج قبل أي expect (متطلب flutter_test).
    FlutterError.onError = oldOnError;
    expect(
      overflows,
      isEmpty,
      reason: 'فيضانات على المقياس الأقصى:\n${overflows.join('\n')}',
    );
  });
}
