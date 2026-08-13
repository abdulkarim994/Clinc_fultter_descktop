/// تبويب المالية — محور FinanceTab.vue بأقسامه الثلاثة الحقيقية:
/// الخزينة (بطاقات العيادات والتفصيل بالفئة) والديون (القائمة الكاملة
/// بإجراءاتها) والأرباح (شهرية بالعيادة وسنوية) — مع شارة عدد الديون
/// المفتوحة على زر القسم، وإعادة القسم إلى الخزينة عند مغادرة التبويب ما
/// لم يفعّل keepTabState (نفس onDeactivated في الأصل).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../shell/app_shell.dart' show activeTabProvider;
import 'debts_section.dart';
import 'profits_section.dart';
import 'treasury_section.dart';
import '../staff/staff_session.dart'
    show kCurrentStaff, staffCan, staffIsAdmin;

typedef JMap = Map<String, Object?>;

/// نبضة إعادة قراءة بعد كتابات مالية.
final financeRevProvider = StateProvider<int>((ref) => 0);

/// م108 — طلب فتح قسمٍ مالي: القيمة الافتراضية menu (قائمة البطاقات).
/// أي كتابة بقيمة قسم (treasury/debts/profits/statement) من أي مكان في
/// التطبيق تدفع شاشة القسم فوراً ثم تعود القيمة إلى menu — فتبقى روابط
/// «فتح الديون» القديمة تعمل كما هي.
final financeSectionProvider = StateProvider<String>((ref) => 'menu');

// م125 — ميزة شارة عدد الديون أُلغيت نهائياً (قرار المالك):
// حُذف مزوّد العدّ والشارة ومفتاح الإعدادات معاً.

/// م108 — بيانات بطاقة قسمٍ مالي (بأسلوب بطاقات «أدوات إضافية»).
class _FinItem {
  const _FinItem(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _finItems = <_FinItem>[
  _FinItem('treasury', 'الخزينة',
      'الكاش والتحويل والتركيبات وصافي الشهر بعد المصروفات',
      Icons.account_balance_rounded),
  _FinItem('debts', 'الديون',
      'الديون المفتوحة وسدادها وأقساطها',
      Icons.receipt_long_rounded),
  // م178 — الأرباح ثلاثة أقسام (شهرية/سنوية/كشف حساب) وبطاقة الكشف
  // تفتح القسم الثالث نفسه (سلامة روابط م108 وصلاحيات الموظفين).
  _FinItem('profits', 'الأرباح',
      'جداول الأرباح الشهرية والسنوية وكشف الحساب',
      Icons.trending_up_rounded),
  _FinItem('statement', 'كشف الحساب',
      'كشف مالي بمدى تاريخي وفلاتر وطباعة',
      Icons.summarize_rounded),
];

/// م119 — أهلية القسم المالي لصلاحيات الجلسة: الديون بصلاحيتَي الديون
/// (أو عرض المالية)، وبقية الأقسام بصلاحية عرض المالية. الإدارة الكل.
bool financeSectionAllowed(String id) {
  final u = kCurrentStaff;
  if (u == null || staffIsAdmin(u)) return true;
  // م122 — إرث: حسابات مُنحت «عرض المالية» القديمة قبل التفصيل تبقى ترى
  // كل الأقسام حتى تعيد الإدارة ضبطها بالصلاحيات المفصلة.
  final legacy = staffCan(u, 'finance.view');
  return switch (id) {
    'debts' => staffCan(u, 'debts.pay') ||
        staffCan(u, 'debts.manage') ||
        legacy,
    'treasury' => staffCan(u, 'treasury.view') || legacy,
    'profits' => staffCan(u, 'profits.view') || legacy,
    'statement' => staffCan(u, 'statement.view') || legacy,
    _ => legacy,
  };
}

/// م108 — شاشة قسمٍ مالي مدفوعة بترويسة رجوع (توأم شاشات «إضافي»).
/// م173 — زر رجوع النظام منها يعود **للرئيسية** مباشرةً (قرار المالك):
/// بعد انغلاق الشاشة يُضبط تبويب الصدفة على الرئيسية — تسلسلٌ متوقع
/// (الخزينة ⇒ رجوع ⇒ الرئيسية) بدل التقطع بين القوائم.
class FinanceSectionScreen extends ConsumerWidget {
  const FinanceSectionScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = _finItems.firstWhere((e) => e.id == id,
        orElse: () => _finItems.first);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.read(activeTabProvider.notifier).state = 'home';
        }
      },
      child: Scaffold(
        backgroundColor: BrandColors.paper,
        appBar: AppBar(
          title: Text(item.title),
          backgroundColor: BrandColors.brand,
          foregroundColor: BrandColors.goldLight,
        ),
        body: switch (id) {
          'debts' => const DebtsSection(),
          'profits' => const ProfitsSection(),
          // م178 — الكشف صار القسم الثالث في الأرباح؛ بطاقته وروابط
          // م108 القديمة تفتحه على حبته مباشرة.
          'statement' => const ProfitsSection(initialView: 'statement'),
          _ => const TreasurySection(),
        },
      ),
    );
  }
}

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FinanceSectionScreen(id: id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // م108 — روابط «فتح قسمٍ مالي» من بقية التطبيق (خلية الديون في
    // الخزينة، قفزات الصدفة...): كتابة القسم تدفع شاشته ثم تعود القيمة
    // إلى menu.
    ref.listen(financeSectionProvider, (prev, next) {
      if (next == 'menu' || next.isEmpty) return;
      ref.read(financeSectionProvider.notifier).state = 'menu';
      if (!financeSectionAllowed(next)) return; // م119
      _open(context, next);
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, right: 4),
          child: Text(
            'المالية',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: BrandColors.brandText,
            ),
          ),
        ),
        for (final it in _finItems)
          if (financeSectionAllowed(it.id))
          _FinCard(
            item: it,
            onTap: () => _open(context, it.id),
          ),
      ],
    );
  }
}

