/// اختبار م140 (إصلاح عاجل) — قسم الاشتراك يجب أن يُصيَّر **داخل ListView**
/// (كما تستضيفه شاشة الإعدادات: children:[section.body(cfg)]) دون خطأ تخطيط
/// «ارتفاع غير محدود» الذي كان يُظهره فارغاً في نسخة الإصدار.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/settings/subscription_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'staff_test_session.dart' show staffAdminSession;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m140_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('يُصيَّر داخل ListView بلا خطأ تخطيط ولا فراغ', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffAdminSession(),
          dbDirProvider.overrideWithValue(tmp.path),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            // نفس استضافة شاشة الإعدادات: الجسم طفلٌ داخل ListView.
            child: Scaffold(
              body: ListView(children: const [SubscriptionSection()]),
            ),
          ),
        ),
      ),
    );

    // حالة التحميل الأولى بارتفاعٍ محدود — لا خطأ فوراً.
    expect(tester.takeException(), isNull);

    // بعد استقرار التحميل (وضع محلي: evaluate فوري بلا شبكة).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // لا استثناء تخطيط، وجسم القسم صُيِّر فعلاً (البطاقة الأولى ظاهرة).
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('subscription-body')), findsOneWidget);
    expect(find.text('الخطة الحالية'), findsOneWidget);
  });
}
