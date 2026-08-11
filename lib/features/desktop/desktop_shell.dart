/// ============================================================================
///  صدفة سطح المكتب — DesktopShell: الهيدر + الشريط الجانبي + مساحة العمل
/// ============================================================================
///
///  تُعرض بدل تخطيط الهاتف حين [isDesktopUi] (البوابة داخل AppShellScreen
///  بعد بوابة الدخول وكل مستمعي الإقلاع — فسلوكيات التشغيل واحدة للنسختين
///  حرفياً: الهجرات، المزامنة التلقائية، تذكير المواعيد، نبضة «زيارة جديدة»).
///
///  الشريط الجانبي (قرار المالك):
///  - ثابت على اليمين (أول أبناء Row في RTL)، ظاهر دائماً.
///  - Collapse/Expand بزرٍّ يُحفظ محلياً.
///  - أيقونات مع أسماء + اختصارات لوحة المفاتيح Ctrl+1..8.
///  - الترتيب الجديد: الرئيسية، السجلات، المالية، الخزينة، الديون،
///    المصروفات، إضافي، الحجوزات — الخزينة والديون رُفعتا من داخل
///    «المالية» والمصروفات من «إضافي» إلى تبويبات مباشرة بنفس صلاحيات
///    الموظفين المفصلة (financeSectionAllowed توأمها هنا).
///
///  لا Navigation دولاب هنا: تبديل التبويب يبدّل المحتوى فقط
///  (desktopTabProvider) — لا صفحات تُفتح ولا حالة تُفقد.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../records/add_record_screen.dart' show openAddRecordSheet;
import 'desktop_prefs.dart' show desktopPrefsProvider, saveDesktopPref;
import 'widgets/add_record_dock.dart'
    show
        AddRecordSidePanel,
        addRecordDockPosProvider,
        addRecordDockProvider,
        addRecordPanelWidth;
import '../settings/settings_screen.dart';
import '../shell/app_shell.dart' show LocalModeBanner;
import '../staff/staff_account_screen.dart' show StaffAccountScreen;
import '../staff/staff_gate.dart' show gateStaff;
import '../staff/staff_session.dart'
    show currentStaffProvider, staffCan, staffIsAdmin;
import '../xrays/pending_uploads_dialog.dart';
import 'desktop_prefs.dart';
import 'security/temp_cleaner.dart' show sweepEphemeral;
import 'widgets/desktop_dialogs.dart';
import 'screens/additional_desktop.dart';
import 'screens/appointments_desktop.dart';
import 'screens/debts_desktop.dart';
import 'screens/expenses_desktop.dart';
import 'screens/finance_desktop.dart';
import 'screens/home_desktop.dart';
import 'screens/queue_desktop.dart';
import 'screens/records_desktop.dart';
import 'screens/treasury_desktop.dart';

// ── التبويبات ───────────────────────────────────────────────────────────────