/// بطاقة قسمٍ مالي — التوأم البصري لبطاقات «أدوات إضافية» حرفياً.
class _FinCard extends StatelessWidget {
  const _FinCard(
      {required this.item, required this.onTap});

  final _FinItem item;
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
        key: Key('fin-seg-${item.id}'),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                    Row(children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  color: BrandColors.mut, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// إجمالي متبقي الديون المفتوحة (لبطاقة الشارة في الصدفة إن لزم).
num openDebtsRemaining(WidgetRef ref) {
  ref.watch(financeRevProvider);
  return ref
      .watch(reposProvider)
      .debts
      .getAll()
      .where((d) => d['status'] != 'paid')
      .fold<num>(0, (s, d) => s + jsNumOr0(d['remaining']));
}

/// v52 — شارة عدد الديون: دائرة حمراء الرقم في مركزها تماماً، تحيط بها
/// هالة حمراء ضبابية صغيرة تنبض بخفة شديدة (متحكم واحد بطيء 1.8 ثانية
/// ذهاباً وإياباً). النبض يُعطَّل في بيئة الاختبارات (نمط الدائرة
/// العائمة م59) كي لا تعلق pumpAndSettle.
class PulseCountBadge extends StatefulWidget {
  const PulseCountBadge({super.key, required this.count});

  final int count;

  @override
  State<PulseCountBadge> createState() => PulseCountBadgeState();
}

class PulseCountBadgeState extends State<PulseCountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTest) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          // م109 — 22 بدل 20: تنفس للرقمين مع توسيط هندسي تام.
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444)
                    .withValues(alpha: .22 + .18 * t),
                blurRadius: 4 + 3 * t,
                spreadRadius: .5 + 1.3 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      // v53 — تمركز الرقم في قلب الدائرة: خط القاهرة يميل برفع الأرقام
      // عن مركز السطر، فيوزَّع ارتفاع السطر بالتساوي (even) حول الحرف.
      // م109 — توسيط الرقم في قلب الدائرة تماماً: إلغاء تطبيق ارتفاع
      // السطر على أول صاعد وآخر نازل يزيل انحياز خط القاهرة نهائياً،
      // فيتطابق مركز صندوق الحرف مع مركز الدائرة (مُقاس باختبار هندسي).
      child: Text('${widget.count}',
          textAlign: TextAlign.center,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
          style: const TextStyle(
              fontSize: 10.5,
              height: 1.0,
              leadingDistribution: TextLeadingDistribution.even,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
              color: Colors.white)),
    );
  }
}
