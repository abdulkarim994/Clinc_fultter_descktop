/// الصدفة الرئيسية — نقل بنيوي لـ pages/AppShell.vue:
/// هيدر العلامة (اسم المركز + حالة الاتصال + الشهر + مزامنة + إعدادات)
/// وشريط التبويبات الخمسة: الرئيسية/السجلات/المالية/إضافي/الحجوزات.
/// «إضافي» (رمز زائد) قائمةٌ تفتح كل أداة كشاشة مستقلة — والمختبر أول
/// عناصرها بعد نقله من تبويب سفلي مستقل (انظر additional_tab.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/display_prefs.dart' show applyDisplayPrefs;
import '../../core/theme/app_theme.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/desktop_shell.dart' show DesktopShell;
import '../finance/debts_section.dart' show debtsClinicFilterProvider;
import 'tab_icons.dart';
import '../finance/finance_screen.dart'
    show FinanceScreen, financeSectionProvider;
import '../additional/additional_tab.dart';
import '../patients/patients_tab.dart'
    show PatientsTab, homeJumpProvider, openClinicProvider;
import '../appointments/appointments_logic.dart' show to12h;
import '../appointments/appt_lifecycle.dart' show bookingSystemOf;
import '../appointments/appointments_tab.dart';
import '../../core/widgets/shiny_fab.dart' show ShinyFab;
import '../patients/clinic_scope.dart' show migrateMedicalKeys;
import '../records/add_record_screen.dart' show openAddRecordSheet;
import '../staff/staff_login_screen.dart' show StaffLoginScreen;
import '../staff/staff_account_screen.dart' show StaffAccountScreen;
import '../staff/staff_session.dart'
    show currentStaffProvider, staffCan, staffIsAdmin;
import '../staff/staff_store.dart' show StaffStore;
import '../staff/staff_gate.dart' show gateStaff;
import '../records/daily_income_screen.dart';
import '../settings/settings_screen.dart';
import '../queue/queue_add_sheet.dart' show showQueueAddSheet;
import '../queue/queue_screen.dart';
import '../xrays/pending_uploads_dialog.dart';
import '../../core/utils/js_compat.dart';

