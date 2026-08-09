/// شاشة الإعدادات — نسخة 1:1 من SettingsModal.vue: عشر مجموعات قابلة للطي
/// بنفس الترتيب والرؤوس (أيقونة + عنوان + سهم يدور) وبطاقات داخلية وحقول
/// سطرية بأزرار حفظ ذهبية، ثم تسجيل الخروج وبطاقة حساب المستخدم وبطاقة
/// الدعم الفني — وأسفلها مجموعة «السحابة والترحيل» الخاصة بنسخة Flutter.
///
/// النموذج المحلي كما في الأصل (localCfg): متحكمات تُبذر من config وتُكتب
/// بأزرار الحفظ عبر settings.set (يُختم HLC ويُدمج بنيوياً عند المزامنة).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateController, StateProvider;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/error_log.dart' show recordError;
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/security/factory_reset.dart' show runFactoryReset;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import '../staff/staff_session.dart' show currentStaffProvider, staffIsAdmin;
import '../staff/staff_recovery.dart'
    show showEnableStaffSystemDialog, showDisableStaffSystemDialog;
import '../staff/staff_store.dart' show StaffStore;
import '../staff/staff_users_screen.dart' show StaffUsersScreen;
import '../staff/activity_log_screen.dart' show ActivityLogScreen;
import '../staff/staff_account_screen.dart' show StaffAccountCard;
import '../../core/app_build.dart';
import '../../core/theme/app_theme.dart';
import '../xrays/storage_meter.dart'
    show StorageMeter, StorageLevel, humanBytesAr;
import '../../core/utils/js_compat.dart';
import '../../data/db/local_db.dart' show LocalDb;
import '../../data/rates/rate_snapshot.dart';
import '../../data/repositories/repositories.dart' show Repositories;
import '../../data/sync/db_sync.dart' show getMetaValue, setMetaValue;
import '../patients/patients_tab.dart' show patientsRevProvider;
import '../records/default_treatment.dart' show clearLastTreatment;
import '../records/record_saver.dart' show isProsthetic;
import 'settings_actions.dart';
import 'account_section.dart';
import 'subscription_section.dart';
import '../auth/idle_lock.dart' show hasLockVerifier;
import '../auth/lock_prefs.dart';
import '../auth/pin_setup.dart';
import '../notifications/notification_center.dart'
    show showUpdateButtonPref, setShowUpdateButtonPref;
import 'analyses3.dart'
    show
        kTriAnalysesCfgKey,
        kTriAnalysesName,
        triAnalysesEnabled,
        triAnalysesPrice,
        triRepeatMonths;

typedef JMap = Map<String, Object?>;

// م143 — الافتراضات المقفولة: طرق الدفع كاش/تحويل لا تُحذف (والإضافة
// موقوفة حالياً)، والمعالجة «تركيبات» لا تُحذف — حمايةً من بثِّ حذفٍ
// (شاهد قبر) لافتراضٍ إلى كل الأجهزة. الأسعار تبقى قابلة للتعديل للجميع،
// وحذف/تعديل باقي المعالجات (حشوا العصب وأيّ إضافة) يبقى متاحاً.
const Set<String> _kLockedPayments = {'كاش', 'تحويل'};
const Set<String> _kLockedServices = {'تركيبات'};

// م143 — مهلة التراجع عن الحذف (بالثواني): تفضيلٌ محليٌّ لكل جهاز في
// sync_meta (لا يُزامَن — نفس مكان تفضيلات القفل م87). الغياب ⇒ 3 ثوانٍ،
// و0 ⇒ إيقاف المؤقّت (حذفٌ فوري). قسم الأشعة يقرأ هذا المفتاح لِمُهلة
// «تراجع» في شريط الإشعار عند الحذف.
const String _kXrayDeleteUndoSecsKey = 'xray.delete_undo_secs';
const int _kXrayDeleteUndoDefault = 3;
const List<int> _kXrayDeleteUndoChoices = [3, 5, 10, 0];

/// يقرأ مهلة التراجع عن الحذف — الغياب/غير الصالح ⇒ الافتراضي (3).
int xrayDeleteUndoSecs(LocalDb db) {
  final v = getMetaValue(db, _kXrayDeleteUndoSecsKey);
  if (v == null) return _kXrayDeleteUndoDefault;
  final n = int.tryParse('$v'.trim());
  return (n != null && n >= 0) ? n : _kXrayDeleteUndoDefault;
}

/// يكتب مهلة التراجع (بختم المالك، نمط تفضيلات القفل).
void setXrayDeleteUndoSecs(LocalDb db, int secs) {
  try {
    setMetaValue(db, _kXrayDeleteUndoSecsKey, '$secs', db.getOwnerUid() ?? '');
  } catch (_) {/* أفضل جهد */}
}

/// منتقيات قابلة للحقن للاختبارات.
typedef ImagePick = Future<(String, Uint8List)?> Function();
typedef TextFilePick = Future<String?> Function();

Future<(String, Uint8List)?> _defaultImagePick() async {
  const group = XTypeGroup(
    label: 'صور',
    extensions: ['png', 'jpg', 'jpeg', 'svg', 'webp'],
  );
  final f = await openFile(acceptedTypeGroups: [group]);
  if (f == null) return null;
  return (f.name, await f.readAsBytes());
}

Future<String?> _defaultJsonPick() async {
  const group = XTypeGroup(label: 'JSON', extensions: ['json']);
  final f = await openFile(acceptedTypeGroups: [group]);
  if (f == null) return null;
  return utf8.decode(await f.readAsBytes(), allowMalformed: true);
}

final logoPickProvider = Provider<ImagePick>((ref) => _defaultImagePick);
final jsonPickProvider = Provider<TextFilePick>((ref) => _defaultJsonPick);

/// م70 — نبضة إعادة بناء بطاقة الأرشفة (حالتها تعيش في sync_meta لا هنا).
final _archiveRev = StateProvider<int>((ref) => 0);

/// افتراضي رسالة الدور — حرفياً من الأصل.
const kDefaultQueueWaTemplate =
    'مرحباً {name} 🦷\nدوركم اقترب في {center} ({clinic}).\nيرجى التوجّه خلال الوقت المتوقع: {time}';

