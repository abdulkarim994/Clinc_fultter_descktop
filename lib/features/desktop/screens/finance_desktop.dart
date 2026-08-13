/// م178 — «المالية» في سطح المكتب صارت شاشة الأرباح المكتبية المخصصة
/// بأقسامها الثلاثة (الشهرية/السنوية/كشف الحساب): زال مبدّل الشرائح
/// الوسيط واستعارة واجهة الهاتف المكبرة (MobileHost) معاً — التخطيط
/// العريض والصلاحيات كلها داخل DesktopProfitsScreen نفسها.
library;

import 'package:flutter/material.dart';

import 'profits_desktop.dart';

class DesktopFinanceScreen extends StatelessWidget {
  const DesktopFinanceScreen({super.key});

  @override
  Widget build(BuildContext context) => const DesktopProfitsScreen();
}