class ShellTab {
  const ShellTab(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const shellTabs = [
  ShellTab('home', 'الرئيسية', Icons.add_box_rounded),
  ShellTab('clinics', 'السجلات', Icons.folder_shared_rounded),
  ShellTab('finance', 'المالية', Icons.account_balance_wallet_rounded),
  ShellTab('extra', 'إضافي', Icons.add_circle_outline_rounded),
  ShellTab('calendar', 'الحجوزات', Icons.event_note_rounded),
];

/// م119 — أهلية التبويب لصلاحيات الجلسة الحالية (الإدارة ترى الكل):
/// «السجلات» تتطلب عرض ملفات المرضى، «المالية» أي صلاحية ماليةٍ أو
/// ديون، و«إضافي» المختبرَ أو المصروفات. الرئيسية والحجوزات للجميع.
bool shellTabAllowed(Map<String, Object?>? u, String id) {
  if (u == null || staffIsAdmin(u)) return true;
  return switch (id) {
    'clinics' => staffCan(u, 'patients.view'),
    // م122 — يكفي أي قسم مالي واحد لإظهار التبويب (كلٌّ بصلاحيته).
    'finance' => staffCan(u, 'finance.view') ||
        staffCan(u, 'treasury.view') ||
        staffCan(u, 'profits.view') ||
        staffCan(u, 'statement.view') ||
        staffCan(u, 'debts.pay') ||
        staffCan(u, 'debts.manage'),
    'extra' => staffCan(u, 'labs.view') ||
        staffCan(u, 'expenses.add') ||
        staffCan(u, 'expenses.delete'),
    _ => true,
  };
}

/// م36 — «الرئيسية» هي التبويب الافتراضي دائماً (فتح التطبيق وكل دخول)
/// — توأم بوابة Vue التي تنتهي إلى home (كان الافتراضي «السجلات» خطأً).
final activeTabProvider = StateProvider<String>((ref) => 'home');

/// م96 — هجرة مفاتيح المعلومات الطبية مرة لكل إقلاع (عديمة الأثر عند
/// اكتمالها): المدخل العاري بالاسم ← مفتاح عيادة أحدث نشاط لذلك الاسم،
/// و«اسم|عيادة» ← مفتاح هاتف صف المريض. التفاصيل في clinic_scope.dart —
/// عزل المالك: ممنوع تشارك المعلومات الطبية بين مشابهي الاسم.
bool _medicalMigrationRan = false;

void _maybeMigrateMedicalKeys(WidgetRef ref) {
  if (_medicalMigrationRan) return;
  _medicalMigrationRan = true;
  try {
    final repos = ref.read(reposProvider);
    final cfg = ref.read(appConfigProvider);
    final medical = cfg['patientMedical'];
    final plans = cfg['treatmentPlans'];
    // فحص رخيص: لا مسح للجداول إلا عند وجود مفاتيح بحاجة هجرة.
    final medNeeds = medical is Map &&
        medical.keys.any((k) => '$k'.split('|').length <= 2);
    // م97 — كتلة الخطة القديمة: العاري بالاسم فقط (بلا ترقية هاتف للكتلة).
    final planNeeds =
        plans is Map && plans.keys.any((k) => !'$k'.contains('|'));
    if (!medNeeds && !planNeeds) return;

    // أحدث عيادة نشاط لكل اسم (سجلات + تركيبات + ديون).
    final latest = <String, (num, String)>{};
    void scan(List rows) {
      for (final r in rows.cast<Map<String, Object?>>()) {
        final nm = '${r['name'] ?? r['patient_name'] ?? ''}'.trim();
        final cl = '${r['clinic'] ?? ''}'.trim();
        if (nm.isEmpty || cl.isEmpty) continue;
        final t = jsNumOr0(
            jsOr(r['_activityAt'], jsOr(r['_mod'], r['createdAt'])));
        final cur = latest[nm];
        if (cur == null || t >= cur.$1) latest[nm] = (t, cl);
      }
    }

    scan(repos.records.getAll());
    scan(repos.prosthetics.getAll());
    scan(repos.debts.getAll());

    String rowPhoneOf(String nm) {
      final p = '${repos.patients.getById(nm)?['phone'] ?? ''}';
      return p == 'null' ? '' : p;
    }

    String? latestClinicOf(String nm) => latest[nm]?.$2;

    final migratedMed = medNeeds
        ? migrateMedicalKeys(medical,
            latestClinicOf: latestClinicOf, rowPhoneOf: rowPhoneOf)
        : null;
    // م97 — خطة العلاج: هجرة الكتلة بالعيادة فقط؛ ترقية الهاتف لصفوف
    // المخزن تجري عند القراءة في TreatmentPlanStore.
    final migratedPlans = planNeeds
        ? migrateMedicalKeys(plans,
            latestClinicOf: latestClinicOf,
            rowPhoneOf: rowPhoneOf,
            upgradePhones: false)
        : null;
    if (migratedMed == null && migratedPlans == null) return;
    final cur = Map<String, Object?>.from(cfg);
    repos.settings.set('app.config', {
      ...cur,
      'patientMedical': ?migratedMed,
      'treatmentPlans': ?migratedPlans,
    });
    ref.read(configRevProvider.notifier).state++;
  } catch (_) {
    // الهجرة تحسينية — فشلها لا يوقف الإقلاع وتُعاد بالإقلاع التالي.
    _medicalMigrationRan = false;
  }
}

class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({super.key});

  Future<void> _pickMonth(BuildContext context, WidgetRef ref) async {
    final current = ref.read(selectedMonthProvider);
    final parts = current.split('-');
    final initial =
        DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ═══ بوابة الدخول — نظام الموظفين **اختياري** (قرار المالك) ═══
    // الوضع الفردي (طبيبٌ وحده): ما دام لا حساب موظفٍ واحد على الأقل،
    // لا شاشة دخول ولا كلمة مرور — يفتح التطبيق مباشرةً بصلاحياتٍ كاملة
    // (staffAllowed(null) ⇒ سماحٌ كامل). تفعيل النظام اختيارٌ من الإعدادات.
    // وحين يوجد حسابٌ فأكثر: تسجيل الدخول مطلوبٌ كالسابق تماماً.
    final staffConfigured =
        StaffStore(ref.watch(reposProvider).settings).hasAnyUser;
    if (staffConfigured && ref.watch(currentStaffProvider) == null) {
      return const StaffLoginScreen();
    }
    // نبضة «زيارة جديدة» من قائمة مرضى العيادة ⇒ الانتقال للرئيسية.
    ref.listen(homeJumpProvider, (prev, next) {
      // مسار «إضافة زيارة» صار يفتح نموذج الإدخال كورقة سفلية بدل تبويب.
      if (!gateStaff(context, 'records.add')) return;
      openAddRecordSheet(context);
    });
    final staffU = ref.watch(currentStaffProvider);
    var active = ref.watch(activeTabProvider);
    // م119 — تبويبٌ محجوب عن هذه الجلسة (بقي من جلسة إدارةٍ سابقة على
    // نفس الجهاز)؟ يُرجَع للرئيسية.
    if (!shellTabAllowed(staffU, active)) active = 'home';
    final cfg = ref.watch(appConfigProvider);
    // م116 — تفضيلات العرض العامة (الأرقام/الوقت/فاصل الفترة) تُضبط
    // من الإعدادات لكل المنسقات المركزية.
    applyDisplayPrefs(cfg);
    // م179 (قرار المالك): شريط التبويبات **أسفل افتراضياً** — الغياب
    // يعني أسفل، ولا يصعد إلا باختيارٍ صريح 'top' من الإعدادات.
    final tabBottom = cfg['tabBarPosition'] != 'top';
    // تفعيل/إيقاف المزامنة التلقائية بعد الإطار (خارج البناء — آمن).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => applyAutoSync(ref));
    // م96 — هجرة مفاتيح المعلومات الطبية (مرة لكل إقلاع، خارج البناء).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeMigrateMedicalKeys(ref));
    // تذكير مواعيد اليوم والغد عند فتح التطبيق — showApptNotification.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowApptNotif(context, ref));

    // ═══ بوابة نسخة الكمبيوتر (Desktop UI) ═══
    // بعد بوابة الدخول وكل مستمعي الإقلاع أعلاه (فهي مشتركة للنسختين
    // حرفياً: الهجرات، المزامنة، تذكير المواعيد، نبضة «زيارة جديدة»).
    // منصة سطح مكتب + عرض ≥ الحد ⇒ تخطيط DesktopShell؛ ودون الحد يستمر
    // تخطيط الهاتف أدناه **دون أي تغيير** — انظر desktop_gate.dart.
    if (isDesktopUi(context)) return const DesktopShell();

    final centerName = ref.watch(centerNameProvider);
    final month = ref.watch(selectedMonthProvider);
    final syncUi = ref.watch(syncUiProvider);
    // م25 — الحالة الحية من خدمة الشبكة الموحدة (وصلة + وصول مؤكد):
    // «متصل الآن/غير متصل» يتبدل فعلاً مع الشبكة (كان مثبتاً متصلاً).
    final online = ref.watch(onlineProvider);
    // م26 — عدد الصور بانتظار الرفع (أيقونة بجانب زر المزامنة).
    final pendingX = ref.watch(pendingXrayUploadsProvider);

    final body = switch (active) {
      'home' => const DailyIncomeScreen(),
      'clinics' => const PatientsTab(),
      'finance' => const FinanceScreen(),
      'extra' => const AdditionalTab(),
      // بوابة الحجوزات — توأم BookingsTab: التبديل حيّ من الإعدادات
      // بلا إعادة تحميل، وكلا النظامين يحتفظ ببياناته.
      // م164 — bookingSystemOf: المصدرُ الوحيد لقراءة نوع الحجز.
      _ => bookingSystemOf(cfg) == 'queue'
          ? const QueueScreen()
          : const AppointmentsTab(),
    };
    final tabBar = _ShellTabBar(bottom: tabBottom);

    // م173 — زر رجوع النظام (قرار المالك): تسلسلٌ هرمي متوقع —
    //   • داخل عيادةٍ في السجلات ⇒ رجوعٌ لبوابة العيادات أولاً.
    //   • أي تبويبٍ غير الرئيسية ⇒ رجوعٌ للرئيسية.
    //   • الرئيسية ⇒ خروجٌ طبيعي من التطبيق.
    // «داخل عيادة» تُراقب كي يعاد البناء فيتحدث canPop معها.
    final inClinic =
        active == 'clinics' && ref.watch(openClinicProvider) != null;
    return PopScope(
      canPop: active == 'home' && !inClinic,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ref.read(activeTabProvider) == 'clinics' &&
            ref.read(openClinicProvider) != null) {
          ref.read(openClinicProvider.notifier).state = null;
          return;
        }
        ref.read(activeTabProvider.notifier).state = 'home';
      },
      child: Scaffold(
      body: Column(
        children: [
          // ── هيدر العلامة — توأم .brand-header حرفياً: تدرج 160deg مع
          // نقش معيّنات ذهبي بشفافية 6% (brand-header-pattern)، أزرار
          // دائرية 44px بخلفية بيضاء 8% وحد ذهبي 20% وأيقونات ذهبية
          // فاتحة (brand-hdr-btn)، وشريحة شهر بنص ذهبي (brand-hdr-inp).
          Container(
            decoration:
                const BoxDecoration(gradient: BrandColors.brandGradient),
            child: CustomPaint(
              painter: const _HeaderPatternPainter(),
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 12,
                  bottom: 12,
                  left: 16,
                  right: 16,
                ),
                child: Row(
              children: [
                // م124 — ترس واحد للجميع (ترتيب الهيدر — قرار المالك):
                // الإدارة ⇒ الإعدادات الكاملة (وبأعلاها بطاقة الحساب)،
                // وغيرها ⇒ شاشة «حساب الموظف» المصغرة فقط — فيبقى
                // قرار حجب الإعدادات عن الموظف قائماً.
                _HdrCircleBtn(
                  tooltip: staffIsAdmin(staffU) || staffU == null
                      ? 'الإعدادات'
                      : 'حساب الموظف',
                  icon: Icons.settings_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            staffIsAdmin(staffU) || staffU == null
                                ? const SettingsScreen()
                                : const StaffAccountScreen()),
                  ),
                ),
                const SizedBox(width: 8),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        centerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BrandColors.goldLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5, // text-sm (14px) ÷ معايرة 1.12
                        ),
                      ),
                      // م41 — تقليص رشيق عند تكبير الخط بدل الفيضان.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                        children: [
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
                              fontSize: 9, // ٨px كالأصل (÷ المعايرة)
                              color: online
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFFF87171),
                            ),
                          ),
                        ],
                        ),
                      ),
                    ],
                  ),
                ),
                // م26 — أيقونة الصور المعلقة بجانب زر المزامنة (توأم زر
                // AppShell في الأصل: تظهر فقط عند وجود معلقات، بشارة
                // العدد، وتفتح نافذة «صور بانتظار الرفع»).
                if (pendingX > 0)
                  IconButton(
                    key: const Key('pending-uploads-icon'),
                    tooltip: '$pendingX صور بانتظار الرفع',
                    onPressed: () => showPendingUploadsDialog(context),
                    icon: Badge(
                      label: Text('$pendingX',
                          style: const TextStyle(fontSize: 11.5)),
                      backgroundColor: const Color(0xFFD97706),
                      child: const Icon(Icons.cloud_upload_rounded,
                          color: Color(0xFFFBBF24)),
                    ),
                  ),
                _HdrCircleBtn(
                  tooltip: 'مزامنة',
                  icon: Icons.sync_rounded,
                  spinning: syncUi.syncing,
                  onTap: syncUi.syncing
                      ? null
                      : () {
                          // م25 — توأم الأصل: أوفلاين لا دورة، رسالة
                          // «الوضع غير متصل — العمل محلياً».
                          if (!ref.read(onlineProvider)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'الوضع غير متصل — العمل محلياً')),
                            );
                            return;
                          }
                          ref
                              .read(syncUiProvider.notifier)
                              .manualSync();
                        },
                ),
                const SizedBox(width: 6),
                // شريحة الشهر — brand-hdr-inp: خلفية بيضاء 8%، حد ذهبي
                // 20%، نص ذهبي فاتح، قطر 12.
                InkWell(
                  // م121 — التنقل بين الأشهر السابقة صلاحية مستقلة
                  // (الموظف يعمل بشهره الحالي فقط).
                  onTap: () {
                    if (!gateStaff(context, 'months.nav')) return;
                    _pickMonth(context, ref);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color.fromRGBO(201, 162, 75, .2)),
                    ),
                    child: Text(
                      month,
                      style: const TextStyle(
                          color: BrandColors.goldLight,
                          fontSize: 12.5, // 14px ÷ المعايرة
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
                ),
              ),
            ),
          ),

          // م78 — شريط «الوضع المحلي». يظهر فقط حين لا يوجد إعداد سحابي.
          const LocalModeBanner(),

          if (!tabBottom) tabBar,

          // ── محتوى التبويب — خلفية body الحرفية: paper + تدرجان
          // شعاعيان خافتان (أخضر 4% أعلى اليمين وذهبي 3% أسفل اليسار
          // في RTL) يعطيان عمق الأصل بدل اللون المسطح. ──
          Expanded(
            child: Container(
              color: BrandColors.paper,
              child: CustomPaint(
                painter: BrandColors.darkMode
                    ? null
                    : const _PaperGlowPainter(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: body,
                  ),
                ),
              ),
            ),
          ),

          if (tabBottom)
            SafeArea(top: false, child: tabBar),
        ],
      ),
      // الزر العائم — م107: دائرة ShinyFab الخضراء الموحدة، يساراً دائماً.
      // م172 (قرار المالك): سياقيٌّ بالتبويب — «+» في الرئيسية (إدخال
      // اليوم) فقط، «إضافة حجز» دائري في الحجوزات، ولا زر في البقية.
      // م179 — الزر العائم **ظاهر دائماً** (خيار fabVisible أُلغي): يبقى
      // حارس الصلاحية وحده (من لا يملك إضافة السجلات لا يراه).
      floatingActionButton: !(staffU == null ||
              staffCan(staffU, 'records.add'))
          ? null
          : switch (active) {
              'home' => Padding(
                  padding: EdgeInsets.only(bottom: tabBottom ? 66 : 6),
                  child: ShinyFab(
                    key: const Key('fab-add'),
                    tooltip: 'زيارة جديدة',
                    onTap: () => openAddRecordSheet(context),
                  ),
                ),
              'calendar' => Padding(
                  padding: EdgeInsets.only(bottom: tabBottom ? 66 : 6),
                  child: ShinyFab(
                    key: const Key('fab-book-appt'),
                    tooltip: 'إضافة حجز',
                    icon: Icons.event_available_rounded,
                    // م177 — نوع الحجز «بالدور»: الورقة المنبثقة من
                    // الأسفل (عيادة مفتوحة) وإلا إرشادٌ لفتح عيادة.
                    // التقليدي: مسودة فارغة تفتح معالج الموعد كالسابق.
                    onTap: () {
                      if (bookingSystemOf(ref.read(appConfigProvider)) ==
                          'queue') {
                        if (ref.read(queueViewProvider).clinic != null) {
                          showQueueAddSheet(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'افتح عيادةً أولاً — ثم أضف من زر الحجز داخل لوحتها')),
                          );
                        }
                        return;
                      }
                      ref
                          .read(apptBookDraftProvider.notifier)
                          .state = <String, Object?>{};
                    },
                  ),
                ),
              _ => null,
            },
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}