class DesktopTab {
  const DesktopTab(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

/// الترتيب الجديد المعتمد (قرار المالك).
const desktopTabs = <DesktopTab>[
  DesktopTab('home', 'الرئيسية', Icons.space_dashboard_rounded),
  DesktopTab('clinics', 'السجلات', Icons.folder_shared_rounded),
  DesktopTab('finance', 'المالية', Icons.account_balance_wallet_rounded),
  DesktopTab('treasury', 'الخزينة', Icons.account_balance_rounded),
  DesktopTab('debts', 'الديون', Icons.request_quote_rounded),
  DesktopTab('expenses', 'المصروفات', Icons.receipt_long_rounded),
  DesktopTab('extra', 'إضافي', Icons.widgets_rounded),
  DesktopTab('calendar', 'الحجوزات', Icons.event_note_rounded),
];

/// التبويب النشط في نسخة الكمبيوتر — مستقل عن تبويب الهاتف كي لا تتسرب
/// معرفات لا يعرفها الهاتف (treasury/debts/expenses) إلى حالته.
final desktopTabProvider = StateProvider<String>((ref) => 'home');

/// أهلية تبويبات سطح المكتب — توأم shellTabAllowed للهاتف مع تفصيل
/// financeSectionAllowed للأقسام المرفوعة (الإرث القديم «عرض المالية»
/// يفتح الخزينة والديون كما يفعل داخل تبويب المالية في الهاتف).
bool desktopTabAllowed(Map<String, Object?>? u, String id) {
  if (u == null || staffIsAdmin(u)) return true;
  final legacy = staffCan(u, 'finance.view');
  return switch (id) {
    'clinics' => staffCan(u, 'patients.view'),
    'finance' => staffCan(u, 'profits.view') ||
        staffCan(u, 'statement.view') ||
        legacy,
    'treasury' => staffCan(u, 'treasury.view') || legacy,
    'debts' =>
      staffCan(u, 'debts.pay') || staffCan(u, 'debts.manage') || legacy,
    'expenses' =>
      staffCan(u, 'expenses.add') || staffCan(u, 'expenses.delete'),
    'extra' => staffCan(u, 'labs.view') ||
        staffCan(u, 'expenses.add') ||
        staffCan(u, 'expenses.delete'),
    _ => true,
  };
}

// ── الصدفة ──────────────────────────────────────────────────────────────────

class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key});

  Future<void> _pickMonth(BuildContext context, WidgetRef ref) async {
    final current = ref.read(selectedMonthProvider);
    final parts = current.split('-');
    final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'اختر الشهر',
    );
    if (picked != null) {
      ref.read(selectedMonthProvider.notifier).state =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}';
    }
  }

  void _newVisit(BuildContext context) {
    openAddRecordSheet(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffU = ref.watch(currentStaffProvider);
    var active = ref.watch(desktopTabProvider);
    if (!desktopTabAllowed(staffU, active)) active = 'home';
    final cfg = ref.watch(appConfigProvider);
    // لوح «زيارة جديدة» الجانبي (م146) — null = مغلق. حين يُفتح يطفو فوق
    // مساحة العمل من حافة البداية (يمين RTL) بظلٍّ بلا حاجزٍ معتم.
    final dock = ref.watch(addRecordDockProvider);

    final body = switch (active) {
      'home' => const DesktopHomeScreen(),
      'clinics' => const DesktopRecordsScreen(),
      'finance' => const DesktopFinanceScreen(),
      'treasury' => const DesktopTreasuryScreen(),
      'debts' => const DesktopDebtsScreen(),
      'expenses' => const DesktopExpensesScreen(),
      'extra' => const DesktopAdditionalScreen(),
      _ => cfg['bookingSystem'] == 'queue'
          ? const DesktopQueueScreen()
          : const DesktopAppointmentsScreen(),
    };

    final visibleTabs = [
      for (final t in desktopTabs)
        if (desktopTabAllowed(staffU, t.id)) t,
    ];

    const digitKeys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    return CallbackShortcuts(
      bindings: {
        // Ctrl+1..8 — التنقل بين التبويبات الظاهرة بترتيبها.
        for (var i = 0; i < visibleTabs.length && i < digitKeys.length; i++)
          SingleActivator(digitKeys[i], control: true): () =>
              ref.read(desktopTabProvider.notifier).state =
                  visibleTabs[i].id,
        // Ctrl+N — زيارة جديدة.
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            _newVisit(context),
        // Esc — إغلاق لوح «زيارة جديدة» المرسى حين يكون مفتوحاً.
        if (dock != null)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(addRecordDockProvider.notifier).state = null,
      },
      child: FocusScope(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              // كنّاس دورة الحياة — ينظّف المؤقتات/الصادرات عند إغلاق
              // النافذة (قرار المالك §خامساً «تنظيف الموارد عند الإغلاق»).
              const _LifecycleSweeper(),
              _DesktopHeader(onPickMonth: () => _pickMonth(context, ref)),
              const LocalModeBanner(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── الشريط الجانبي — أول أبناء Row = يمين RTL ──
                    _DesktopSidebar(
                      tabs: visibleTabs,
                      active: active,
                      onNewVisit: (staffU == null ||
                              staffCan(staffU, 'records.add'))
                          ? () => _newVisit(context)
                          : null,
                    ),
                    Container(
                        width: 1,
                        color: const Color.fromRGBO(20, 80, 59, .08)),
                    // ── مساحة العمل — كامل العرض المتبقي ──
                    // م146: لوح «زيارة جديدة» الجانبي يطفو فوقها (Stack)
                    // بظلٍّ بلا حاجز — الجدول يبقى مرئياً، واللوح يرسو على
                    // حافة البداية (يمين RTL) ملاصقاً للشريط الجانبي
                    // بارتفاع مساحة العمل كاملاً.
                    Expanded(
                      // م167/ج — اللوح قابل للسحب من رأسه: موضعه الحر في
                      // مزوّدٍ (يُحفظ في تفضيلات الجهاز) بقصٍّ ذكي يمنع
                      // خروجه؛ null = المرسى الافتراضي (بداية RTL).
                      child: LayoutBuilder(builder: (ctx, cons) {
                        final panelW = addRecordPanelWidth(
                            MediaQuery.sizeOf(ctx));
                        // الموضع المحفوظ من جلسات سابقة (dock.pos = "x,y").
                        Offset? savedPos() {
                          final raw =
                              '${ref.read(desktopPrefsProvider)['dock.pos'] ?? ''}';
                          final parts = raw.split(',');
                          if (parts.length != 2) return null;
                          final x = double.tryParse(parts[0]);
                          final y = double.tryParse(parts[1]);
                          return (x == null || y == null)
                              ? null
                              : Offset(x, y);
                        }

                        final anchor = Offset(
                            cons.maxWidth - panelW - 10, 10);
                        final live = ref.watch(addRecordDockPosProvider);
                        final pos = live ?? savedPos() ?? anchor;
                        final clamped = Offset(
                          pos.dx.clamp(80.0 - panelW,
                              (cons.maxWidth - 80).clamp(0.0, 1e6)),
                          pos.dy.clamp(
                              0.0, (cons.maxHeight - 60).clamp(0.0, 1e6)),
                        );
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                color: BrandColors.paper,
                                child: body,
                              ),
                            ),
                            if (dock != null)
                              Positioned(
                                left: clamped.dx,
                                top: clamped.dy,
                                child: AddRecordSidePanel(
                                  request: dock,
                                  onDrag: (delta) => ref
                                          .read(addRecordDockPosProvider
                                              .notifier)
                                          .state =
                                      clamped + delta,
                                  onDragEnd: () {
                                    final p = ref.read(
                                            addRecordDockPosProvider) ??
                                        clamped;
                                    saveDesktopPref(
                                        ref,
                                        'dock.pos',
                                        '${p.dx.round()},${p.dy.round()}',
                                        immediate: true);
                                  },
                                ),
                              ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── الهيدر المكتبي — توأم هيدر العلامة بارتفاع مضغوط ───────────────────────

/// كنّاس المؤقتات عند إغلاق النافذة — ودجةٌ عديمة الأثر البصري تراقب دورة
/// حياة التطبيق: عند `detached`/`hidden` (إغلاق نافذة سطح المكتب برشاقة)
/// تكنس المؤقتات والصادرات. أفضل جهد؛ كنسُ الإقلاع يغطي الإغلاق المفاجئ.
class _LifecycleSweeper extends ConsumerStatefulWidget {
  const _LifecycleSweeper();

  @override
  ConsumerState<_LifecycleSweeper> createState() => _LifecycleSweeperState();
}

class _LifecycleSweeperState extends ConsumerState<_LifecycleSweeper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      final dir = ref.read(dbDirProvider);
      // لا ننتظر (النافذة تُغلق) — أفضل جهد صامت.
      sweepEphemeral(dir).catchError((_) => 0);
    } else if (state == AppLifecycleState.resumed) {
      // م-إصلاح (فورية المزامنة) — عودة تركيز النافذة تركل دورة سحب فورية
      // فيرى الطبيب تعديلات الهاتف حال التفاته للكمبيوتر بلا انتظار سحب
      // الخمول. kickPresenceSync تحترم شروط الدخول/السحابة/التلقائية
      // بنفسها فلا تعمل في الوضع المحلي.
      kickPresenceSync(ref);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DesktopHeader extends ConsumerWidget {
  const _DesktopHeader({required this.onPickMonth});
  final VoidCallback onPickMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffU = ref.watch(currentStaffProvider);
    final centerName = ref.watch(centerNameProvider);
    final month = ref.watch(selectedMonthProvider);
    final syncUi = ref.watch(syncUiProvider);
    final online = ref.watch(onlineProvider);
    final pendingX = ref.watch(pendingXrayUploadsProvider);

    return Container(
      decoration:
          const BoxDecoration(gradient: BrandColors.brandGradient),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // اسم المركز + الحالة.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BrandColors.goldLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  online ? 'متصل الآن' : 'غير متصل',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: online
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171),
                  ),
                ),
              ]),
            ],
          ),
          const Spacer(),
          if (pendingX > 0) ...[
            IconButton(
              key: const Key('desk-pending-uploads'),
              tooltip: '$pendingX صور بانتظار الرفع',
              onPressed: () => showPendingUploadsDialog(context),
              icon: Badge(
                label: Text('$pendingX',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: const Color(0xFFD97706),
                child: const Icon(Icons.cloud_upload_rounded,
                    color: Color(0xFFFBBF24), size: 20),
              ),
            ),
            const SizedBox(width: 4),
          ],
          _HdrBtn(
            tooltip: 'مزامنة',
            icon: Icons.sync_rounded,
            spinning: syncUi.syncing,
            onTap: syncUi.syncing
                ? null
                : () {
                    if (!ref.read(onlineProvider)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('الوضع غير متصل — العمل محلياً')),
                      );
                      return;
                    }
                    ref.read(syncUiProvider.notifier).manualSync();
                  },
          ),
          const SizedBox(width: 6),
          // شريحة الشهر.
          InkWell(
            key: const Key('desk-month-chip'),
            onTap: () {
              if (!gateStaff(context, 'months.nav')) return;
              onPickMonth();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color.fromRGBO(201, 162, 75, .2)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 14, color: BrandColors.goldLight),
                const SizedBox(width: 5),
                Text(
                  month,
                  style: const TextStyle(
                      color: BrandColors.goldLight,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          // شريحة الحساب/الإعدادات.
          InkWell(
            key: const Key('desk-account-chip'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final admin = staffIsAdmin(staffU) || staffU == null;
              showDesktopPanel<void>(
                context,
                title: admin ? 'الإعدادات' : 'حساب الموظف',
                builder: (_) => ClipRect(
                  child: Navigator(
                    onGenerateRoute: (s) => MaterialPageRoute(
                      settings: s,
                      builder: (_) => admin
                          ? const SettingsScreen()
                          : const StaffAccountScreen(),
                    ),
                  ),
                ),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color.fromRGBO(201, 162, 75, .2)),
              ),
              child: Row(children: [
                const Icon(Icons.settings_rounded,
                    size: 16, color: BrandColors.goldLight),
                const SizedBox(width: 6),
                Text(
                  staffU == null
                      ? 'الإعدادات'
                      : '${staffU['displayName'] ?? staffU['username'] ?? 'حساب'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: BrandColors.goldLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HdrBtn extends StatelessWidget {
  const _HdrBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.spinning = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .08),
        shape: const CircleBorder(
          side: BorderSide(color: Color.fromRGBO(201, 162, 75, .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: spinning
                ? const Center(
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BrandColors.goldLight),
                    ),
                  )
                : Icon(icon, size: 18, color: BrandColors.goldLight),
          ),
        ),
      ),
    );
  }
}

// ── الشريط الجانبي ──────────────────────────────────────────────────────────

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({
    required this.tabs,
    required this.active,
    this.onNewVisit,
  });

  final List<DesktopTab> tabs;
  final String active;
  final VoidCallback? onNewVisit;

  static const _gold = Color(0xFFC9A24B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(desktopPrefsProvider);
    final target = prefs['sidebarCollapsed'] == true;
    final w = target ? 64.0 : 212.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: w,
      color: BrandColors.surface,
      // قرار «مطوي/ممدود» من العرض **اللحظي** أثناء الحركة لا من الهدف —
      // فلا تظهر التسميات قبل اتساع المساحة (كانت تفيض أثناء التمدد).
      child: LayoutBuilder(
        builder: (context, box) => _sidebarBody(
          context,
          ref,
          collapsed: box.maxWidth < 120,
        ),
      ),
    );
  }

  Widget _sidebarBody(
    BuildContext context,
    WidgetRef ref, {
    required bool collapsed,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // زر «زيارة جديدة» الأول — CTA الذهبي الدائم.
          if (onNewVisit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              child: Tooltip(
                message: 'زيارة جديدة (Ctrl+N)',
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD9B45C), Color(0xFF9C7A2E)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      key: const Key('desk-new-visit'),
                      onTap: onNewVisit,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: collapsed ? 0 : 12, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_rounded,
                                size: 20, color: Colors.white),
                            if (!collapsed) ...[
                              const SizedBox(width: 6),
                              const Flexible(
                                child: Text(
                                  'زيارة جديدة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          // التبويبات.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _SidebarItem(
                    tab: tabs[i],
                    active: active == tabs[i].id,
                    collapsed: collapsed,
                    shortcutHint: i < 9 ? 'Ctrl+${i + 1}' : null,
                    onTap: () => ref
                        .read(desktopTabProvider.notifier)
                        .state = tabs[i].id,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: BrandColors.line),
          // زر الطي.
          InkWell(
            key: const Key('desk-sidebar-collapse'),
            onTap: () => saveDesktopPref(
                ref,
                'sidebarCollapsed',
                ref.read(desktopPrefsProvider)['sidebarCollapsed'] != true,
                immediate: true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    collapsed
                        ? Icons.keyboard_double_arrow_left_rounded
                        : Icons.keyboard_double_arrow_right_rounded,
                    size: 18,
                    color: BrandColors.mut2,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('طي الشريط',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.tab,
    required this.active,
    required this.collapsed,
    required this.onTap,
    this.shortcutHint,
  });

  final DesktopTab tab;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;
  final String? shortcutHint;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        key: Key('desk-tab-${widget.tab.id}'),
        onTap: widget.onTap,
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 0 : 10),
          decoration: BoxDecoration(
            color: active
                ? BrandColors.brand.withValues(alpha: .08)
                : _hover
                    ? BrandColors.brand.withValues(alpha: .04)
                    : null,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border(
                    right: BorderSide(
                        color: _DesktopSidebar._gold, width: 3))
                : null,
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Container(
                decoration: active
                    ? const BoxDecoration(boxShadow: [
                        BoxShadow(
                            color: Color.fromRGBO(201, 162, 75, .4),
                            blurRadius: 8),
                      ])
                    : null,
                child: Icon(
                  widget.tab.icon,
                  size: 21,
                  color: active
                      ? _DesktopSidebar._gold
                      : const Color.fromRGBO(15, 42, 32, .55),
                ),
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? const Color(0xFF1B5E47)
                          : BrandColors.mut,
                    ),
                  ),
                ),
                if (_hover && widget.shortcutHint != null)
                  Text(
                    widget.shortcutHint!,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 9.5, color: BrandColors.faint),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    return widget.collapsed
        ? Tooltip(
            message:
                '${widget.tab.label}${widget.shortcutHint == null ? '' : '  (${widget.shortcutHint})'}',
            child: item,
          )
        : item;
  }
}
