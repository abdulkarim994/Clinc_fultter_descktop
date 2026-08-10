/// ============================================================================
///  إضافي — نسخة سطح المكتب: بطاقات أدوات أنيقة + شاشة التركيبات داخل التبويب
/// ============================================================================
///
///  (قرار المالك):
///  - بطاقة «المختبر» تعرض شاشة التركيبات المنقسمة [DesktopLabsScreen]
///    داخل نفس التبويب مع زر رجوع لقائمة الأدوات.
///  - بطاقة «المصروفات» ظاهرة بوسم «انتقلت لتبويب مستقل» — نقرها يحوّل
///    التبويب النشط إلى 'expenses' عبر [desktopTabProvider].
///  - الصلاحيات من [additional_tab.dart]: labs.view + expenses.add/delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../staff/staff_session.dart' show kCurrentStaff, staffCan, staffIsAdmin;
import '../desktop_shell.dart' show desktopTabProvider;
import '../../labs/lab_logo.dart';
import 'labs_desktop.dart';

/// حالة عرض شاشة التركيبات داخل التبويب.
enum _ExtraView { tools, labs }

class DesktopAdditionalScreen extends ConsumerStatefulWidget {
  const DesktopAdditionalScreen({super.key});

  @override
  ConsumerState<DesktopAdditionalScreen> createState() =>
      _DesktopAdditionalScreenState();
}

class _DesktopAdditionalScreenState
    extends ConsumerState<DesktopAdditionalScreen> {
  _ExtraView _view = _ExtraView.tools;

  bool get _labAllowed {
    final u = kCurrentStaff;
    if (u == null || staffIsAdmin(u)) return true;
    return staffCan(u, 'labs.view');
  }

  bool get _expensesAllowed {
    final u = kCurrentStaff;
    if (u == null || staffIsAdmin(u)) return true;
    return staffCan(u, 'expenses.add') || staffCan(u, 'expenses.delete');
  }

  @override
  Widget build(BuildContext context) {
    // عرض شاشة التركيبات المنقسمة داخل التبويب مع زر رجوع.
    if (_view == _ExtraView.labs) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط الرجوع.
          Container(
            color: BrandColors.surface,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(children: [
              Material(
                color: BrandColors.brand600.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: const Key('extra-labs-back'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _view = _ExtraView.tools),
                  child: SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.arrow_back_rounded,
                        size: 18, color: BrandColors.brandIcon),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('المختبر — التركيبات',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
            ]),
          ),
          Divider(height: 1, color: BrandColors.line),
          // شاشة التركيبات المنقسمة.
          const Expanded(child: DesktopLabsScreen()),
        ],
      );
    }

    // عرض قائمة الأدوات.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'أدوات إضافية',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: BrandColors.brandText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر أداةً لفتحها',
            style: TextStyle(fontSize: 12, color: BrandColors.mut),
          ),
          const SizedBox(height: 20),

          // بطاقة المختبر.
          if (_labAllowed)
            _ToolCard(
              key: const Key('extra-labs'),
              isLab: true,
              icon: Icons.biotech_rounded,
              iconColor: BrandColors.brand700,
              iconBg: BrandColors.brand600.withValues(alpha: .1),
              title: 'المختبر',
              subtitle: 'التركيبات وحالاتها المالية لكل مختبر',
              onTap: () => setState(() => _view = _ExtraView.labs),
            ),

          if (_labAllowed) const SizedBox(height: 12),

          // بطاقة المصروفات (انتقلت لتبويب مستقل).
          if (_expensesAllowed)
            _ToolCard(
              key: const Key('extra-expenses'),
              icon: Icons.account_balance_wallet_rounded,
              iconColor: BrandColors.goldDark,
              iconBg: BrandColors.gold.withValues(alpha: .1),
              title: 'المصروفات',
              subtitle: 'الرواتب والمواد والمصروفات الشهرية',
              badge: 'انتقلت لتبويب مستقل',
              badgeColor: BrandColors.brand600,
              actionIcon: Icons.open_in_new_rounded,
              onTap: () {
                // تحويل التبويب النشط إلى المصروفات عبر desktopTabProvider.
                ref.read(desktopTabProvider.notifier).state = 'expenses';
              },
            ),
        ],
      ),
    );
  }
}

// ── بطاقة أداة ───────────────────────────────────────────────────────────────

class _ToolCard extends StatefulWidget {
  const _ToolCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
    this.actionIcon,
    this.isLab = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;
  final IconData? actionIcon;
  final bool isLab;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _hovered ? BrandColors.surface2 : BrandColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? BrandColors.brand600.withValues(alpha: .25)
                : BrandColors.line,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: BrandColors.brand.withValues(alpha: .06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              // أيقونة الأداة.
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: widget.iconColor.withValues(alpha: .2)),
                ),
                child: widget.isLab
                    ? LabLogo(size: 26, color: widget.iconColor)
                    : Icon(widget.icon, color: widget.iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // العنوان + شارة «انتقلت».
                    Row(children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText,
                        ),
                      ),
                      if (widget.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (widget.badgeColor ?? BrandColors.brand600)
                                .withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: (widget.badgeColor ??
                                        BrandColors.brand600)
                                    .withValues(alpha: .3)),
                          ),
                          child: Text(
                            widget.badge!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: widget.badgeColor ??
                                  BrandColors.brand600,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                          fontSize: 12, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.actionIcon ?? Icons.chevron_left_rounded,
                size: 20,
                color: BrandColors.gold,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
