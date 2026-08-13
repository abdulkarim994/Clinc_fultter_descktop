/// ============================================================================
///  الطابور (نظام الدور) — نسخة سطح المكتب
/// ============================================================================
///
///  (قرار المالك): «نظام الحجوزات يتبدل من الإعدادات بين المواعيد والطابور
///  (bookingSystem).» هذه الشاشة هي فرع «الطابور».
///
///  م177 — التصميم المكتبي: عيادةٌ غير مفتوحة ⇒ شاشة الاختيار (المستضافة)
///  بعمود مريح؛ وعيادةٌ مفتوحة ⇒ لوحة الدور الكاملة **مضمّنةً** بعرضٍ
///  رحب (~1100): الترويسة نفسها (رجوع يميناً/العيادة وسطاً/صف التاريخ
///  بسهمين/التبويبات المنزلقة)، والجسم يتفرع تلقائياً للتخطيط العريض
///  (اللوحة الجانبية يميناً والقائمة يساراً) — والإضافة بحوارٍ متمركز
///  بنفس نموذج الورقة وسلسلة Enter. البيانات والمزامنة (م56) بلا مساس.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../queue/queue_screen.dart'
    show QueueBoardScreen, QueueScreen, queueViewProvider;

class DesktopQueueScreen extends ConsumerWidget {
  const DesktopQueueScreen({super.key});

  /// عرض شاشة الاختيار المريح، وعرض اللوحة الرحب (م177).
  static const double _selectWidth = 760;
  static const double _boardWidth = 1100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardOpen = ref.watch(queueViewProvider).clinic != null;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: boardOpen ? _boardWidth : _selectWidth),
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
          // م177 — اللوحة مضمّنة (زر رجوعها يعيد للاختيار لا لمسار)،
          // وشاشة الاختيار داخل Navigator متداخل كي تبقى أي دفعات
          // داخلية محصورةً في البطاقة.
          child: boardOpen
              ? const QueueBoardScreen(embedded: true)
              : ClipRect(
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