/// أنواع التأكيد المزدوج — dcItems حرفياً.
const dcItems = [
  ('rec', 'السجلات', 'سجلات العلاج والتركيبات'),
  ('debt', 'الديون', 'سجلات الديون والدفعات'),
  ('pat', 'المرضى', 'حذف بيانات مريض بالكامل'),
  ('appt', 'المواعيد', 'حذف مواعيد المرضى'),
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// م92 — القسم المفتوح حالياً (null = القائمة الرئيسية).
  ///
  /// كانت الأقسام أكورديوناً في صفحة واحدة (`Set<String> open`)، وصارت
  /// «قائمة رئيسية ← صفحة قسم» على نمط تطبيقات المراسلة. التبديل يحدث
  /// **داخل نفس كائن الحالة** لا بدفع Route: أجسام الأقسام تتشارك
  /// المتحكمات وعقد التركيز (الحفظ عند فقد التركيز م55) ودوال الحفظ،
  /// وRoute منفصل يقطع setState عن شجرته فتتجمد مفاتيح التبديل.
  String? openSection;

  /// م92 — مغادرة القسم تمرّ من هنا حصراً (سهم الرجوع وزر النظام معاً).
  ///
  /// شبكة أمان أسعار المعالجات: م55 كانت تعتمد فقدَ تركيز الحقل — يفي
  /// بذلك تفكيكُ المسار عند مغادرة الشاشة كلها، أما التبديل الداخلي
  /// فيُخرج الحقل من الشجرة عبر AnimatedSwitcher وقد يسبق حتى اكتمالَ
  /// طلب التركيز نفسه (كتابةٌ ثم مغادرة فورية) فلا يقع فقدُ تركيزٍ ولا
  /// التزام. فيُلتزم هنا بكل سعرٍ معلّق قبل الإغلاق — و[_commitSvcPrice]
  /// تكتب فقط عند تغيّرٍ حقيقي، فالنداء الشامل بلا كلفة ولا ضجيج.
  void _closeSection() {
    for (final svc in svcPriceCtls.keys.toList()) {
      _commitSvcPrice(svc, ui: false);
    }
    // «التحاليل الثلاثية» — يُلتزم بالسعر المعلّق قبل إغلاق القسم (توأم svc).
    _commitTriAnalPrice(ui: false);
    setState(() => openSection = null);
  }

  // ── النموذج المحلي (localCfg) ──
  final centerCtl = TextEditingController();
  final currencyCtl = TextEditingController();
  final newClinicCtl = TextEditingController();
  final newServiceCtl = TextEditingController();
  final newPaymentCtl = TextEditingController();
  final qMorningCtl = TextEditingController();
  final qEveningCtl = TextEditingController();
  final qSlotCtl = TextEditingController();
  // ساعات دوام النظام التقليدي (مدى جدول المواعيد الأسبوعي).
  final workdayStartCtl = TextEditingController();
  final workdayEndCtl = TextEditingController();
  final qWaCtl = TextEditingController();
  final syncMinCtl = TextEditingController();
  final newLabCtl = TextEditingController();
  final newLabTypeNameCtl = TextEditingController();
  final newLabTypePriceCtl = TextEditingController();

  // «التحاليل الثلاثية» — متحكم سعر التحليل الثابت وعقدة تركيزه.
  final triAnalPriceCtl = TextEditingController();
  final triAnalPriceFocus = FocusNode(debugLabel: 'tri-anal-price');
  // م149 — متحكم «المدة المسموح بها لإعادة التحليل (بالأشهر)» وعقدته.
  final triAnalRepeatCtl = TextEditingController();
  final triAnalRepeatFocus = FocusNode(debugLabel: 'tri-anal-repeat');

  int? editingClinicIdx;
  final renameClinicCtl = TextEditingController();

  // أسعار المعالجات ومدد التأكيد — متحكمات ثابتة عبر إعادة البناء.
  final svcPriceCtls = <String, TextEditingController>{};
  final dcDurCtls = <String, TextEditingController>{};

  // م55 — عقدة تركيز لكل حقل سعر معالجة: مغادرة الحقل = حفظ (كان الحفظ
  // على Enter فقط فيضيع السعر عند اللمس خارجاً أو الرجوع من الشاشة).
  final svcPriceFocusNodes = <String, FocusNode>{};

  // قوالب واتساب والمختبرات — قوائم محلية تُحفظ بزر (نموذج الأصل).
  List<Map<String, TextEditingController>> waTpls = [];
  List<TextEditingController> labCtls = [];
  List<(TextEditingController, TextEditingController)> labTypeCtls = [];
  bool _seeded = false;
  // م87 — تفضيلات القفل محليّة (sync_meta) لا من app.config المُزامَن.
  bool _lockOnStart = true;
  bool _biometric = false;
  // م143 — مهلة التراجع عن الحذف (ثوانٍ، محليّة): 3 افتراضاً، 0 = إيقاف.
  int _deleteUndoSecs = _kXrayDeleteUndoDefault;

  @override
  void initState() {
    super.initState();
    // م54 — فتح الإعدادات = لحظة نظر المستخدم: دورة مزامنة فورية تلتقط
    // ما أضافه الجهاز الآخر (معالجة/سعر/عيادة) بدل انتظار نبضة الاستطلاع.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) kickPresenceSync(ref);
    });
  }

  // م55 — مبلّغ الإشعارات ومرجع المستودع/عدّاد النسخة ملتقطة وهي حية:
  // dispose لا يجوز أن يلمس `ref` (BuildContext غير آمن بعد التعطيل —
  // إرشاد Riverpod نفسه: احفظ الحالة في حقل). فحفظ السعر عند مغادرة
  // الشاشة يمر عبر هذه المراجع المحفوظة لا عبر ref.
  ScaffoldMessengerState? _messenger;
  Repositories? _repos;
  StateController<int>? _configRev;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _repos = ref.read(reposProvider);
    _configRev = ref.read(configRevProvider.notifier);
  }

  @override
  void dispose() {
    // م55 — لا حفظ داخل dispose: مغادرة الشاشة (رجوع مباشر) تُفقد حقلَ
    // السعر تركيزه ضمن تفكيك المسار، فيمرّ مستمع فقد التركيز على
    // _commitSvcPrice ويكتب للقاعدة قبل فحص mounted (الكتابة تسبقه).
    // الاستعلام من القاعدة أثناء التفكيك كان هشّاً ويكسر ترتيب الفك.
    for (final n in svcPriceFocusNodes.values) {
      n.dispose();
    }
    // «التحاليل الثلاثية» — تفكيك عقدتَي تركيز السعر والمدة.
    triAnalPriceFocus.dispose();
    triAnalRepeatFocus.dispose();
    for (final c in [
      centerCtl,
      currencyCtl,
      newClinicCtl,
      newServiceCtl,
      newPaymentCtl,
      qMorningCtl,
      qEveningCtl,
      qSlotCtl,
      workdayStartCtl,
      workdayEndCtl,
      qWaCtl,
      syncMinCtl,
      newLabCtl,
      newLabTypeNameCtl,
      newLabTypePriceCtl,
      triAnalPriceCtl,
      triAnalRepeatCtl,
      renameClinicCtl,
    ]) {
      c.dispose();
    }
    for (final c in svcPriceCtls.values) {
      c.dispose();
    }
    for (final c in dcDurCtls.values) {
      c.dispose();
    }
    for (final t in waTpls) {
      t['lbl']!.dispose();
      t['msg']!.dispose();
    }
    for (final c in labCtls) {
      c.dispose();
    }
    for (final (a, b) in labTypeCtls) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  void _seed(JMap cfg) {
    if (_seeded) return;
    _seeded = true;
    final db = ref.read(localDbProvider);
    // م97 — العرض الفعّال: المفتاحان لا يظهران مفعَّلَين إلا برمزٍ
    // معيَّن، مهما كان التفضيل المخزَّن — فالقاعدة «لا قفل ولا بصمة بلا
    // رمز» تنعكس في الواجهة كما في السلوك.
    final pinned = hasPinVerifier(db);
    _biometric = biometricEnabled(db) && pinned;
    _lockOnStart =
        lockOnStartEnabled(db) && (hasLockVerifier(db) || biometricEnabled(db));
    _deleteUndoSecs = xrayDeleteUndoSecs(db);
    centerCtl.text = '${cfg['centerName'] ?? ''}';
    currencyCtl.text = '${cfg['currency'] ?? 'د.ل'}';
    qMorningCtl.text = '${cfg['queueMorningStart'] ?? '09:00'}';
    qEveningCtl.text = '${cfg['queueEveningStart'] ?? '16:00'}';
    workdayStartCtl.text = '${cfg['workdayStart'] ?? '09:00'}';
    workdayEndCtl.text = '${cfg['workdayEnd'] ?? '21:00'}';
    qSlotCtl.text = jsNumOr0(jsOr(cfg['queueSlotMin'], 15)).toStringAsFixed(0);
    qWaCtl.text = '${jsOr(cfg['queueWaTemplate'], kDefaultQueueWaTemplate)}';
    syncMinCtl.text = jsNumOr0(jsOr(cfg['syncMin'], 30)).toStringAsFixed(0);
    waTpls = [
      for (final t in (cfg['waTemplates'] as List? ?? const []))
        if (t is Map)
          {
            'lbl': TextEditingController(text: '${t['lbl'] ?? ''}'),
            'msg': TextEditingController(text: '${t['msg'] ?? ''}'),
          },
    ];
    labCtls = [
      for (final l in (cfg['labs'] as List? ?? const []))
        TextEditingController(text: '$l'),
    ];
    labTypeCtls = [
      for (final t in (cfg['labTypes'] as List? ?? const []))
        if (t is Map)
          (
            TextEditingController(text: '${t['name'] ?? ''}'),
            TextEditingController(
              text: jsNumOr0(t['defaultPrice']).toStringAsFixed(0),
            ),
          ),
    ];
  }

  void _update(JMap Function(JMap cfg) mutate) {
    final cfg = Map<String, Object?>.from(ref.read(appConfigProvider));
    // v30 — نمرّر اللقطة الأساس: يُكتب ما غيّرته هذه الشاشة فقط، فلا
    // تُرجَع قيمة قديمة فوق تعديل جهاز آخر وصل بين القراءة والحفظ.
    ref
        .read(reposProvider)
        .settings
        .set(
          'app.config',
          mutate(Map<String, Object?>.from(cfg)),
          configBase: cfg,
        );
    ref.read(configRevProvider.notifier).state++;
    setState(() {});
  }

  /// v30 — حذف عنصر قائمة **بنداء صريح** (شاهد قبر على صفه): حتمي على
  /// كل الأجهزة، ولا يمكن لحفظ من لقطة قديمة أن يمحو عنصراً أضافه غيرنا.
  void _removeItem(List<String> path, Object? item) {
    ref.read(reposProvider).settings.configRemoveItem(path, item);
    ref.read(configRevProvider.notifier).state++;
    setState(() {});
  }

  /// إضافة عنصر قائمة (صف مستقل ⇒ إضافتان من جهازين تنجوان معاً).
  void _addItem(List<String> path, Object? item) {
    ref.read(reposProvider).settings.configAddItem(path, item);
    ref.read(configRevProvider.notifier).state++;
    setState(() {});
  }

  void _snack(String msg) => (_messenger ?? ScaffoldMessenger.of(context))
      .showSnackBar(SnackBar(content: Text(msg)));

  List<String> _list(JMap cfg, String key) =>
      cfg[key] is List ? [for (final e in cfg[key] as List) '$e'] : <String>[];

  /// تطبيع وقت HH:MM بتسامح (يقبل «9»، «9:5»، «09:05») — يعيد [fallback]
  /// عند التعذّر، ويقصّ الساعة 0-23 والدقيقة 0-59.
  String _normHHMM(String raw, String fallback) {
    final m = RegExp(r'^\s*(\d{1,2})\s*[:.]?\s*(\d{1,2})?\s*$').firstMatch(raw);
    if (m == null) return fallback;
    final h = int.parse(m.group(1)!).clamp(0, 23);
    final mi = int.tryParse(m.group(2) ?? '0')?.clamp(0, 59) ?? 0;
    return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
  }

  JMap _dc(JMap cfg) {
    final v = cfg['dcConfirm'];
    final m = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
    return {
      for (final (key, _, _) in dcItems) ...{
        '${key}On': m['${key}On'] != false,
        '${key}Dur': jsNumOr0(jsOr(m['${key}Dur'], 3)),
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    _seed(cfg);

    // م46/v24 — الخلفية فاتحة كما كانت، والشريط العلوي وحده نسخة حرفية
    // من هيدر الصدفة (عبدالكريم): تدرج الهوية نفسه بنفس الحشوات، يبدأ
    // من أول بكسل خلف شريط النظام الشفاف — لون واحد متصل بلا فاصل.
    //
    // م92 — «قائمة رئيسية ← صفحة قسم»: الهيدر واحدٌ يبدّل عنوانه ووجهةَ
    // رجوعه، والجسم يتبادل بين قائمة الأقسام وصفحة القسم المفتوح.
    // زرُّ رجوع النظام يغلق القسمَ أولاً (PopScope) — كسلوك المراسلات.
    final section = openSection == null
        ? null
        : _sections.firstWhere((s) => s.id == openSection);
    return PopScope(
      canPop: section == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) _closeSection();
      },
      child: Scaffold(
        body: Column(
          children: [
            Container(
              key: const Key('settings-header'),
              decoration: const BoxDecoration(
                gradient: BrandColors.brandGradient,
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 10,
                bottom: 10,
                left: 12,
                right: 12,
              ),
              child: Row(
                children: [
                  section == null
                      ? BackButton(
                          color: Colors.white,
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                      : BackButton(
                          key: const Key('settings-section-back'),
                          color: Colors.white,
                          onPressed: _closeSection,
                        ),
                  Expanded(
                    child: Text(
                      section?.title ?? 'الإعدادات',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // موازنة زر الرجوع.
                ],
              ),
            ),
            Expanded(
              // انتقالٌ ناعم بإيقاع حركة التطبيق (تلاشٍ + انزياح خفيف).
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .015),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: section != null
                    ? ListView(
                        key: ValueKey('section-${section.id}'),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 60),
                        children: [section.body(cfg)],
                      )
                    : ListView(
                        key: const ValueKey('settings-hub'),
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 60),
                        children: [
                          // م124 — بطاقة حساب الموظف أعلى الإعدادات (ترتيب الهيدر):
                          // التبديل والخروج انتقلا هنا من زر الترويسة المحذوف.
                          if (ref.watch(currentStaffProvider) != null) ...[
                            _glass(child: const StaffAccountCard()),
                            const SizedBox(height: 6),
                          ],
                          for (final s in _sections) _hubRow(s),
                          // م64 — مجموعة «السحابة والترحيل» أُزيلت: الاتصال السحابي
                          // يُبنى وقت البناء (dart-define) ومحرك المزامنة يعمل تلقائياً
                          // بلا حاجة لمحرر داخل التطبيق أو أداة ترحيل.

                          // ── تسجيل الخروج ──
                          const SizedBox(height: 6),
                          _glass(
                            child: SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                key: const Key('logout-btn'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF4455),
                                  backgroundColor: const Color(
                                    0xFFFF4455,
                                  ).withValues(alpha: .1),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _confirmLogout,
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 17,
                                ),
                                label: const Text(
                                  'تسجيل الخروج',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // م94 — بطاقةُ البريد المستقلة أُزيلت (طلب المالك): البريد
                          // وإدارتُه صارا داخل قسم «إعدادات الحساب» نفسه، وبطاقتا الحالة
                          // والدعم انتقلتا إلى قسم «حول التطبيق» — فلا يبقى هنا إلا الخروج.
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ م94 — جسم قسم «حول التطبيق» ═══

  /// نسخة التطبيق وحالة المزامنة (v28) + التواصل مع المطور — كانتا
  /// بطاقتين أسفل القائمة الرئيسية وانتقلتا قسماً مستقلاً بطلب المالك.
  // ignore: unused_element_parameter
  Widget _aboutBody(JMap cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── v28: هوية البناء وحالة المزامنة (للتحقق من تطابق الأجهزة) ──
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: BrandColors.brandIcon,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'حالة التطبيق والمزامنة',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final st = ref.watch(syncUiProvider);
                  final engine = ref.read(syncEngineProvider);
                  var pending = st.pending;
                  var quarantined = 0;
                  int? lastTs;
                  try {
                    final es = engine.getEngineStatus();
                    pending = es.pending;
                    // م77 — الصفوف المحجورة كانت تُحسب وتُطرح من العدّاد
                    // ثم لا تُعرض في أي مكان: `EngineStatus.quarantined`
                    // بلا مستهلك واحد. فكانت الشاشة تقول «صفر معلّق ·
                    // تمّت المزامنة الآن» بينما زيارة أو دفعة أو صورة
                    // أشعة لم تصل الخادم قطّ — وهذا أسوأ من عطل ظاهر.
                    quarantined = es.quarantined;
                    lastTs = es.lastSyncTs;
                  } catch (_) {
                    /* أفضل جهد */
                  }
                  final last =
                      st.lastOk ??
                      (lastTs != null
                          ? DateTime.fromMillisecondsSinceEpoch(lastTs)
                          : null);
                  String two(int v) => v.toString().padLeft(2, '0');
                  final lastTxt = last == null
                      ? '—'
                      : '${two(last.hour)}:${two(last.minute)}';
                  Widget line(String k, String v, {Color? color}) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          k,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: BrandColors.mut2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          v,
                          key: Key('appinfo-\$k'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                  return Column(
                    children: [
                      line('نسخة التطبيق', appBuildLabel),
                      line('آخر مزامنة ناجحة', lastTxt),
                      line(
                        'تغييرات غير مدفوعة',
                        '\$pending',
                        color: pending > 0
                            ? BrandColors.red
                            : BrandColors.green,
                      ),
                      // م77 — لا يظهر السطر إلا عند وجود محجور فعلاً، فلا
                      // ضجيج على الحالة السليمة. ووجوده يعني أن صفوفاً
                      // أخفقت ثماني مرات وتوقّف المحرك عن محاولتها.
                      if (quarantined > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 15,
                              color: BrandColors.red,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '\$quarantined عنصراً تحتاج انتباهاً — '
                                'لم تصل الخادم بعد محاولات متكررة',
                                key: const Key('quarantine-notice'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('quarantine-retry'),
                            onPressed: () async {
                              // `retryFailedAndSync` كانت موجودة ومختبَرة
                              // و**بلا مستدعٍ في كامل lib**: الآلية جاهزة
                              // وينقصها مقبض فقط.
                              try {
                                await engine.retryFailedAndSync();
                              } catch (_) {
                                /* أفضل جهد */
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'أُعيدت محاولة العناصر المتوقفة',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text(
                              'أعد المحاولة',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // ── الدعم الفني ──
        _glass(
          child: Column(
            children: [
              Text(
                'الدعم الفني',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  key: const Key('support-wa'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    backgroundColor: const Color(
                      0xFF25D366,
                    ).withValues(alpha: .1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/218919292258'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 17),
                  label: const Text(
                    'تواصل مع المطور — 0919292258',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══ م92 — سجلّ الأقسام وصفوف القائمة الرئيسية ═══

  /// سجلّ الأقسام العشرة: القائمة الرئيسية تُبنى منه (أيقونة + عنوان +
  /// سطر وصفٍ يلخّص محتوى القسم **فعلياً** — لا شعارات عامة)، وصفحة
  /// القسم تستدعي جسمه القائم كما هو بلا أي تعديل.
  ///
  /// الأجسام تُستدعى كسولاً كما في م82: القائمة الرئيسية لا تبني قسماً
  /// واحداً، وصفحة القسم تبني قسمها وحده.
  List<
    ({
      String id,
      IconData icon,
      Color? iconColor,
      String title,
      String sub,
      Widget Function(JMap) body,
    })
  >
  get _sections => [
    // المرحلة د — «الاشتراك والترخيص»: للحسابات السحابية وحدها (بلا اتصال
    // لا اشتراكَ يُعرض). في المقدّمة لأهميته.
    if (ref.read(cloudConfigProvider) != null)
      (
        id: 'subscription',
        icon: Icons.workspace_premium_rounded,
        iconColor: BrandColors.gold,
        title: 'الاشتراك والترخيص',
        sub: 'خطتك وحالتها، التخزين والأجهزة، التجديد والترقية',
        body: (_) => const SubscriptionSection(),
      ),
    (
      id: 'center',
      icon: Icons.apartment_rounded,
      iconColor: null,
      title: 'معلومات المركز',
      sub: 'اسم المركز أو الطبيب، شعار التقرير، عملة الدفع',
      body: _centerBody,
    ),
    (
      id: 'clinic',
      icon: Icons.medical_services_rounded,
      iconColor: null,
      title: 'العيادات والمعالجات',
      sub: 'العيادات، المعالجات وأسعارها، المعالجة الافتراضية، طرق الدفع',
      body: _clinicBody,
    ),
    (
      id: 'rates',
      icon: Icons.percent_rounded,
      iconColor: null,
      title: 'نسب الطبيب',
      sub: 'نسبة الطبيب من المعالجات الخاصة لكل عيادة',
      body: _ratesBody,
    ),
    (
      id: 'booking',
      icon: Icons.event_note_rounded,
      iconColor: null,
      title: 'نظام الحجز',
      sub: 'التقليدي أو الدور، حساب الوقت المتوقع، رسالة الدور الجاهزة',
      body: _bookingBody,
    ),
    (
      id: 'protect',
      icon: Icons.shield_rounded,
      iconColor: null,
      title: 'الحماية والتأكيدات',
      sub: 'قفل الدخول، البصمة، رمز القفل، تأكيدات الحذف المزدوجة',
      body: _protectBody,
    ),
    // م-تكافؤ — قسم رئيسي مستقل (قرار المالك): كان مدفوناً في «المظهر».
    (
      id: 'staff',
      icon: Icons.manage_accounts_rounded,
      iconColor: null,
      title: 'الموظفون والصلاحيات',
      sub: 'تفعيل نظام الموظفين، الحسابات والصلاحيات، سجل النشاط',
      body: _staffBody,
    ),
    (
      id: 'notif',
      icon: Icons.notifications_rounded,
      iconColor: null,
      title: 'الإشعارات',
      sub: 'تذكير مواعيد اليوم والغد عند فتح التطبيق',
      body: _notifBody,
    ),
    (
      id: 'expenses',
      icon: Icons.account_balance_wallet_rounded,
      iconColor: null,
      title: 'المصروفات والرواتب',
      sub: 'سياسة ترحيل المتبقّي من الرواتب',
      body: _expensesBody,
    ),
    (
      id: 'theme',
      icon: Icons.dark_mode_rounded,
      iconColor: null,
      title: 'المظهر والعرض',
      sub: 'المظهر، حجم الخط، شريط التبويبات، الزر العائم، شارة الديون',
      body: _themeBody,
    ),
    (
      id: 'storage',
      icon: Icons.cloud_rounded,
      iconColor: null,
      title: 'التخزين والنسخ الاحتياطي',
      sub: 'الأرشفة الباردة، المزامنة، النسخ الاحتياطي',
      body: _storageBody,
    ),
    (
      id: 'wa',
      icon: Icons.chat_rounded,
      iconColor: const Color(0xFF25D366),
      title: 'قوالب رسائل واتساب',
      sub: 'قوالب جاهزة باسم المريض والعيادة للتذكير والمتابعة',
      body: _waBody,
    ),
    (
      id: 'labs',
      icon: Icons.biotech_rounded,
      iconColor: null,
      title: 'إعدادات المختبرات',
      sub: 'قائمة المختبرات، أنواع التركيبات وأسعارها',
      body: _labsBody,
    ),
    // م93 — «إعدادات الحساب»: أسفل المختبرات، للحسابات السحابية وحدها
    // (بلا اتصالٍ سحابي لا حسابَ يُدار). المنطق في AccountAdmin؛
    // الجسم واجهةٌ صرفة في account_section.dart.
    if (ref.read(accountAdminProvider) != null)
      (
        id: 'account',
        icon: Icons.manage_accounts_rounded,
        iconColor: null,
        title: 'إعدادات الحساب',
        sub: 'البريد، كلمة المرور، حذف الحساب',
        body: (_) => const AccountSection(),
      ),
    // م94 — «حول التطبيق»: بطاقتا «حالة التطبيق والمزامنة» (v28)
    // و«التواصل مع المطور» انتقلتا من أسفل القائمة إلى هنا (طلب
    // المالك) — فلا يبقى أسفل الصفوف إلا زرّ تسجيل الخروج.
    (
      id: 'about',
      icon: Icons.info_outline_rounded,
      iconColor: null,
      title: 'حول التطبيق',
      sub: 'نسخة التطبيق، حالة المزامنة، التواصل مع المطور',
      body: _aboutBody,
    ),
  ];

  /// صفُّ القائمة الرئيسية — نمط قوائم المراسلات بهوية التطبيق: أيقونة
  /// داخل قرصٍ بلون العلامة الباهت، عنوانٌ عريض، وسطرُ وصفٍ رمادي.
  /// المفتاح `group-$id` نفسه القديم فتبقى مسالك الاختبارات كما هي،
  /// والنقر يفتح صفحة القسم بدل طيّ الأكورديون.
  Widget _hubRow(
    ({
      String id,
      IconData icon,
      Color? iconColor,
      String title,
      String sub,
      Widget Function(JMap) body,
    })
    s,
  ) {
    final tint = s.iconColor ?? BrandColors.brand600;
    return InkWell(
      key: Key('group-${s.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => openSection = s.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: .10),
              ),
              child: Icon(s.icon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: BrandColors.mut2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 5),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: BrandColors.surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: BrandColors.line),
    ),
    child: child,
  );

  Widget _secH(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: BrandColors.gold,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          s,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  /// حقل + زر حفظ ذهبي (نمط الأصل السطري).
  Widget _inputSave(
    Key key,
    TextEditingController ctl,
    String hint,
    VoidCallback onSave, {
    Key? saveKey,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: key,
            controller: ctl,
            decoration: InputDecoration(isDense: true, hintText: hint),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: saveKey,
          style: FilledButton.styleFrom(
            backgroundColor: BrandColors.gold,
            foregroundColor: BrandColors.brand900,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onSave,
          child: const Text('حفظ', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _toggleRow(
    String title,
    String sub,
    bool value,
    void Function(bool) onChanged, {
    Key? key,
  }) {
    return _glass(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
                  ),
              ],
            ),
          ),
          Switch(key: key, value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // ═══ 1) معلومات المركز ═══

  Widget _centerBody(JMap cfg) {
    final logo = '${cfg['logo'] ?? ''}';
    return Column(
      children: [
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('اسم المركز'),
              _inputSave(
                const Key('center-name-input'),
                centerCtl,
                'طب الأسنان الرقمي',
                saveKey: const Key('center-name-save'),
                () {
                  _update((c) => {...c, 'centerName': centerCtl.text.trim()});
                  _snack('تم الحفظ');
                },
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('شعار طباعة التقرير'),
              if (logo.startsWith('data:'))
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: BrandColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: BrandColors.line),
                      ),
                      child: _logoImage(logo),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('logo-remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: BrandColors.red,
                      ),
                      onPressed: () {
                        _update((c) => {...c, 'logo': ''});
                        _snack('تم حذف الشعار');
                      },
                      child: const Text(
                        '✕ حذف',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('logo-upload'),
                  onPressed: () async {
                    final picked = await ref.read(logoPickProvider)();
                    if (picked == null) return;
                    final (name, bytes) = picked;
                    final ext = name.split('.').last.toLowerCase();
                    final mime = ext == 'svg'
                        ? 'image/svg+xml'
                        : ext == 'png'
                        ? 'image/png'
                        : 'image/jpeg';
                    _update(
                      (c) => {
                        ...c,
                        'logo': 'data:$mime;base64,${base64Encode(bytes)}',
                      },
                    );
                    _snack('تم حفظ الشعار');
                  },
                  icon: const Icon(Icons.upload_rounded, size: 15),
                  label: const Text(
                    'رفع صورة من الجهاز',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              Text(
                'PNG/JPG/SVG — يظهر في أعلى صفحة الطباعة',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('عملة الدفع'),
              _inputSave(
                const Key('currency-input'),
                currencyCtl,
                'د.ل',
                saveKey: const Key('currency-save'),
                () {
                  _update((c) => {...c, 'currency': currencyCtl.text.trim()});
                  _snack('تم الحفظ');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoImage(String dataUrl) {
    try {
      final i = dataUrl.indexOf('base64,');
      if (i < 0 || dataUrl.contains('svg')) {
        return Icon(Icons.image_rounded, size: 34, color: BrandColors.faint);
      }
      return Image.memory(
        base64Decode(dataUrl.substring(i + 7)),
        height: 44,
        fit: BoxFit.contain,
      );
    } catch (_) {
      return Icon(
        Icons.broken_image_rounded,
        size: 34,
        color: BrandColors.faint,
      );
    }
  }

  // ═══ 2) العيادات والمعالجات ═══

  Widget _clinicBody(JMap cfg) {
    final clinics = _list(cfg, 'clinics');
    final services = _list(cfg, 'services');
    final payments = _list(cfg, 'payments');
    final prices = cfg['servicePrices'] is Map
        ? Map<String, Object?>.from(cfg['servicePrices'] as Map)
        : <String, Object?>{};

    Widget itemRow(Widget content, {required List<Widget> actions}) =>
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: BrandColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BrandColors.line),
          ),
          child: Row(
            children: [
              Expanded(child: content),
              ...actions,
            ],
          ),
        );

    return Column(
      children: [
        // ── العيادات (إعادة تسمية متعاقبة + حذف + إضافة) ──
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('العيادات'),
              for (var i = 0; i < clinics.length; i++)
                editingClinicIdx == i
                    ? itemRow(
                        TextField(
                          key: const Key('clinic-rename-input'),
                          controller: renameClinicCtl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        actions: [
                          TextButton(
                            key: const Key('clinic-rename-save'),
                            onPressed: () => _confirmRenameClinic(i, clinics),
                            child: const Text(
                              'حفظ',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => editingClinicIdx = null),
                            child: const Text(
                              'إلغاء',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      )
                    : itemRow(
                        Text(
                          clinics[i],
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        actions: [
                          IconButton(
                            key: Key('clinic-rename-$i'),
                            tooltip: 'إعادة تسمية',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: BrandColors.brandIcon,
                            ),
                            onPressed: () => setState(() {
                              editingClinicIdx = i;
                              renameClinicCtl.text = clinics[i];
                            }),
                          ),
                          IconButton(
                            key: Key('clinic-del-$i'),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: BrandColors.red,
                            ),
                            onPressed: () =>
                                _removeItem(const ['clinics'], clinics[i]),
                          ),
                        ],
                      ),
              const SizedBox(height: 4),
              _inputSave(
                const Key('new-clinic-input'),
                newClinicCtl,
                'اسم عيادة جديدة',
                saveKey: const Key('add-clinic'),
                () {
                  final v = newClinicCtl.text.trim();
                  if (v.isEmpty) return;
                  // المرحلة ب — حد العيادات: لا تجاوز max_clinics (0 = بلا حدّ).
                  final max = ref.read(licenseServiceProvider).cachedMaxClinics();
                  if (max > 0 && clinics.length >= max) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'خطتك تسمح بـ$max '
                          '${max == 1 ? 'عيادة واحدة' : 'عيادات'} فقط. '
                          'رقِّ خطتك لإضافة المزيد.',
                        ),
                      ),
                    );
                    return;
                  }
                  _addItem(const ['clinics'], v);
                  newClinicCtl.clear();
                },
              ),
            ],
          ),
        ),

        // ── المعالجات (سعر لكل معالجة) ──
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('المعالجات'),
              for (var i = 0; i < services.length; i++)
                itemRow(
                  Text(services[i], style: const TextStyle(fontSize: 12.5)),
                  actions: [
                    SizedBox(
                      width: 74,
                      child: TextField(
                        key: Key('svc-price-${services[i]}'),
                        controller: _svcPriceCtl(
                          services[i],
                          prices[services[i]],
                        ),
                        focusNode: _svcPriceFocus(services[i]),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 11.5),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'السعر',
                        ),
                        // م55 — اللمس خارج الحقل على الهاتف لا يُفقده
                        // التركيز افتراضياً: نُفقده صراحةً فيمر الحفظ
                        // بمستمع فقد التركيز نفسه (مسار حفظ واحد).
                        onTapOutside: (_) =>
                            svcPriceFocusNodes[services[i]]?.unfocus(),
                        onSubmitted: (_) => _commitSvcPrice(services[i]),
                      ),
                    ),
                    // م143 — «تركيبات» مقفولةٌ ضد الحذف (بلا زر حذف): حذفُها
                    // يبثّ شاهدَ قبرٍ لكل الأجهزة فيمحو افتراضاً لازماً.
                    // سعرُها يبقى قابلاً للتعديل (حقل السعر أعلاه)، وباقي
                    // المعالجات تُحذف بحرّية.
                    if (!_kLockedServices.contains(services[i]))
                      IconButton(
                        key: Key('svc-del-$i'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: BrandColors.red,
                        ),
                        onPressed: () =>
                            _removeItem(const ['services'], services[i]),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              _inputSave(
                const Key('new-service-input'),
                newServiceCtl,
                'اسم معالجة جديدة',
                saveKey: const Key('add-service'),
                () {
                  final v = newServiceCtl.text.trim();
                  if (v.isEmpty) return;
                  _addItem(const ['services'], v);
                  newServiceCtl.clear();
                },
              ),
              Text(
                'السعر يملأ قيمة السجل تلقائياً عند اختيار المعالجة — '
                'يُحفظ تلقائياً بمجرد مغادرة الحقل',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
            ],
          ),
        ),

        // ── نظام «التحاليل» (دخل مخبري خاص بالعيادة، معزول مالياً) ──
        // بطاقةٌ بنمط المعالجات: اسم + سعر + مفتاح تفعيل + حذف لكل تحليل،
        // وحقل إضافة. كل عنصرٍ خريطةٌ بمعرّفٍ ثابت (لا قبور عند التعديل).
        _analysesCard(cfg),

        // م34 — المعالجة الافتراضية المختارة في الواجهة الرئيسية (توأم
        // SettingsGeneral.saveDefaultTreatment): الفارغ = الأولى في القائمة.
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('المعالجة الافتراضية'),
              const SizedBox(height: 4),
              Text(
                'تُعبأ تلقائياً في نموذج الزيارة بالواجهة الرئيسية.',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final cfg = ref.watch(appConfigProvider);
                  final services = _list(cfg, 'services');
                  final cur = '${cfg['defaultTreatment'] ?? ''}';
                  final value = services.contains(cur) ? cur : '';
                  return DropdownButtonFormField<String>(
                    key: const Key('default-treatment-select'),
                    initialValue: value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text(
                          'الأولى في القائمة (الافتراضي)',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      for (final s in services)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      // v57 — ختم زمني متزامن + مسح «آخر اختيار» المحلي:
                      // الضبط الصريح يسري فوراً هنا وعلى كل الأجهزة
                      // (آخر الاختيار يفوز لاحقاً فقط إن كان أحدث منه).
                      final now = DateTime.now()
                          .toUtc()
                          .toIso8601String()
                          .substring(0, 19)
                          .replaceAll('T', ' ');
                      _update(
                        (c) => {
                          ...c,
                          'defaultTreatment': v ?? '',
                          'defaultTreatmentAt': now,
                        },
                      );
                      clearLastTreatment(ref.read(localDbProvider));
                      _snack('تم حفظ المعالجة الافتراضية');
                    },
                  );
                },
              ),
            ],
          ),
        ),

        // ── طرق الدفع ──
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('طرق الدفع'),
              for (var i = 0; i < payments.length; i++)
                itemRow(
                  Text(payments[i], style: const TextStyle(fontSize: 12.5)),
                  actions: [
                    // م143 — كاش/تحويل مقفولتان ضد الحذف (بلا زر حذف): حذفهما
                    // يبثّ شاهدَ قبرٍ لكل الأجهزة فيلغي طريقتَي دفعٍ افتراضيتين.
                    if (!_kLockedPayments.contains(payments[i]))
                      IconButton(
                        key: Key('pay-del-$i'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: BrandColors.red,
                        ),
                        onPressed: () =>
                            _removeItem(const ['payments'], payments[i]),
                      ),
                  ],
                ),
              // م143 — إضافة طرق الدفع موقوفةٌ حالياً: طرق الدفع محصورةٌ في
              // الافتراضين كاش/تحويل، فلا حقلَ إضافةٍ (يبقى المتحكّم للتفكيك).
              Text(
                'طرق الدفع محصورةٌ حالياً في كاش وتحويل.',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextEditingController _svcPriceCtl(String svc, Object? current) {
    final n = jsNumOr0(current);
    final want = n > 0 ? n.toStringAsFixed(0) : '';
    final ctl = svcPriceCtls.putIfAbsent(
      svc,
      () => TextEditingController(text: want),
    );
    // م55 — سعر وصل من الجهاز الآخر (مزامنة) يظهر في الحقل فوراً — كان
    // putIfAbsent يجمّد أول نص للأبد. التركيز يحمي مسودة المستخدم من
    // الدهس أثناء الكتابة.
    final focused = svcPriceFocusNodes[svc]?.hasFocus ?? false;
    if (!focused && ctl.text.trim() != want) ctl.text = want;
    return ctl;
  }

  /// م55 — عقدة تركيز الحقل: فقد التركيز (لمسة خارج الحقل، تنقل لحقل
  /// آخر، إخفاء لوحة المفاتيح) يمرّ على [_commitSvcPrice] فيُحفظ ما
  /// تغيّر فعلاً — الحفظ لم يعد رهين ضغطة Enter.
  FocusNode _svcPriceFocus(String svc) =>
      svcPriceFocusNodes.putIfAbsent(svc, () {
        final node = FocusNode(debugLabel: 'svc-price-$svc');
        node.addListener(() {
          if (!node.hasFocus) _commitSvcPrice(svc);
        });
        return node;
      });

  /// م55 — الالتزام الفعلي: يقارن نص الحقل بالمخزون ويكتب **فقط عند
  /// تغيّر حقيقي** — فلا إشعارات ولا صفوف مزامنة عبثية عند كل فقد تركيز.
  /// ui=false لمسار dispose (لا setState ولا إشعار بعد فك الشاشة).
  /// قراءة الإعدادات المركّبة عبر المرجع المحفوظ (آمن في dispose).
  Map<String, Object?> _readConfig() {
    final repos = _repos;
    if (repos == null) return const {};
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  void _commitSvcPrice(String svc, {bool ui = true}) {
    final ctl = svcPriceCtls[svc];
    if (ctl == null) return;
    final prices = _readConfig()['servicePrices'];
    final stored = jsNumOr0(prices is Map ? prices[svc] : null);
    if (jsNumOr0(ctl.text) == stored) return;
    _setSvcPrice(svc, ctl.text, ui: ui);
  }

  void _setSvcPrice(String svc, String val, {bool ui = true}) {
    final repos = _repos;
    if (repos == null) return;
    final cfg = _readConfig();
    final prices = cfg['servicePrices'] is Map
        ? Map<String, Object?>.from(cfg['servicePrices'] as Map)
        : <String, Object?>{};
    final n = jsNumOr0(val);
    if (n > 0) {
      prices[svc] = n;
    } else {
      prices.remove(svc);
    }
    // v30 — نمرّر اللقطة الأساس (كما في _update): يُكتب صف السعر المتغيّر
    // فقط، فلا تُدهس أسعار عدّلها جهاز آخر بين القراءة والحفظ.
    repos.settings.set('app.config', {
      ...cfg,
      'servicePrices': prices,
    }, configBase: cfg);
    _configRev?.state++;
    if (!ui || !mounted) return;
    setState(() {});
    _snack(n > 0 ? 'حُفظ سعر «$svc»' : 'أُزيل سعر «$svc»');
  }

  // ── نظام «التحاليل الثلاثية» — بطاقة الإعدادات ────────────────────────────

  /// يُبذر متحكمَي السعر والمدة من المخزون ويتحدّثان بالمزامنة إلا أثناء
  /// الكتابة (بنمط _svcPriceCtl تماماً).
  void _seedTriAnalPrice(JMap cfg) {
    final nn = triAnalysesPrice(cfg);
    final want = nn > 0 ? nn.toStringAsFixed(0) : '';
    if (!triAnalPriceFocus.hasFocus && triAnalPriceCtl.text.trim() != want) {
      triAnalPriceCtl.text = want;
    }
    // م149 — المدة بالأشهر (الافتراضي 6؛ 0 = القاعدة معطّلة).
    final wantR = triRepeatMonths(cfg).toInt().toString();
    if (!triAnalRepeatFocus.hasFocus &&
        triAnalRepeatCtl.text.trim() != wantR) {
      triAnalRepeatCtl.text = wantR;
    }
  }

  /// يُسجّل مستمعَي تركيز «التحاليل الثلاثية» مرةً واحدةً في الجلسة —
  /// يُستدعى من build أول مرة تُبنى فيها الحقول (لا putIfAbsent هنا
  /// فالعقد ثابتة لا خريطة).
  bool _triAnalFocusListened = false;
  void _ensureTriAnalFocusListener() {
    if (_triAnalFocusListened) return;
    _triAnalFocusListened = true;
    // مغادرة الحقل = التزام القيمة تلقائياً (توأم svc-price).
    triAnalPriceFocus.addListener(() {
      if (!triAnalPriceFocus.hasFocus) _commitTriAnalPrice();
    });
    triAnalRepeatFocus.addListener(() {
      if (!triAnalRepeatFocus.hasFocus) _commitTriAnalRepeat();
    });
  }

  /// يكتب خريطة التحاليل الثلاثية {'price','enabled','repeatMonths'} تحت
  /// kTriAnalysesCfgKey عبر آلية _update نفسها لمفاتيح config البسيطة —
  /// الحقول الثلاثة تُكتب معاً دوماً فلا يُسقط كاتبٌ حقلَ الآخر.
  void _writeTriAnal({
    required num price,
    required bool enabled,
    required num repeatMonths,
  }) {
    _update(
      (c) => {
        ...c,
        kTriAnalysesCfgKey: {
          'price': price,
          'enabled': enabled,
          'repeatMonths': repeatMonths,
        },
      },
    );
  }

  /// يلتزم بسعر التحاليل الثلاثية عند تغيّرٍ حقيقي فقط (توأم _commitSvcPrice).
  void _commitTriAnalPrice({bool ui = true}) {
    final cfg = _readConfig();
    final stored = triAnalysesPrice(cfg);
    final now = jsNumOr0(triAnalPriceCtl.text);
    if (now == stored) return;
    final repos = _repos;
    if (repos == null) return;
    repos.settings.set(
      'app.config',
      {
        ...cfg,
        kTriAnalysesCfgKey: {
          'price': now,
          'enabled': triAnalysesEnabled(cfg),
          'repeatMonths': triRepeatMonths(cfg),
        },
      },
      configBase: cfg,
    );
    _configRev?.state++;
    if (!ui || !mounted) return;
    setState(() {});
    _snack('حُفظ سعر «$kTriAnalysesName»');
  }

  /// م149 — يلتزم بمدة إعادة التحليل (بالأشهر) عند تغيّرٍ حقيقي فقط.
  /// السالب يُقصّ إلى صفر (صفر = القاعدة معطّلة صراحةً).
  void _commitTriAnalRepeat({bool ui = true}) {
    final cfg = _readConfig();
    final stored = triRepeatMonths(cfg).toInt();
    var now = jsNumOr0(triAnalRepeatCtl.text).toInt();
    if (now < 0) now = 0;
    if (now == stored) return;
    final repos = _repos;
    if (repos == null) return;
    repos.settings.set(
      'app.config',
      {
        ...cfg,
        kTriAnalysesCfgKey: {
          'price': triAnalysesPrice(cfg),
          'enabled': triAnalysesEnabled(cfg),
          'repeatMonths': now,
        },
      },
      configBase: cfg,
    );
    _configRev?.state++;
    if (!ui || !mounted) return;
    setState(() {});
    _snack(
      now > 0
          ? 'حُفظت مدة إعادة التحليل: $now أشهر'
          : 'أُلغيت قاعدة مدة إعادة التحليل',
    );
  }

  /// بطاقة «التحاليل الثلاثية» — تحليلٌ واحدٌ ثابتُ الاسم بسعرٍ ومفتاح تفعيل.
  Widget _analysesCard(JMap cfg) {
    _ensureTriAnalFocusListener();
    _seedTriAnalPrice(cfg);
    final enabled = triAnalysesEnabled(cfg);
    final storedPrice = triAnalysesPrice(cfg);

    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان بطاقة التحاليل الثلاثية.
          _secH(kTriAnalysesName),
          const SizedBox(height: 8),
          // سطر السعر ومفتاح التفعيل في صف واحد.
          Row(
            children: [
              // حقل السعر الرقمي — يلتزم عند الإرسال وفقدان التركيز.
              SizedBox(
                width: 110,
                child: TextField(
                  key: const Key('tri-anal-price'),
                  controller: triAnalPriceCtl,
                  focusNode: triAnalPriceFocus,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'السعر',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  // اللمس خارج الحقل يُفقده التركيز فيمر مستمع الالتزام.
                  onTapOutside: (_) => triAnalPriceFocus.unfocus(),
                  onSubmitted: (_) => _commitTriAnalPrice(),
                ),
              ),
              const SizedBox(width: 12),
              // اسم التحليل الثابت (للعرض فقط — لا يُعدَّل).
              Expanded(
                child: Text(
                  kTriAnalysesName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // مفتاح التفعيل — يكتب الحقول الثلاثة معاً عبر _writeTriAnal.
              Switch(
                key: const Key('tri-anal-enabled'),
                value: enabled,
                activeTrackColor: BrandColors.brand600,
                onChanged: (v) => _writeTriAnal(
                  price: storedPrice,
                  enabled: v,
                  repeatMonths: triRepeatMonths(cfg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // م149 — سطر مدة إعادة التحليل (بالأشهر) — الافتراضي 6، 0 يعطّل.
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  key: const Key('tri-anal-repeat'),
                  controller: triAnalRepeatCtl,
                  focusNode: triAnalRepeatFocus,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'أشهر',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onTapOutside: (_) => triAnalRepeatFocus.unfocus(),
                  onSubmitted: (_) => _commitTriAnalRepeat(),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'المدة المسموح بها لإعادة التحليل (بالأشهر)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // سطر توضيحي بنص المواصفة حرفياً.
          Text(
            'دخلٌ مخبري خاص بالعيادة — معزولٌ مالياً عن الأرباح والخزينة. '
            'تفعيلُ الزر يُظهر خيار التحاليل الثلاثية في شاشة الإضافة وملف '
            'المريض، وإيقافه يخفيه. المدة بالأشهر تمنع تكرار التحليل لنفس '
            'المريض قبل انقضائها (الافتراضي 6 — والقيمة 0 تُلغي القاعدة).',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2),
          ),
        ],
      ),
    );
  }

  void _confirmRenameClinic(int idx, List<String> clinics) {
    final newName = renameClinicCtl.text.trim();
    final oldName = clinics[idx];
    if (newName.isEmpty || newName == oldName) {
      setState(() => editingClinicIdx = null);
      return;
    }
    if (clinics.contains(newName)) {
      _snack('هذا الاسم موجود بالفعل');
      return;
    }
    renameClinicCascade(ref.read(reposProvider), oldName, newName);
    ref.read(configRevProvider.notifier).state++;
    ref.read(patientsRevProvider.notifier).state++;
    setState(() => editingClinicIdx = null);
    _snack('تم تغيير الاسم: $oldName ← $newName');
  }

  // ═══ 3) نسب الطبيب لكل عيادة ═══

  Widget _ratesBody(JMap cfg) {
    final clinics = _list(cfg, 'clinics');
    final services = _list(cfg, 'services');
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secH('نسب الطبيب لكل عيادة'),
          Text(
            'اختر عيادة لضبط نسبة الطبيب لكل معالجة على حِدة — تشمل '
            'المعالجات الافتراضية والمضافة والتركيبات. القيمة 0% مسموحة.',
            style: TextStyle(fontSize: 11, color: BrandColors.mut),
          ),
          const SizedBox(height: 8),
          if (clinics.isEmpty)
            Text(
              'لا توجد عيادات بعد — أضِف عيادة من قسم «العيادات والمعالجات».',
              style: TextStyle(fontSize: 11, color: BrandColors.mut2),
            )
          else
            for (final cli in clinics)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: Material(
                  color: BrandColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: BrandColors.line),
                  ),
                  child: ListTile(
                    key: Key('rates-card-$cli'),
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: Icon(
                      Icons.local_hospital_rounded,
                      size: 18,
                      color: BrandColors.brandIcon,
                    ),
                    title: Text(
                      cli,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${services.where((s) => !isProsthetic(s)).length} معالجة + التركيبات',
                      style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded, size: 18),
                    onTap: () => _openClinicRatesSheet(cli),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// اللوحة السفلية — نسبة لكل معالجة غير تركيبية + صف تركيبات مستقل.
  Future<void> _openClinicRatesSheet(String clinic) async {
    final cfg = ref.read(appConfigProvider);
    final services = [
      for (final s in _list(cfg, 'services'))
        if (!isProsthetic(s)) s,
    ];
    final ctls = {
      for (final s in services)
        s: TextEditingController(
          text: resolveDoctorPct(
            cfg,
            clinic: clinic,
            service: s,
          ).toStringAsFixed(0),
        ),
    };
    final prosCtl = TextEditingController(
      text: resolveDoctorPct(
        cfg,
        clinic: clinic,
        isPros: true,
      ).toStringAsFixed(0),
    );

    bool validPct(String v) {
      final n = num.tryParse(v);
      return n != null && n >= 0 && n <= 100;
    }

    // نسخة الكمبيوتر: محرر النسب حوار مركزي بدل الورقة السفلية.
    Widget ratesBody(BuildContext context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BrandColors.faint2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'نسب الطبيب — $clinic',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (services.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              'لا توجد معالجات — أضِفها من قسم «العيادات والمعالجات».',
                              style: TextStyle(
                                fontSize: 11,
                                color: BrandColors.mut2,
                              ),
                            ),
                          ),
                        for (final s in services)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                SizedBox(
                                  width: 92,
                                  child: TextField(
                                    key: Key('rate-input-$s'),
                                    controller: ctls[s],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      suffixText: '%',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'تركيبات',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 92,
                                child: TextField(
                                  key: const Key('rate-input-pros'),
                                  controller: prosCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: '%',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const Key('rates-save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.gold,
                          foregroundColor: BrandColors.brand900,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حفظ النسب'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    final ok = isDesktopUi(context)
        ? await showDesktopDialog<bool>(
            context,
            width: 480,
            builder: ratesBody,
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: BrandColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: ratesBody,
          );
    if (ok != true) return;

    for (final s in services) {
      if (!validPct(ctls[s]!.text)) {
        _snack('النسبة يجب أن تكون بين 0 و 100');
        return;
      }
    }
    if (!validPct(prosCtl.text)) {
      _snack('النسبة يجب أن تكون بين 0 و 100');
      return;
    }
    // الحفاظ على المعالجات القديمة غير المعروضة (الأصل لا يحذفها).
    _update((c) {
      final rates = c['clinicRates'] is Map
          ? Map<String, Object?>.from(c['clinicRates'] as Map)
          : <String, Object?>{};
      final clinicsMap = rates['clinics'] is Map
          ? Map<String, Object?>.from(rates['clinics'] as Map)
          : <String, Object?>{};
      final existing = clinicsMap[clinic] is Map
          ? Map<String, Object?>.from(clinicsMap[clinic] as Map)
          : <String, Object?>{};
      final treatments = existing['treatments'] is Map
          ? Map<String, Object?>.from(existing['treatments'] as Map)
          : <String, Object?>{};
      for (final s in services) {
        treatments[s] = jsNumOr0(ctls[s]!.text).clamp(0, 100);
      }
      clinicsMap[clinic] = {
        ...existing,
        'treatments': treatments,
        'prosthetics': jsNumOr0(prosCtl.text).clamp(0, 100),
      };
      rates['version'] = 1;
      rates['clinics'] = clinicsMap;
      return {...c, 'clinicRates': rates};
    });
    _snack('تم حفظ النسب');
  }

  // ═══ 4) نظام الحجز ═══

  Widget _bookingBody(JMap cfg) {
    final system = cfg['bookingSystem'] == 'queue' ? 'queue' : 'traditional';
    return Column(
      children: [
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('نوع نظام الحجز'),
              SegmentedButton<String>(
                key: const Key('booking-system'),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: 'traditional',
                    label: Text('النظام التقليدي'),
                  ),
                  ButtonSegment(value: 'queue', label: Text('نظام الدور')),
                ],
                selected: {system},
                onSelectionChanged: (v) =>
                    _update((c) => {...c, 'bookingSystem': v.first}),
              ),
              const SizedBox(height: 4),
              Text(
                'يمكن التبديل في أي وقت دون فقدان أي بيانات — كل نظام يحتفظ بسجلاته.',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
        _glass(
          child: Text(
            '🗑 تُحذف سجلات الأيام السابقة تلقائياً من الجهاز والسحابة في نهاية كل يوم — دون أي إعداد أو إذن.',
            style: TextStyle(fontSize: 11, color: BrandColors.mut, height: 1.6),
          ),
        ),
        // ═══ ساعات الدوام (النظام التقليدي) — تحكم مدى جدول المواعيد ═══
        // تظهر على المنصتين وتعبر app.config المتزامن؛ الافتراضي 09:00–21:00.
        // تستعملها الجدولة الأسبوعية المكتبية لرسم مدى الساعات، والهاتف
        // يقرؤها كمرجعٍ لأوقات العمل. مفتاحان نصّيان HH:MM.
        if (system == 'traditional')
          _glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _secH('ساعات الدوام'),
                Text(
                  'مدى ساعات العمل الذي يعرضه جدول المواعيد الأسبوعي.',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('workday-start'),
                        controller: workdayStartCtl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'بداية الدوام (HH:MM)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('workday-end'),
                        controller: workdayEndCtl,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'نهاية الدوام (HH:MM)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('save-workday'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.gold,
                      foregroundColor: BrandColors.brand900,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final s = _normHHMM(workdayStartCtl.text, '09:00');
                      final e = _normHHMM(workdayEndCtl.text, '21:00');
                      workdayStartCtl.text = s;
                      workdayEndCtl.text = e;
                      _update((c) => {
                            ...c,
                            'workdayStart': s,
                            'workdayEnd': e,
                          });
                      _snack('تم حفظ ساعات الدوام');
                    },
                    child: const Text('حفظ ساعات الدوام',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('حساب الوقت المتوقع'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('q-morning'),
                      controller: qMorningCtl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'بداية الصباحي (HH:MM)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const Key('q-evening'),
                      controller: qEveningCtl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'بداية المسائي (HH:MM)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('q-slot'),
                controller: qSlotCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'المدة لكل مريض (دقائق)',
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-queue-timing'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _update(
                      (c) => {
                        ...c,
                        'queueMorningStart': qMorningCtl.text.trim(),
                        'queueEveningStart': qEveningCtl.text.trim(),
                        'queueSlotMin': jsNumOr0(qSlotCtl.text) > 0
                            ? jsNumOr0(qSlotCtl.text)
                            : 15,
                      },
                    );
                    _snack('تم حفظ إعدادات الوقت');
                  },
                  child: const Text(
                    'حفظ إعدادات الوقت',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('رسالة الدور الجاهزة (واتساب / SMS)'),
              TextField(
                key: const Key('q-watpl'),
                controller: qWaCtl,
                maxLines: 3,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(isDense: true),
              ),
              const SizedBox(height: 4),
              Text(
                'المتغيرات: {name} الاسم · {center} المركز · {clinic} العيادة · {time} الوقت المتوقع',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-queue-tpl'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _update((c) => {...c, 'queueWaTemplate': qWaCtl.text});
                    _snack('تم حفظ الرسالة');
                  },
                  child: const Text(
                    'حفظ الرسالة',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══ 5) الحماية والتأكيدات ═══

  /// م97 — البوابة الموحّدة للمفتاحين (القفل عند الفتح + البصمة):
  /// كلاهما مطفأٌ افتراضاً، وتشغيلُ أيٍّ منهما يستلزم «رمز قفل التطبيق»
  /// معيَّناً — إن لم يوجد يُفتح حوار تعيينٍ إجباري (الإلغاء = يبقى
  /// المفتاح مطفأً). ينطبق على الجميع: كلمةُ المرور مفتاحُ **الحساب**،
  /// والرمزُ مفتاحُ **الشاشة** — كالتطبيقات المعتادة. فلا يصل أحدٌ إلى
  /// قفلٍ أو بصمةٍ بلا رمزٍ يفتح بهما.
  ///
  /// يعيد `true` حين يجوز التفعيل (رمزٌ موجود أو عُيّن الآن).
  Future<bool> _requirePinForToggle(String featureLabel) async {
    final db = ref.read(localDbProvider);
    if (hasPinVerifier(db)) return true;
    final saved = await showPinSetupDialog(
      context,
      db: db,
      reason: PinSetupReason.settings,
    );
    if (!mounted) return false;
    if (!saved) {
      _snack('تعيين رمز القفل شرطُ تفعيل «$featureLabel»');
    }
    return saved;
  }

  Future<void> _setLockOnStartGated(bool enable) async {
    final db = ref.read(localDbProvider);
    if (!enable) {
      setState(() {
        _lockOnStart = false;
        setLockOnStart(db, false);
      });
      return;
    }
    final ok = await _requirePinForToggle('القفل عند فتح التطبيق');
    if (!mounted) return;
    setState(() {
      _lockOnStart = ok;
      if (ok) setLockOnStart(db, true);
    });
  }

  Future<void> _setBiometricGated(bool enable) async {
    final db = ref.read(localDbProvider);
    if (!enable) {
      setState(() {
        _biometric = false;
        setBiometricEnabled(db, false);
      });
      return;
    }
    final ok = await _requirePinForToggle('الدخول بالبصمة');
    if (!mounted) return;
    setState(() {
      _biometric = ok;
      if (ok) setBiometricEnabled(db, true);
    });
  }

  Widget _protectBody(JMap cfg) {
    final dc = _dc(cfg);
    final db = ref.read(localDbProvider);
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // م87 — قفل الدخول والبصمة (تفضيلات محليّة لكل جهاز، لا تُزامَن).
          _secH('قفل الدخول'),
          _toggleRow(
            'القفل عند فتح التطبيق',
            'يطلب رمز الفتح عند كل فتحٍ للتطبيق (يُنصح به بشدّة). '
                'إطفاؤه يجعل الفتح مباشراً بلا رمزٍ على هذا الجهاز.',
            _lockOnStart,
            (v) => _setLockOnStartGated(v),
            key: const Key('set-lock-on-start'),
          ),
          _toggleRow(
            'الدخول بالبصمة',
            'فتحٌ أسرع للقفل ببصمة الجهاز. يتطلّب تعيين رمز قفلٍ أولاً، '
                'ويبقى الرمز متاحاً دائماً كبديل.',
            _biometric,
            (v) => _setBiometricGated(v),
            key: const Key('set-biometric'),
          ),
          // م91/٤ — «رمز قفل التطبيق»: بندٌ لمن دخل بلا كلمة مرور (Google)
          // أو من عيّن رمزاً سابقاً. صاحبُ كلمة المرور لا يراه إطلاقاً —
          // كلمتُه هي مفتاح القفل كما كانت (انظر pinSettingsEntryVisible).
          if (pinSettingsEntryVisible(db))
            _glass(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPinVerifier(db)
                              ? 'تغيير رمز القفل'
                              : 'تعيين رمز القفل',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'رمزٌ رقمي يفتح قفل الشاشة على هذا الجهاز — '
                          'دخولُ Google لا يترك كلمةَ مرورٍ محلية تفتحه. '
                          'محليٌّ لا يُزامَن، ويُمسح عند الخروج.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: BrandColors.mut2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('set-pin-btn'),
                    onPressed: () async {
                      await showPinSetupDialog(
                        context,
                        db: db,
                        reason: PinSetupReason.settings,
                      );
                      if (mounted) {
                        setState(() {
                          /* حال الرمز تغيّر */
                        });
                      }
                    },
                    child: Text(hasPinVerifier(db) ? 'تغيير' : 'تعيين'),
                  ),
                ],
              ),
            ),
          // م91/٥ — التنبيه الصادق: القفل مفعَّل ولا وسيلةَ فتحٍ إطلاقاً ⇒
          // شاشةُ القفل القادمة خيارُها الوحيد الخروج. يُصارَح المالك هنا
          // قبل أن يقابلها، وبجواره زرُّ الخلاص الفوري.
          if (lockTrapWarningDue(db))
            Container(
              key: const Key('set-lock-warning'),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(245, 158, 11, .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color.fromRGBO(245, 158, 11, .35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'القفل مفعَّل لكن لا وسيلةَ فتحٍ على هذا الجهاز — '
                      'عند القفل لن يتاح إلا تسجيل الخروج. عيِّن رمزَ '
                      'قفلٍ الآن أو فعِّل البصمة.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('set-lock-warning-btn'),
                    onPressed: () async {
                      await showPinSetupDialog(
                        context,
                        db: db,
                        reason: PinSetupReason.settings,
                      );
                      if (mounted) {
                        setState(() {
                          /* التنبيه قد زال */
                        });
                      }
                    },
                    child: const Text('تعيين رمز الآن'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          _secH('تأكيد مزدوج قبل الحذف'),
          Text(
            'تحكم في عرض نافذة التأكيد مع العداد لكل نوع سجل — '
            'اضغط Enter بعد تعديل المدة',
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
          ),
          const SizedBox(height: 6),
          for (final (key, label, sub) in dcItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: BrandColors.mut2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: TextField(
                      key: Key('dc-dur-$key'),
                      controller: _dcDurCtl(key, dc['${key}Dur']),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5),
                      decoration: const InputDecoration(isDense: true),
                      onSubmitted: (v) => _saveDc(key, dur: jsNumOr0(v)),
                    ),
                  ),
                  Text(
                    ' ثانية',
                    style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                  ),
                  Switch(
                    key: Key('dc-on-$key'),
                    value: dc['${key}On'] == true,
                    onChanged: (v) => _saveDc(key, on: v),
                  ),
                ],
              ),
            ),
          // م143 — مهلة التراجع عن حذف الأشعة (تفضيلٌ محليّ لكل جهاز):
          // بعد الحذف يظهر شريطٌ فيه «تراجع» لهذه المدة قبل الحذف النهائي.
          // «إيقاف المؤقّت» (0) يجعل الحذف فورياً بلا مهلة تراجع.
          const SizedBox(height: 14),
          _secH('مهلة التراجع عن الحذف'),
          Text(
            'بعد حذف صورة أشعة يظهر شريطٌ يتيح التراجع خلال هذه المدة قبل '
            'الحذف النهائي. «إيقاف المؤقّت» يجعل الحذف فورياً.',
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'المدة قبل تثبيت الحذف',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  key: const Key('pref-delete-undo'),
                  initialValue: _kXrayDeleteUndoChoices.contains(_deleteUndoSecs)
                      ? _deleteUndoSecs
                      : _kXrayDeleteUndoDefault,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in _kXrayDeleteUndoChoices)
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          s == 0 ? 'إيقاف المؤقّت' : '$s ثوانٍ',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    final db = ref.read(localDbProvider);
                    setXrayDeleteUndoSecs(db, v);
                    setState(() => _deleteUndoSecs = v);
                    // نفس نبض التحديث الذي تستعمله بقية المفاتيح.
                    ref.read(configRevProvider.notifier).state++;
                    _snack(
                      v == 0
                          ? 'تم إيقاف مؤقّت التراجع — الحذف فوري'
                          : 'مهلة التراجع: $v ثوانٍ',
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  TextEditingController _dcDurCtl(String key, Object? current) {
    return dcDurCtls.putIfAbsent(
      key,
      () => TextEditingController(text: jsNumOr0(current).toStringAsFixed(0)),
    );
  }

  void _saveDc(String key, {bool? on, num? dur}) {
    _update((c) {
      final dc = _dc(c);
      if (on != null) dc['${key}On'] = on;
      if (dur != null) dc['${key}Dur'] = dur.clamp(0, 30);
      return {...c, 'dcConfirm': dc};
    });
  }

  // ═══ 6) الإشعارات ═══

  // ═══ المصروفات والرواتب ═══
  Widget _expensesBody(JMap cfg) {
    return Column(
      children: [
        _toggleRow(
          'ترحيل المتبقّي من الرواتب',
          'عند التفعيل: المتبقّي غير المسحوب يُرحَّل للشهر التالي ويتراكم منذ شهر '
              'انضمام الموظف. عند الإطفاء: يصفّر المتبقّي مطلع كل شهر (الوضع الحالي).',
          cfg['salaryCarryover'] == true,
          (v) => _update((c) => {...c, 'salaryCarryover': v}),
          key: const Key('set-salary-carryover'),
        ),
      ],
    );
  }

  Widget _notifBody(JMap cfg) {
    return Column(
      children: [
        _toggleRow(
          'تذكير المواعيد القادمة',
          'إشعار عند فتح التطبيق بمواعيد اليوم والغد',
          cfg['apptNotif'] != false,
          (v) => _update((c) => {...c, 'apptNotif': v}),
          key: const Key('set-apptnotif'),
        ),
        _toggleRow(
          'العودة التلقائية لتبويب الإضافة',
          'بعد حفظ موعد المتابعة',
          cfg['followUpAuto'] == true,
          (v) => _update((c) => {...c, 'followUpAuto': v}),
          key: const Key('set-followup'),
        ),
        _toggleRow(
          'حفظ حالة التبويب',
          'عند الخروج من السجلات أو المالية يحفظ مكانك',
          cfg['keepTabState'] == true,
          (v) => _update((c) => {...c, 'keepTabState': v}),
          key: const Key('set-keeptab'),
        ),
        // المرحلة هـ — إظهار/إخفاء زر تحميل التحديث في نافذة «تحديث متوفّر».
        // تفضيلٌ محليٌّ لكل جهاز (sync_meta، لا config المُزامَن) فلا يُكتب
        // عبر _update — نقرأ/نكتب مباشرةً ثم نُعيد البناء بـ setState.
        _glass(
          child: SwitchListTile(
            key: const Key('pref-show-update'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'إظهار زر تحديث التطبيق',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'عند توفّر تحديث، يظهر زر «تحميل التحديث» في التنبيه',
              style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
            ),
            value: showUpdateButtonPref(ref.read(localDbProvider)),
            onChanged: (v) {
              setShowUpdateButtonPref(ref.read(localDbProvider), v);
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  // ═══ 7) المظهر والعرض ═══

  // ═══ م-تكافؤ — «الموظفون والصلاحيات» قسمٌ رئيسي مستقل (قرار المالك) ═══
  // البطاقتان انتقلتا من _themeBody حيث كانتا مدفونتين تحت إعدادات
  // المظهر: تفعيل النظام (بالوضع الفردي) + إدارة المستخدمين والسجل
  // (للإدارة) + الإيقاف الآمن.
  Widget _staffBody(JMap cfg) {
    final hasUsers = StaffStore(ref.watch(reposProvider).settings).hasAnyUser;
    final isAdmin = staffIsAdmin(ref.watch(currentStaffProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // الوضع الفردي: تفعيل نظام الموظفين (اختياري — قرار المالك).
        if (!hasUsers)
          _glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _secH('نظام الموظفين والصلاحيات'),
                Text(
                  'الوضع الحالي: فردي — بلا تسجيل دخولٍ ولا كلمة مرور. '
                  'فعّل النظام إن كان يعمل معك موظفون، لتمنح كلَّ واحدٍ '
                  'حساباً بصلاحياتٍ محدودة.',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('enable-staff-system'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.brand600,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final done =
                          await showEnableStaffSystemDialog(context, ref);
                      if (done && mounted) nav.maybePop();
                    },
                    icon: const Icon(Icons.admin_panel_settings_rounded,
                        size: 18),
                    label: const Text('تفعيل نظام الموظفين'),
                  ),
                ),
              ],
            ),
          ),
        // م118 — المستخدمون والصلاحيات (للإدارة حصراً).
        if (isAdmin)
          _glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _secH('المستخدمون والصلاحيات'),
                Text(
                  'حسابات موظفي الاستعلامات وصلاحياتهم وكلمات مرورهم',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('open-staff-users'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.brand600,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StaffUsersScreen(),
                          ),
                        ),
                        icon: const Icon(
                          Icons.manage_accounts_rounded,
                          size: 18,
                        ),
                        label: const Text('إدارة المستخدمين'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // م120 — سجل التدقيق: من فعل ماذا ومتى (للإدارة فقط).
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('open-activity-log'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.goldDark,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActivityLogScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('سجل النشاط'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                // إيقاف النظام والعودة للوضع الفردي (آمنٌ للبيانات تماماً).
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('disable-staff-system'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BrandColors.red,
                      side: const BorderSide(color: BrandColors.red),
                    ),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final done =
                          await showDisableStaffSystemDialog(context, ref);
                      if (done && mounted) nav.maybePop();
                    },
                    icon: const Icon(Icons.person_off_rounded, size: 18),
                    label: const Text('إيقاف النظام — العودة للاستخدام الفردي'),
                  ),
                ),
              ],
            ),
          ),
        // موظفٌ غير إداري والنظام مفعّل: توضيحٌ بدل قسمٍ فارغ.
        if (hasUsers && !isAdmin)
          _glass(
            child: Row(
              children: [
                Icon(Icons.lock_person_rounded,
                    size: 18, color: BrandColors.mut2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'إدارة الموظفين والصلاحيات متاحة لحساب الإدارة فقط.',
                    style: TextStyle(fontSize: 11.5, color: BrandColors.mut),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _themeBody(JMap cfg) {
    final scale = ref.watch(fontScaleProvider);
    final themeMode = ref.watch(themeModeProvider);
    // م40 — قيم Vue الحرفية (fs-small/medium/large/xlarge).
    const sizes = [
      ('صغير', 0.85),
      ('عادي', 1.0),
      ('كبير', 1.2),
      ('أكبر', 1.45),
    ];
    final tabBottom = cfg['tabBarPosition'] == 'bottom';
    final fabVisible = cfg['fabVisible'] != false;
    final fabPos = '${jsOr(cfg['fabPosition'], 'center')}';

    Widget segBtn(String label, bool on, VoidCallback onTap, {Key? key}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: on
                ? FilledButton(
                    key: key,
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.gold,
                      foregroundColor: BrandColors.brand900,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onTap,
                    child: Text(label, style: const TextStyle(fontSize: 11.5)),
                  )
                : OutlinedButton(
                    key: key,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onTap,
                    child: Text(label, style: const TextStyle(fontSize: 11.5)),
                  ),
          ),
        );

    void metaSet(String key, String value) => ref.read(localDbProvider).execute(
      'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
      "VALUES (?, ?, datetime('now'))",
      [key, value],
    );

    return Column(
      children: [
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('حجم الخط'),
              Row(
                children: [
                  for (final (label, v) in sizes)
                    segBtn(label, (scale - v).abs() < 0.01, () {
                      metaSet('dental_font_size', '$v');
                      ref.read(fontScaleProvider.notifier).state = v;
                    }, key: Key('font-$label')),
                ],
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('المظهر'),
              Row(
                children: [
                  segBtn('فاتح', themeMode == 'light', () {
                    metaSet('dental_theme', 'light');
                    ref.read(themeModeProvider.notifier).state = 'light';
                  }, key: const Key('theme-light')),
                  segBtn('داكن', themeMode == 'dark', () {
                    metaSet('dental_theme', 'dark');
                    ref.read(themeModeProvider.notifier).state = 'dark';
                  }, key: const Key('theme-dark')),
                ],
              ),
            ],
          ),
        ),
        // (قرار المالك — نسخة الكمبيوتر): خيار «تبويبات أعلى/أسفل» خاص
        // بالهاتف — يُحذف من إعدادات الكمبيوتر فقط (الشريط الجانبي بديله)
        // ويبقى في الهاتف كما هو حرفياً.
        if (!isDesktopUi(context))
          _glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _secH('موقع شريط التبويبات'),
                Text(
                  'تحديد مكان شريط التبويبات (الرئيسية ← الحجوزات): في الأعلى أو في الأسفل',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    segBtn(
                      'أعلى',
                      !tabBottom,
                      () => _update((c) => {...c, 'tabBarPosition': 'top'}),
                      key: const Key('tabbar-top'),
                    ),
                    segBtn(
                      'أسفل',
                      tabBottom,
                      () => _update((c) => {...c, 'tabBarPosition': 'bottom'}),
                      key: const Key('tabbar-bottom'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        // م100 — نظام ترقيم الأسنان (Palmer/FDI): تفضيل عرضٍ مُزامَن لا يمسّ
        // تخزين الأسنان المحايد. الغياب = FDI (ISO 3950، الأوسع عالمياً).
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('نظام ترقيم الأسنان'),
              Text(
                'طريقة عرض رقم السن في المخطط والتقارير — Palmer '
                '(رقم داخل زاوية الربع) أو FDI (رقمان حسب ISO 3950). '
                'لا يغيّر أي بيانات محفوظة، ويُطبَّق على أجهزة العيادة كلها.',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  segBtn(
                    'FDI',
                    '${cfg['toothNotation'] ?? 'palmer'}' != 'palmer',
                    () => _update((c) => {...c, 'toothNotation': 'fdi'}),
                    key: const Key('notation-fdi'),
                  ),
                  segBtn(
                    'Palmer',
                    '${cfg['toothNotation'] ?? 'palmer'}' == 'palmer',
                    () => _update((c) => {...c, 'toothNotation': 'palmer'}),
                    key: const Key('notation-palmer'),
                  ),
                ],
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('الزر العائم (+)'),
              Text(
                'تحكم بموقع زر الإضافة السريع أو إخفائه',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'إظهار الزر العائم',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Switch(
                    key: const Key('fab-visible'),
                    value: fabVisible,
                    onChanged: (v) => _update((c) => {...c, 'fabVisible': v}),
                  ),
                ],
              ),
              if (fabVisible)
                Row(
                  children: [
                    segBtn(
                      'يمين',
                      fabPos == 'right',
                      () => _update((c) => {...c, 'fabPosition': 'right'}),
                      key: const Key('fab-right'),
                    ),
                    segBtn(
                      'وسط',
                      fabPos == 'center',
                      () => _update((c) => {...c, 'fabPosition': 'center'}),
                      key: const Key('fab-center'),
                    ),
                    segBtn(
                      'يسار',
                      fabPos == 'left',
                      () => _update((c) => {...c, 'fabPosition': 'left'}),
                      key: const Key('fab-left'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // م-تكافؤ — بطاقتا «نظام الموظفين» و«المستخدمون والصلاحيات»
        // انتقلتا من هنا إلى قسمٍ رئيسي مستقل «الموظفون والصلاحيات»
        // (_staffBody) — كانتا مدفونتين تحت إعدادات المظهر (قرار المالك).

        // ═══ م116 — العرض والتوقيت (قرار المالك) ═══
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('العرض والتوقيت'),
              Text(
                'نظام الوقت والأرقام وفاصل الفترة — تسري على كل التطبيق',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 8),
              Text(
                'نظام الوقت',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  segBtn(
                    '12 ساعة (ص/م)',
                    cfg['timeFormat'] != '24',
                    () => _update((c) => {...c, 'timeFormat': '12'}),
                    key: const Key('time-12'),
                  ),
                  segBtn(
                    '24 ساعة',
                    cfg['timeFormat'] == '24',
                    () => _update((c) => {...c, 'timeFormat': '24'}),
                    key: const Key('time-24'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'نظام الأرقام',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  segBtn(
                    'غربي 123',
                    cfg['digitStyle'] != 'arabic',
                    () => _update((c) => {...c, 'digitStyle': 'western'}),
                    key: const Key('digits-western'),
                  ),
                  segBtn(
                    'هندي ١٢٣',
                    cfg['digitStyle'] == 'arabic',
                    () => _update((c) => {...c, 'digitStyle': 'arabic'}),
                    key: const Key('digits-arabic'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'بداية الفترة المسائية (دخل اليوم)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const Key('period-cutoff'),
                      isExpanded: true,
                      initialValue: () {
                        final c = cfg['periodCutoffHour'];
                        final h = c is num ? c.toInt() : 12;
                        return (h >= 1 && h <= 23) ? h : 12;
                      }(),
                      decoration: const InputDecoration(isDense: true),
                      items: [
                        for (var h = 1; h <= 23; h++)
                          DropdownMenuItem(
                            value: h,
                            child: Text(
                              h < 12
                                  ? 'الساعة $h صباحاً'
                                  : h == 12
                                  ? 'الساعة 12 ظهراً'
                                  : 'الساعة ${h - 12} مساءً',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          _update((c) => {...c, 'periodCutoffHour': v ?? 12}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'ما قبلها «صباحي» وما بعدها «مسائي» في جدول دخل اليوم.',
                style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
        // م125 — ميزة شارة عدد الديون أُلغيت نهائياً (قرار المالك)؛
        // حُذف مفتاحها من هنا وحُذفت الشارة من بطاقة الديون.
      ],
    );
  }

  // ═══ 8) التخزين والنسخ الاحتياطي ═══

  /// م70 — بطاقة الأرشفة الباردة (سحابي + R2 فقط). المنطق كله في
  /// ColdArchive؛ هنا عرضٌ وأزرار لا غير.
  Widget _archiveGlass() {
    ref.watch(_archiveRev); // إعادة البناء بعد تبديل/تشغيل
    final arch = ref.read(coldArchiveProvider);
    if (arch == null) return const SizedBox.shrink();
    final last = arch.lastRunMs;
    final lastTxt = last == 0
        ? 'لم تعمل بعد'
        : 'آخر أرشفة: ${DateTime.fromMillisecondsSinceEpoch(last).toString().split(' ').first}';
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _secH('الأرشفة الباردة'),
          Row(
            children: [
              Expanded(
                child: Text(
                  'نقل القديم تلقائياً لتخزين أرخص',
                  style: TextStyle(fontSize: 12, color: BrandColors.mut),
                ),
              ),
              Switch(
                key: const Key('set-archive'),
                value: arch.enabled,
                onChanged: (v) {
                  arch.enabled = v;
                  ref.read(_archiveRev.notifier).state++;
                },
              ),
            ],
          ),
          // م94 — بلا أسماء بنيةٍ تحتية في نصوص الواجهة (تفضيل المالك).
          Text(
            'ما يتجاوز النافذة أدناه يُحزَم إلى التخزين السحابي ثم يُزال '
            'من قاعدة المزامنة — أجهزتك تحتفظ بنسخها كاملةً، ولا حذف قبل '
            'التأكد من وصول الحزمة ومن أن كل أجهزتك استلمت الصفوف. $lastTxt',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2),
          ),
          const SizedBox(height: 6),
          // م73 — النافذة الساخنة قابلة للاختيار. الأقصر أوفر تخزيناً؛
          // الأطول يجعل جهازاً جديداً يرى تاريخاً أوسع بلا استرجاع.
          Row(
            children: [
              Text(
                'الاحتفاظ على الخادم: ',
                style: TextStyle(fontSize: 12, color: BrandColors.mut),
              ),
              Expanded(
                child: DropdownButton<int>(
                  key: const Key('archive-window'),
                  isExpanded: true,
                  isDense: true,
                  value: arch.windowDays,
                  items: const [
                    DropdownMenuItem(value: 90, child: Text('٣ أشهر (الأوفر)')),
                    DropdownMenuItem(value: 180, child: Text('٦ أشهر')),
                    DropdownMenuItem(value: 365, child: Text('سنة كاملة')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    arch.windowDays = v;
                    ref.read(_archiveRev.notifier).state++;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('archive-now'),
                  onPressed: () async {
                    _snack('جاري الأرشفة…');
                    final r = await arch.run(manual: true);
                    ref.read(_archiveRev.notifier).state++;
                    _snack(r.ok ? r.reason : 'لم تكتمل: ${r.reason}');
                  },
                  icon: const Icon(Icons.archive_rounded, size: 15),
                  label: const Text(
                    'أرشفة الآن',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('archive-restore'),
                  onPressed: () async {
                    _snack('جاري الاسترجاع من الأرشيف…');
                    final r = await arch.restore();
                    // ترطيب صفوف يستوجب تحديث الإسقاطات (كما بعد السحب).
                    ref.read(patientsRevProvider.notifier).state++;
                    ref.read(configRevProvider.notifier).state++;
                    ref.read(_archiveRev.notifier).state++;
                    _snack(r.reason);
                  },
                  icon: const Icon(Icons.unarchive_rounded, size: 15),
                  label: const Text(
                    'استرجاع الأرشيف',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'الاسترجاع للجهاز الجديد: يملأ الناقص من الأرشيف ولا يمسّ '
            'الأحدث محلياً.',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2),
          ),
        ],
      ),
    );
  }

  Widget _storageBody(JMap cfg) {
    return Column(
      children: [
        // م134 — بطاقة حصة تخزين صور الأشعة (المرحلة ٣): شريط الاستهلاك
        // وتحذيرات 80/90/100٪. تُعرض في الوضع السحابي فقط (الحصة تُدار سحابياً).
        if (ref.read(cloudConfigProvider) != null) _StorageQuotaCard(),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('المزامنة'),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'مزامنة تلقائية',
                      style: TextStyle(fontSize: 12, color: BrandColors.mut),
                    ),
                  ),
                  Switch(
                    key: const Key('set-autosync'),
                    value: cfg['autoSync'] != false,
                    onChanged: (v) {
                      _update((c) => {...c, 'autoSync': v});
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => applyAutoSync(ref),
                      );
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'كل: ',
                    style: TextStyle(fontSize: 12, color: BrandColors.mut),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('syncmin-input'),
                      controller: syncMinCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '30',
                      ),
                    ),
                  ),
                  Text(
                    ' دقيقة ',
                    style: TextStyle(fontSize: 12, color: BrandColors.mut),
                  ),
                  FilledButton(
                    key: const Key('syncmin-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.gold,
                      foregroundColor: BrandColors.brand900,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final v = jsNumOr0(syncMinCtl.text);
                      _update((c) => {...c, 'syncMin': v < 5 ? 5 : v});
                      _snack('تم الحفظ');
                    },
                    child: const Text('حفظ', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // م54 — المعنى الصحيح للفاصل: سقف الخمول. النشاط (كتابة
              // محلية/تغيير وارد/فتح التطبيق) يزامن خلال ثوانٍ دائماً.
              Text(
                'أقصى فاصل بين مزامنتين في الخمول — أي نشاط أو فتح '
                'للتطبيق يزامن فوراً خلال ثوانٍ',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('sync-now'),
                  onPressed: () async {
                    await ref.read(syncUiProvider.notifier).manualSync();
                    _snack('اكتملت المزامنة');
                  },
                  icon: const Icon(Icons.sync_rounded, size: 15),
                  label: const Text(
                    'مزامنة الآن',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        // م70 — الأرشفة الباردة: تُعرض بالوضع السحابي مع R2 فقط (خارجه
        // يكون coldArchive = null فلا بطاقة — لا مفاتيح ميتة في الواجهة).
        if (ref.watch(coldArchiveProvider) != null) _archiveGlass(),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('النسخ الاحتياطي'),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('export-excel'),
                  onPressed: _exportExcel,
                  icon: const Icon(Icons.table_chart_rounded, size: 15),
                  label: const Text(
                    'تصدير Excel',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('export-json'),
                  onPressed: _exportJson,
                  icon: const Icon(Icons.description_rounded, size: 15),
                  label: const Text(
                    'نسخة محلية JSON',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('import-json'),
                  onPressed: _importJson,
                  icon: const Icon(Icons.restore_rounded, size: 15),
                  label: const Text(
                    'استعادة JSON',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _exportsDir {
    final d = Directory(p.join(ref.read(dbDirProvider), 'exports'));
    d.createSync(recursive: true);
    return d.path;
  }

  Future<void> _exportExcel() async {
    try {
      final cfg = ref.read(appConfigProvider);
      final name = '${jsOr(cfg['centerName'], 'export')}';
      final path = p.join(
        _exportsDir,
        'dental_${name}_${getCurrentDate()}.xlsx',
      );
      File(path).writeAsBytesSync(buildBackupXlsx(ref.read(reposProvider)));
      _snack('تم تصدير Excel — $path');
    } catch (e) {
      _snack('خطأ في التصدير: $e');
    }
  }

  Future<void> _exportJson() async {
    try {
      final path = p.join(
        _exportsDir,
        'dental_backup_${getCurrentDate()}.json',
      );
      File(path).writeAsStringSync(buildBackupJson(ref.read(reposProvider)));
      _snack('تم تصدير النسخة الاحتياطية — $path');
    } catch (e) {
      _snack('خطأ في التصدير: $e');
    }
  }

  Future<void> _importJson() async {
    final text = await ref.read(jsonPickProvider)();
    if (text == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة النسخة الاحتياطية'),
        content: const Text(
          'استعادة النسخة الاحتياطية ستستبدل جميع البيانات الحالية.\n\nمتأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('import-json-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final count = restoreBackupJson(ref.read(reposProvider), text);
      ref.read(configRevProvider.notifier).state++;
      ref.read(patientsRevProvider.notifier).state++;
      _seeded = false;
      setState(() {});
      _snack('تمت الاستعادة بنجاح — $count صفاً');
    } catch (_) {
      _snack('خطأ في قراءة الملف');
    }
  }

  // ═══ 9) قوالب واتساب ═══

  Widget _waBody(JMap cfg) {
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'استخدم {name} لاسم المريض و {center} لاسم العيادة',
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < waTpls.length; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BrandColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BrandColors.line),
              ),
              child: Column(
                children: [
                  TextField(
                    key: Key('watpl-lbl-$i'),
                    controller: waTpls[i]['lbl'],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'اسم القالب',
                    ),
                  ),
                  TextField(
                    key: Key('watpl-msg-$i'),
                    controller: waTpls[i]['msg'],
                    maxLines: 3,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'نص الرسالة...',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: Key('watpl-del-$i'),
                      style: TextButton.styleFrom(
                        foregroundColor: BrandColors.red,
                      ),
                      onPressed: () => setState(() {
                        waTpls[i]['lbl']!.dispose();
                        waTpls[i]['msg']!.dispose();
                        waTpls.removeAt(i);
                      }),
                      child: const Text(
                        '✕ حذف القالب',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('add-watpl'),
              onPressed: () => setState(
                () => waTpls.add({
                  'lbl': TextEditingController(),
                  'msg': TextEditingController(),
                }),
              ),
              child: const Text(
                '+ إضافة قالب جديد',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('save-watpls'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.gold,
                foregroundColor: BrandColors.brand900,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                _update(
                  (c) => {
                    ...c,
                    'waTemplates': [
                      for (final t in waTpls)
                        if (t['lbl']!.text.trim().isNotEmpty ||
                            t['msg']!.text.trim().isNotEmpty)
                          {
                            'lbl': t['lbl']!.text.trim(),
                            'msg': t['msg']!.text.trim(),
                          },
                    ],
                  },
                );
                _snack('تم حفظ القوالب');
              },
              icon: const Icon(Icons.check_rounded, size: 15),
              label: const Text('حفظ القوالب', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ 10) إعدادات المختبرات ═══

  Widget _labsBody(JMap cfg) {
    return Column(
      children: [
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('قائمة المختبرات'),
              for (var i = 0; i < labCtls.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: Key('lab-name-$i'),
                          controller: labCtls[i],
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'اسم المختبر',
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('lab-del-$i'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: BrandColors.red,
                        ),
                        onPressed: () => setState(() {
                          labCtls[i].dispose();
                          labCtls.removeAt(i);
                        }),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('new-lab-input'),
                      controller: newLabCtl,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'مختبر جديد...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const Key('add-lab'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final v = newLabCtl.text.trim();
                      if (v.isEmpty) return;
                      setState(() {
                        labCtls.add(TextEditingController(text: v));
                        newLabCtl.clear();
                      });
                    },
                    child: const Text(
                      '+ إضافة',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-labs'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _update(
                      (c) => {
                        ...c,
                        'labs': [
                          for (final ctl in labCtls)
                            if (ctl.text.trim().isNotEmpty) ctl.text.trim(),
                        ],
                      },
                    );
                    _snack('تم حفظ المختبرات');
                  },
                  child: const Text(
                    'حفظ المختبرات',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        _glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _secH('أنواع التركيبات'),
              for (var i = 0; i < labTypeCtls.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: Key('labtype-name-$i'),
                          controller: labTypeCtls[i].$1,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'اسم النوع',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          key: Key('labtype-price-$i'),
                          controller: labTypeCtls[i].$2,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'السعر',
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('labtype-del-$i'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: BrandColors.red,
                        ),
                        onPressed: () => setState(() {
                          labTypeCtls[i].$1.dispose();
                          labTypeCtls[i].$2.dispose();
                          labTypeCtls.removeAt(i);
                        }),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('new-labtype-name'),
                      controller: newLabTypeNameCtl,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'نوع جديد...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      key: const Key('new-labtype-price'),
                      controller: newLabTypePriceCtl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'السعر',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    key: const Key('add-labtype'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      final v = newLabTypeNameCtl.text.trim();
                      if (v.isEmpty) return;
                      setState(() {
                        labTypeCtls.add((
                          TextEditingController(text: v),
                          TextEditingController(
                            text: newLabTypePriceCtl.text.trim(),
                          ),
                        ));
                        newLabTypeNameCtl.clear();
                        newLabTypePriceCtl.clear();
                      });
                    },
                    child: const Text('+', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('save-labtypes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _update(
                      (c) => {
                        ...c,
                        'labTypes': [
                          for (final (nameCtl, priceCtl) in labTypeCtls)
                            if (nameCtl.text.trim().isNotEmpty)
                              {
                                'name': nameCtl.text.trim(),
                                'defaultPrice': jsNumOr0(priceCtl.text),
                              },
                        ],
                      },
                    );
                    _snack('تم حفظ الأنواع');
                  },
                  child: const Text(
                    'حفظ الأنواع',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══ تسجيل الخروج ═══

  /// منظومة الخروج الآمن — توأم SettingsModal + LogoutDialog حرفياً:
  ///   ١) الوضع السحابي وأوفلاين ⇒ منع الخروج (لا تُفقد بيانات غير متزامنة).
  ///   ٢) صور معلقة ⇒ حوار: رفع ثم خروج / حذف وخروج / إلغاء.
  ///   ٣) مزامنة قبل الخروج بشاشة حجب وسقف 12ث — فشلها يلغي الخروج.
  Future<void> _confirmLogout() async {
    final cloud = ref.read(cloudConfigProvider) != null;
    final online = ref.read(onlineProvider);
    final pending = ref.read(pendingXrayUploadsProvider);

    // ١) حارس الأوفلاين (الوضع السحابي فقط).
    if (cloud && !online) {
      _snack(
        'لا يوجد اتصال بالإنترنت — لن يتم تسجيل الخروج حتى لا تفقد بياناتك '
        'غير المتزامنة. اتصل بالإنترنت ثم أعد المحاولة',
      );
      return;
    }

    // ٢) صور معلقة ⇒ حوار الخيارات (توأم LogoutDialog).
    String action = 'confirm'; // confirm | upload | delete | cancel
    if (cloud && pending > 0) {
      action = await _pendingUploadsLogoutDialog(pending) ?? 'cancel';
      if (action == 'cancel' || !mounted) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تسجيل الخروج'),
          content: const Text(
            'هل أنت متأكد من تسجيل الخروج؟ سيتم مزامنة بياناتك قبل الخروج.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('logout-confirm'),
              style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    // نسخة الكمبيوتر (قرار المالك §ثالثاً): الخروج = إعادة ضبط مصنعي —
    // مسحٌ كامل لا رجعة فيه. في الوضع المحلي (بلا سحابة) لا نسخة تحفظ
    // البيانات، فالمسح فقدانٌ نهائي ⇒ تأكيدٌ مكتوب صريح قبله. الوضع
    // السحابي يمسح بعد المزامنة الموثقة (تجري داخل _runLogout).
    final factoryReset = isDesktopUi(context);
    if (factoryReset && !cloud) {
      final confirmed = await _confirmDestructiveWipe();
      if (confirmed != true || !mounted) return;
    }

    // ٣) تنفيذ الخروج بشاشة حجب (رفع/حذف الصور ثم مزامنة ثم خروج).
    await _runLogout(action, cloud: cloud, factoryReset: factoryReset);
  }

  /// نسخة الكمبيوتر — الوضع المحلي: تأكيد مكتوب صريح قبل المسح النهائي.
  /// يجب كتابة «احذف نهائياً» حرفياً كي يُفعَّل زرّ الحذف (توأم أنماط
  /// التأكيد المدمّر في الأنظمة الحرجة — لا نقرة واحدة تمحو عيادة).
  Future<bool?> _confirmDestructiveWipe() {
    final ctl = TextEditingController();
    const phrase = 'احذف نهائياً';
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setSt) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: BrandColors.red, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('خروج نهائي — مسح كل البيانات')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هذا الجهاز في الوضع المحلي — لا نسخة سحابية لبياناته. '
                'تسجيل الخروج هنا يمحو نهائياً: كل المرضى والسجلات والديون '
                'والمواعيد والصور والمصروفات والرواتب ومفتاح التشفير — '
                'بلا أي إمكانية للاستعادة.\n\nاكتب «$phrase» للتأكيد:',
                style: TextStyle(fontSize: 13, height: 1.7),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('wipe-confirm-field'),
                controller: ctl,
                autofocus: true,
                onChanged: (_) => setSt(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: phrase,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: const Key('wipe-confirm-btn'),
              style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.red),
              onPressed: ctl.text.trim() == phrase
                  ? () => Navigator.pop(dctx, true)
                  : null,
              child: const Text('امحُ واخرج'),
            ),
          ],
        ),
      ),
    );
  }

  /// حوار الصور المعلقة عند الخروج — رفع ثم خروج / حذف وخروج / إلغاء.
  Future<String?> _pendingUploadsLogoutDialog(int count) => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تسجيل الخروج'),
      content: Text(
        'لديك $count ${count == 1 ? 'صورة' : 'صور'} بانتظار الرفع.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: const Text('إلغاء'),
        ),
        TextButton(
          key: const Key('logout-delete-imgs'),
          onPressed: () => Navigator.pop(context, 'delete'),
          child: const Text(
            'حذف وخروج',
            style: TextStyle(color: BrandColors.red),
          ),
        ),
        FilledButton(
          key: const Key('logout-upload-imgs'),
          onPressed: () => Navigator.pop(context, 'upload'),
          child: const Text('رفع ثم خروج'),
        ),
      ],
    ),
  );

  Future<void> _runLogout(String action,
      {required bool cloud, bool factoryReset = false}) async {
    final navigator = Navigator.of(context);
    // شاشة حجب أثناء المعالجة (لا يمكن الإلغاء).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('جارٍ تجهيز الخروج...')),
          ],
        ),
      ),
    );
    var abort = false;
    try {
      final queue = ref.read(xrayUploadQueueProvider);
      if (action == 'delete') {
        // حذف الصور المعلقة محلياً ثم خروج مباشر.
        final store = ref.read(xrayStoreProvider);
        for (final x in ref.read(reposProvider).xrays.getPendingUploads()) {
          store.deleteXray('${x['id']}');
        }
        ref.read(xrayVersionProvider.notifier).state++;
      } else if (action == 'upload') {
        await queue?.drainNow();
        if (ref.read(pendingXrayUploadsProvider) > 0) {
          abort = true;
        }
      }
      // مزامنة قبل الخروج (سحابي فقط) بسقف 12 ثانية — فشلها يلغي الخروج.
      if (!abort && cloud) {
        final r = await ref
            .read(syncEngineProvider)
            .syncNow()
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () => throw Exception('timeout'),
            )
            .then((v) => v.ok)
            .catchError((_) => false);
        if (!r) abort = true;
      }
    } catch (_) {
      abort = true;
    }
    if (!mounted) return;
    if (abort) {
      navigator.pop(); // إغلاق شاشة الحجب — والبقاء في الإعدادات
      _snack('تعذّر إكمال المزامنة/الرفع — لم يتم تسجيل الخروج. حاول مجدداً');
      return;
    }
    // نسخة الكمبيوتر: المسح المصنعي الكامل **بعد** نجاح المزامنة أعلاه
    // (فلا تُفقد بياناتٌ غير متزامنة) و**قبل** تصفير حالة المصادقة. يُغلق
    // مقابض القاعدة والخزنة ويحذف الملفات والمفتاح والجلسة — انظر
    // factory_reset.dart. الهاتف لا يمر من هنا (factoryReset=false له).
    if (factoryReset) {
      try {
        await runFactoryReset(ref);
      } catch (e) {
        // المسح أفضل جهد: عطلٌ فيه لا يمنع الخروج (البيانات على الأقل
        // مشفَّرة، والمفتاح قد يبقى — يُبلَّغ في السجل عبر منقّي PHI).
        recordError(e, StackTrace.current, context: 'logout:factory-reset');
      }
    }
    // م95 — الخروج **قبل** أي إغلاق: كان الترتيب يغلق الإعدادات أولاً
    // فيرى المستخدم آخرَ واجهةٍ كان فيها (الصدفة) 300ms ثم تُستبدل بشاشة
    // الدخول — وميضٌ بلا معنى. الآن يتم الخروج وشاشةُ الحجب ما تزال فوق
    // الإعدادات (الجذر تحتها صار شاشةَ الدخول)، ثم تُزال المسارات كلها
    // حتى الجذر دفعةً واحدة — فيهبط من الإعدادات على الدخول مباشرة.
    // نفس نمط حذف الحساب (م94/account_section).
    await ref.read(authProvider.notifier).logout();
    navigator.popUntil((r) => r.isFirst);
  }
}

/// م134 — بطاقة حصة تخزين صور الأشعة (المرحلة ٣).
///
///  تعرض شريط الاستهلاك (المستهلك/الحصة) بتلوين العتبات 80/90/100٪ ورسالة
///  حالة صريحة. تجلب الحصة الحيّة من الخادم عند الفتح (أفضل جهد)، وتعمل من
///  المخبَّأ بلا اتصال. القياس من عدّاد الجهاز (storage_meter) لا من مسح
///  ملفات (تُحذف النسخة الكاملة بعد الرفع).
class _StorageQuotaCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_StorageQuotaCard> createState() => _StorageQuotaCardState();
}

class _StorageQuotaCardState extends ConsumerState<_StorageQuotaCard> {
  @override
  void initState() {
    super.initState();
    // تحديث الحصة من الخادم عند الفتح — ثم إعادة بناء لعرض الرقم الحيّ.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final meter = ref.read(storageMeterProvider);
      await meter.refreshQuota();
      if (mounted) setState(() {});
    });
  }

  (Color, String, IconData) _levelStyle(StorageLevel lvl) => switch (lvl) {
    StorageLevel.full => (
      BrandColors.red,
      'التخزين ممتلئ — احذف صوراً قديمة أو رقِّ الاشتراك لرفع صور جديدة.',
      Icons.error_rounded,
    ),
    StorageLevel.warn90 => (
      BrandColors.red,
      'اقترب التخزين من الامتلاء (فوق ٩٠٪).',
      Icons.warning_amber_rounded,
    ),
    StorageLevel.warn80 => (
      const Color(0xFFD97706),
      'التخزين تجاوز ٨٠٪ — يُنصح بحذف صور قديمة قريباً.',
      Icons.warning_amber_rounded,
    ),
    StorageLevel.ok => (
      BrandColors.brand600,
      'المساحة كافية.',
      Icons.check_circle_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    // نُعيد القراءة عند كل نبضة نسخة أشعة (رفع/حذف) فيتحدّث الشريط حيّاً.
    ref.watch(xrayVersionProvider);
    final StorageMeter meter = ref.read(storageMeterProvider);
    final used = meter.usedBytes;
    final quota = meter.quotaBytes;
    final ratio = meter.ratio;
    final (color, msg, icon) = _levelStyle(meter.level);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ترويسة القسم بنمط _secH (بطاقة مستقلة لا تصل دواله الخاصة).
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 14,
                  decoration: BoxDecoration(
                    color: BrandColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'حصة تخزين صور الأشعة',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${humanBytesAr(used)} من ${humanBytesAr(quota)}',
                  key: const Key('storage-quota-used'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}٪',
                key: const Key('storage-quota-pct'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              key: const Key('storage-quota-bar'),
              value: ratio,
              minHeight: 10,
              backgroundColor: BrandColors.line,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  msg,
                  key: const Key('storage-quota-msg'),
                  style: TextStyle(fontSize: 11.5, color: color, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'المتبقّي ${humanBytesAr((quota - used).clamp(0, quota))} · '
            '${meter.fileCount} صورة',
            style: TextStyle(fontSize: 11, color: BrandColors.mut),
          ),
        ],
      ),
    );
  }
}
