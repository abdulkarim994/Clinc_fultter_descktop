/// ============================================================================
///  الطابور (نظام الدور) — نسخة سطح المكتب: ترقية خفيفة (مرحلة أولى)
/// ============================================================================
///
///  (قرار المالك): «نظام الحجوزات يتبدل من الإعدادات بين المواعيد والطابور
///  (bookingSystem).» هذه الشاشة هي فرع «الطابور».
///
///  الترقية هنا خفيفة عن قصد — مرحلة أولى: تُستضاف واجهة `QueueScreen`
///  الحالية (المنقولة بالكامل ومختبَرة) داخل عمودٍ بعرضٍ مريح للكمبيوتر
///  (~760) ضمن بطاقة متمركزة، بدل حصرها بعرض الهاتف الضيّق كالهيكل المؤقت.
///  فلوحة الدور تتنفّس على الشاشة العريضة دون أي تعديل على منطقها أو
///  بياناتها أو أي سلوك هاتفي. (التصميم المكتبي الكامل للطابور — لوحة عرض
///  كبيرة/شاشة استدعاء — مرحلة تالية.)
///
///  أي دفعات صفحات داخلية تبقى محصورة في Navigator متداخل كي لا تغطي
///  الشاشة كلها (كما مضيف الهاتف المؤقت).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../queue/queue_screen.dart' show QueueScreen;

class DesktopQueueScreen extends StatelessWidget {
  const DesktopQueueScreen({super.key});

  /// عرض مريح للوحة الدور على الكمبيوتر (أوسع من عرض الهاتف الضيّق).
  static const double _comfortWidth = 760;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _comfortWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: BrandColors.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BrandColors.line),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(10, 48, 36, .06),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRect(
            child: Navigator(
              onGenerateRoute: (s) => MaterialPageRoute(
                settings: s,
                builder: (_) => Scaffold(
                  backgroundColor: BrandColors.paper,
                  body: const QueueScreen(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