/// شريط التبويبات — التوأم الحرفي لـ nav-wrap/.tab-b في الأصل:
/// شريط **أبيض** بحد شعري أخضر شفاف، أيقونات مخططة (stroke 1.7) من
/// ملفات SVG الأصلية بشفافية 35% لغير النشط؛ والنشط: أيقونة **ذهبية**
/// متوهجة بتكبير 1.14 بحركة نابضة، نص أخضر عريض، و**نقطة ذهبية 4px**
/// أسفل التبويب (لا خط سفلي). شارة المالية 16px حمراء أعلى يمين الأيقونة.
class _ShellTabBar extends ConsumerWidget {
  const _ShellTabBar({this.bottom = false});

  /// وضع «أسفل» يضيف ظل الأصل العلوي (tabbar-bottom).
  final bool bottom;

  static const _ink72 = Color.fromRGBO(15, 42, 32, .72); // .tab-b
  static const _brand = Color(0xFF1B5E47); // .tab-b.on
  static const _gold = Color(0xFFC9A24B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTabProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // --surface
        border: bottom
            ? const Border(
                top: BorderSide(
                    color: Color.fromRGBO(27, 94, 71, .1)))
            : const Border(
                bottom: BorderSide(
                    color: Color.fromRGBO(20, 80, 59, .08))),
        boxShadow: bottom
            ? const [
                BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, .22),
                    blurRadius: 24,
                    offset: Offset(0, -6)),
              ]
            : null,
      ),
      child: Row(
        children: [
          for (final tab in shellTabs)
            if (shellTabAllowed(ref.watch(currentStaffProvider), tab.id))
            Expanded(
              child: InkWell(
                onTap: () {
                  // م179 — مغادرة المالية تعيد قسمها للخزينة **دائماً**:
                  // خيار keepTabState أُلغي نهائياً (قرار المالك)، والسلوك
                  // مُثبَّت على ما كان سارياً افتراضياً (إعادة الضبط).
                  final leavingFinance =
                      ref.read(activeTabProvider) == 'finance' &&
                          tab.id != 'finance';
                  if (leavingFinance) {
                    ref
                        .read(financeSectionProvider.notifier)
                        .state = 'menu';
                    // توأم onDeactivated في DebtsTab: فلتر عيادة
                    // الديون يُصفَّر أيضاً.
                    ref
                        .read(debtsClinicFilterProvider.notifier)
                        .state = '';
                  }
                  ref.read(activeTabProvider.notifier).state = tab.id;
                },
                child: _TabItem(
                  tab: tab,
                  active: active == tab.id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends ConsumerWidget {
  const _TabItem({required this.tab, required this.active});

  final ShellTab tab;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // .tab-b: padding 8px 2px 12px + min-height 72 (منطقة لمس أكبر).
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // الأيقونة: شفافية .35 لغير النشط، ذهبية متوهجة ×1.14 للنشط
          // (منحنى نابض كالأصل cubic-bezier(0.34,1.56,0.64,1)).
          AnimatedScale(
            scale: active ? 1.14 : 1.0,
            duration: const Duration(milliseconds: 380),
            curve: const Cubic(0.34, 1.56, 0.64, 1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: active
                      ? const BoxDecoration(boxShadow: [
                          BoxShadow(
                              color: Color.fromRGBO(201, 162, 75, .4),
                              blurRadius: 8),
                        ])
                      : null,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : .35,
                    duration: const Duration(milliseconds: 220),
                    child: TabIcon(
                      tab.id,
                      size: 28,
                      color: active
                          ? _ShellTabBar._gold
                          : _ShellTabBar._ink72,
                    ),
                  ),
                ),
                // v52 — شارة عدد الديون على تبويب «المالية» أُزيلت
                // نهائياً بطلب المالك (بقيت شارة قسم الديون داخله).
              ],
            ),
          ),
          const SizedBox(height: 3),
          // النص: 14px، أخضر داكن 72% ← أخضر عريض للنشط.
          Text(
            tab.label,
            style: TextStyle(
              fontSize: 13,
              height: 1.1,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? _ShellTabBar._brand : _ShellTabBar._ink72,
            ),
          ),
          // النقطة الذهبية 4px — .tab-b::after (بديل الخط السفلي).
          const SizedBox(height: 3),
          AnimatedScale(
            scale: active ? 1 : 0,
            duration: const Duration(milliseconds: 380),
            curve: const Cubic(0.34, 1.56, 0.64, 1),
            child: Container(
              key: active ? Key('tab-dot-${tab.id}') : null,
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: _ShellTabBar._gold,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// عُرض إشعار المواعيد لهذا التشغيل؟ (توأم ظهور الإشعار مرة عند الفتح).
bool _apptNotifShownThisRun = false;

@visibleForTesting
void resetApptNotifGuard() => _apptNotifShownThisRun = false;

Future<void> _maybeShowApptNotif(BuildContext context, WidgetRef ref) async {
  if (_apptNotifShownThisRun) return;
  _apptNotifShownThisRun = true;
  final cfg = ref.read(appConfigProvider);
  if (cfg['apptNotif'] == false) return;
  final today = getCurrentDate();
  final t = DateTime.now().add(const Duration(days: 1));
  final tmrw = '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
  final appts = ref.read(reposProvider).appointments.getAll();
  List<Map<String, Object?>> forDay(String d) => [
        for (final a in appts)
          if (a['date'] == d && a['status'] != 'cancelled') a,
      ]..sort(
          (a, b) => '${a['time'] ?? ''}'.compareTo('${b['time'] ?? ''}'));
  final todayAppts = forDay(today);
  final tmrwAppts = forDay(tmrw);
  if (todayAppts.isEmpty && tmrwAppts.isEmpty) return;
  if (!context.mounted) return;

  Widget section(String title, Color color,
          List<Map<String, Object?>> list) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('$title (${list.length})',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
          for (final a in list)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BrandColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BrandColors.line),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['name'] ?? '—'}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      if ('${a['service'] ?? ''}'.isNotEmpty)
                        Text('${a['service']}',
                            style: TextStyle(
                                fontSize: 11, color: BrandColors.mut2)),
                    ],
                  ),
                ),
                Text(
                  jsTruthy(a['time']) ? to12h('${a['time']}') : '—',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark),
                ),
              ]),
            ),
        ],
      );

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('appt-notif-dialog'),
      title: const Row(children: [
        Icon(Icons.notifications_rounded,
            size: 18, color: BrandColors.goldDark),
        SizedBox(width: 6),
        Text('المواعيد القادمة', style: TextStyle(fontSize: 15)),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (todayAppts.isNotEmpty)
              section('مواعيد اليوم', const Color(0xFFF59E0B), todayAppts),
            if (tmrwAppts.isNotEmpty)
              section('مواعيد الغد', const Color(0xFF15604A), tmrwAppts),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('appt-notif-ok'),
          onPressed: () => Navigator.pop(context),
          child: const Text('حسناً'),
        ),
      ],
    ),
  );
}

