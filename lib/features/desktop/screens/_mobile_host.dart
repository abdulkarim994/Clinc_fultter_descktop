/// مضيف مؤقت لواجهة هاتفية داخل صدفة سطح المكتب — يحصرها بعرض الهاتف
/// في بطاقة متمركزة ريثما تكتمل النسخة المكتبية للشاشة. أي دفعات صفحات
/// داخلية تُحصر في Navigator متداخل كي لا تغطي الشاشة كلها.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class MobileHost extends StatelessWidget {
  const MobileHost({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: BrandColors.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BrandColors.line),
          ),
          child: ClipRect(
            child: Navigator(
              onGenerateRoute: (s) => MaterialPageRoute(
                settings: s,
                builder: (_) => Scaffold(
                  backgroundColor: BrandColors.paper,
                  body: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
