/// تبويب «إضافي» — قائمة الأدوات الإضافية للتطبيق.
///
/// القرار البنيوي (طلب المالك): كل عنصر يفتح **شاشته المستقلة** عبر
/// Navigator.push بدل بنائه داخل الصدفة. الفائدة سرعةُ الصدفة: محتوى
/// المختبر/المصروفات — وهي شاشات ثقيلة تقرأ القاعدة وتحسب مجاميع — لا
/// يُبنى إطلاقاً حتى يدخلها المستخدم فعلاً، فيبقى تبديل التبويب فورياً.
///
/// نُقل «المختبر» هنا من تبويب سفلي مستقل (كان الرابع في الشريط) إلى أول
/// عناصر هذه القائمة: [LabScreen] يغلّف [LabsTab] القائم حرفياً بلا أي
/// تغيير في منطقه. «المصروفات» تُضاف عنصراً ثانياً في الدفعة التالية.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../expenses/expenses_screen.dart';
import '../labs/labs_tab.dart';
import '../staff/staff_session.dart' show kCurrentStaff, staffCan, staffIsAdmin;

/// وصف عنصر واحد في قائمة «إضافي».
class _ExtraItem {
  const _ExtraItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
    this.keyId,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  final String? keyId;
}

class AdditionalTab extends StatelessWidget {
  const AdditionalTab({super.key});

  static const _items = <_ExtraItem>[
    _ExtraItem(
      keyId: 'extra-labs',
      title: 'المختبر',
      subtitle: 'المختبرات والتركيبات وحالاتها المالية',
      icon: Icons.biotech_rounded,
      builder: _buildLabScreen,
    ),
    _ExtraItem(
      keyId: 'extra-expenses',
      title: 'المصروفات',
      subtitle: 'الرواتب ومواد التنظيف والمواد السنية ومصروفات أخرى',
      icon: Icons.account_balance_wallet_rounded,
      builder: _buildExpensesScreen,
    ),
  ];

  /// م119 — أهلية العنصر لصلاحيات الجلسة (الإدارة ترى الكل).
  static bool _itemAllowed(_ExtraItem it) {
    final u = kCurrentStaff;
    if (u == null || staffIsAdmin(u)) return true;
    return switch (it.keyId) {
      'extra-labs' => staffCan(u, 'labs.view'),
      'extra-expenses' =>
        staffCan(u, 'expenses.add') || staffCan(u, 'expenses.delete'),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, right: 4),
          child: Text(
            'أدوات إضافية',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: BrandColors.brandText,
            ),
          ),
        ),
        for (final it in _items)
          if (_itemAllowed(it))
          _ExtraCard(
            item: it,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: it.builder),
            ),
          ),
      ],
    );
  }
}

/// باني شاشة المختبر (دالة عليا كي يبقى [AdditionalTab._items] ثابتاً const).
Widget _buildLabScreen(BuildContext context) => const LabScreen();

/// باني شاشة المصروفات (دالة عليا كي يبقى [AdditionalTab._items] ثابتاً const).
Widget _buildExpensesScreen(BuildContext context) => const ExpensesScreen();

class _ExtraCard extends StatelessWidget {
  const _ExtraCard({required this.item, required this.onTap});

  final _ExtraItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: item.keyId != null ? Key(item.keyId!) : null,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(201, 162, 75, .12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color.fromRGBO(201, 162, 75, .28)),
                ),
                child: Icon(item.icon,
                    color: BrandColors.goldDark, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(fontSize: 11.5, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
              // RTL: السهم لليسار يدل على «فتح/دخول».
              const Icon(Icons.chevron_left_rounded, color: BrandColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة المختبر المستقلة — تغلّف [LabsTab] القائم بهيكل صفحة: شريط علوي
/// بالعنوان وزر رجوع، وخلفية الورق نفسها، والحد الأقصى 640 كما في الصدفة،
/// كي يُفتح كصفحة مدفوعة من قائمة «إضافي». منطق المختبر نفسه دون تغيير.
class LabScreen extends StatelessWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('المختبرات'),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const LabsTab(),
        ),
      ),
    );
  }
}