/// زر الهيدر الدائري — التوأم الحرفي لـ .brand-hdr-btn: قرص 44×44
/// بخلفية بيضاء 8% وحد ذهبي 20% وأيقونة ذهبية فاتحة.
class _HdrCircleBtn extends StatelessWidget {
  const _HdrCircleBtn({
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
        shape: CircleBorder(
          side: BorderSide(
              color: const Color.fromRGBO(201, 162, 75, .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: spinning
                ? const Center(
                    child: SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: BrandColors.goldLight),
                    ),
                  )
                : Icon(icon, size: 20, color: BrandColors.goldLight),
          ),
        ),
      ),
    );
  }
}

/// نقش الهيدر — التوأم الحرفي لـ .brand-header-pattern: بلاطات 60×60
/// من معيّنين متداخلين ودائرة بخطوط ذهبية رفيعة بشفافية 6%.
class _HeaderPatternPainter extends CustomPainter {
  const _HeaderPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 60.0;
    final gold = const Color(0xFFC9A24B).withValues(alpha: .06);
    final p1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = gold;
    final p2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .3
      ..color = gold;
    for (var x = 0.0; x < size.width; x += tile) {
      for (var y = 0.0; y < size.height; y += tile) {
        final c = Offset(x + tile / 2, y + tile / 2);
        // معيّن خارجي 30-60-30 (M30 0L60 30L30 60L0 30Z).
        final outer = Path()
          ..moveTo(c.dx, y)
          ..lineTo(x + tile, c.dy)
          ..lineTo(c.dx, y + tile)
          ..lineTo(x, c.dy)
          ..close();
        canvas.drawPath(outer, p1);
        // معيّن داخلي (M30 10L50 30L30 50L10 30Z).
        final inner = Path()
          ..moveTo(c.dx, y + 10)
          ..lineTo(x + tile - 10, c.dy)
          ..lineTo(c.dx, y + tile - 10)
          ..lineTo(x + 10, c.dy)
          ..close();
        canvas.drawPath(inner, p2);
        // دائرة مركزية r=8.
        canvas.drawCircle(c, 8, p2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeaderPatternPainter oldDelegate) =>
      false;
}

/// توهج الورق — التوأم الحرفي لخلفية body: تدرجان شعاعيان خافتان
/// (أخضر العلامة 4% قرب أعلى البداية وذهبي 3% قرب أسفل النهاية).
class _PaperGlowPainter extends CustomPainter {
  const _PaperGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // ellipse 60% 40% at 15% 15% — rgba(27,94,71,.04)
    final r1 = Rect.fromCenter(
      center: Offset(size.width * .85, size.height * .15), // RTL: 15% من اليمين
      width: size.width * 1.2,
      height: size.height * .8,
    );
    canvas.drawOval(
      r1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color.fromRGBO(27, 94, 71, .04),
            const Color.fromRGBO(27, 94, 71, 0),
          ],
          stops: const [0, .7],
        ).createShader(r1),
    );
    // ellipse 50% 50% at 85% 85% — rgba(201,162,75,.03)
    final r2 = Rect.fromCenter(
      center: Offset(size.width * .15, size.height * .85),
      width: size.width,
      height: size.height,
    );
    canvas.drawOval(
      r2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color.fromRGBO(201, 162, 75, .03),
            const Color.fromRGBO(201, 162, 75, 0),
          ],
          stops: const [0, .7],
        ).createShader(r2),
    );
  }

  @override
  bool shouldRepaint(covariant _PaperGlowPainter oldDelegate) => false;
}

