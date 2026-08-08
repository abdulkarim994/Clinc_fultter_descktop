/// م-إصلاح — النبض الموحّد: bumpDataRevision ينبض مزوّدات النسخة الثلاثة
/// دفعةً واحدة، فتُعاد بناء كل الشاشات المرتبطة فوراً (إصلاح تأخر تحديث
/// الدين المتبقي على المكتب — بلاغ المالك).
library;

import 'package:dental_clinic_flutter/app/data_revision.dart';
import 'package:dental_clinic_flutter/features/expenses/expenses_screen.dart'
    show expensesRefreshProvider;
import 'package:dental_clinic_flutter/features/finance/finance_screen.dart'
    show financeRevProvider;
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show patientsRevProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bumpDataRevision ينبض patients + finance + expenses معاً',
      (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (ctx, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));

    final p0 = ref.read(patientsRevProvider);
    final f0 = ref.read(financeRevProvider);
    final e0 = ref.read(expensesRefreshProvider);

    bumpDataRevision(ref);

    // النبضة الواحدة تحرّك المزوّدات الثلاثة — فأي شاشة تراقب أياً منها
    // تُعاد بناءً (الرئيسية patients/finance، المالية finance، المصروفات).
    expect(ref.read(patientsRevProvider), p0 + 1);
    expect(ref.read(financeRevProvider), f0 + 1);
    expect(ref.read(expensesRefreshProvider), e0 + 1);
  });
}