/// م78 — شريط «الوضع المحلي»: أخطر عطل صامت في التطبيق.
///
///  العلة
///  ─────
///  `transportProvider` يُرجع خادماً وهمياً في الذاكرة كلما كان
///  `cloudConfigProvider == null` — أي حين يُبنى التطبيق بلا أسرار سحابية
///  أو يُحذف ملف الإعداد. والتطبيق حينها **يعمل بلا خلل ظاهر**: تُحفظ
///  الزيارات، وتُطبع التقارير، ولا تظهر رسالة خطأ واحدة.
///
///  لكن **لا شيء يغادر الجهاز**. لا مزامنة مع جهاز آخر، ولا نسخة على
///  الخادم. وشاشة الحالة تقول «آخر مزامنة ناجحة: —» وهي عبارة لا يميّز
///  المستخدم فيها بين «لم تبدأ بعد» و«لا سحابة أصلاً».
///
///  فقد تعمل عيادة **شهوراً** ظانّةً أن بياناتها محفوظة، ثم يسقط اللوح
///  فتضيع سنوات من السجلات. وهذا أسوأ من عطل ظاهر بمراتب: العطل الظاهر
///  يُصلَح في يومه.
///
///  التصميم
///  ───────
///  شريط دائم — لا إشعار يُغلَق ولا حوار يُتجاوَز. الحالة **مستمرة** لا
///  حدث، فيجب أن يكون التذكير مستمراً مثلها. ويختفي وحده لحظة ضبط السحابة.
class LocalModeBanner extends ConsumerWidget {
  const LocalModeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudConfigProvider) != null) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFF8A1C1C),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('وضع محلي — لا مزامنة'),
            content: const Text(
              'هذا الجهاز لا يرسل بياناته إلى السحابة ولا يستقبل منها.\n\n'
              '• لا تظهر بياناته على أي جهاز آخر.\n'
              '• لا توجد نسخة خارج هذا الجهاز — فقدانه فقدانٌ لكل السجلات.\n\n'
              'اضبط الاتصال السحابي، أو خذ نسخة احتياطية يدوية بانتظام.',
              style: TextStyle(height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('فهمت'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 7),
              const Flexible(
                child: Text(
                  'وضع محلي — لا مزامنة ولا نسخة خارج هذا الجهاز',
                  key: Key('local-mode-banner'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
