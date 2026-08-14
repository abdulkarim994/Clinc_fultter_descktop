/// بوابة ما بعد تسجيل الدخول — التوأم الحرفي لـ PostLoginGate.vue **بهويته
/// البصرية الكاملة** (login-bg + login-header-pattern + glass + pg-spinner
/// + wm-lines المتدرّجة من main.css):
///   • loading  : «يرجى الانتظار قليلاً...» (سحب الخادم قبل الحكم).
///   • setup    : إعداد أول مرة **إجباري** (اسم المركز/الطبيب + عيادة+).
///   • preparing: «يتم تجهيز حسابك لأول مرة».
///   • welcome  : ترحيب فاخر بأسطر متدرّجة الظهور (0/140/300/460ms).
///
/// القاعدة الإجبارية (onboarding_service): الرئيسية لا تفتح إلا بإعداد
/// مكتمل — بيانات صحيحة + علم دائم per-uid يصمد عبر إغلاق التطبيق والخروج.
///
/// م32 — نبضات إعادة القراءة عند فتح البوابة: بعد مسح تبديل الحساب كانت
/// ذاكرة الإعدادات المؤقتة (appConfigProvider وأخواتها) تبقى على بيانات
/// الحساب القديم فترحّب البوابة **بالاسم القديم** وتختم علم الإكمال للحساب
/// الجديد خطأً. الحل: قفز كل عدّادات النسخ عند أول إطار فتُقرأ القاعدة
/// النظيفة قبل أي حكم.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart' show BrandColors;
import '../../core/locked_services.dart'
    show kLockedServices, kVariablePriceLabel;
import 'license_service.dart'
    show LicenseGateResult, LicenseSnapshot, LicenseException;
import 'idle_lock.dart' show IdleLockScope, lockedProvider, hasLockVerifier;
import 'lock_prefs.dart' show biometricEnabled, lockOnStartEnabled;
import '../../data/db/local_db.dart' show LocalDb;
import '../appointments/appointments_tab.dart'
    show apptRevProvider, followUpDraftProvider;
import '../finance/finance_screen.dart'
    show financeRevProvider, financeSectionProvider;
import '../patients/patients_tab.dart'
    show
        addVisitDraftProvider,
        openClinicProvider,
        patientSearchProvider,
        patientsRevProvider;
import '../queue/queue_screen.dart' show queueRevProvider;
import '../notifications/notification_center.dart' show showPendingNotifications;
import '../shell/app_shell.dart';
import 'onboarding_service.dart';

// ثوابت توقيت الترحيب — حرفياً من الأصل (تنسيق الحركة فقط؛ التحميل حقيقي).
const _fadeInDelay = Duration(milliseconds: 300); // FADE_IN_DELAY_MS
const _minRead = Duration(milliseconds: 2800); // MIN_READ_MS
const _fadeOut = Duration(milliseconds: 500); // FADE_OUT_MS

// ── لوحة الهوية (main.css :root) ────────────────────────────────────────────
const _goldL = Color(0xFFE4CA85); // --gold-l
const _gold = Color(0xFFC9A24B); // --gold
const _goldD = Color(0xFF9C7A2E); // --gold-d
const _brand700 = Color(0xFF114A38); // --brand-700
const _brand = Color(0xFF1B5E47); // --brand
const _ink = Color(0xFF0F2A20); // --ink
const _softRed = Color(0xFFF87171); // pg-del

// م135 — activation: حالةٌ سادسة قبل setup — شاشة تفعيل الاشتراك حين يمنع
// الترخيصُ الدخول (منتهٍ/محظور/مجمَّد/بلا اشتراك) والإجبارُ مفعَّل.
enum _GateState { loading, activation, setup, preparing, welcome, done }

class PostLoginGate extends ConsumerStatefulWidget {
  const PostLoginGate({super.key});

  @override
  ConsumerState<PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends ConsumerState<PostLoginGate>
    with WidgetsBindingObserver {
  _GateState _state = _GateState.loading;
  bool _welcomeOut = false;
  // المرحلة هـ — لقطةٌ واحدةٌ لتسلسل إشعارات فتح التطبيق: تشتعل مرةً فقط
  // عند أول عبورٍ لحالة `done` في عمر هذه البوابة (لا تتكرر مع إعادة البناء).
  bool _notifShown = false;
  // ظهور الأسطر الأربعة المتدرّج (wm-line 1..4).
  final List<bool> _lineIn = [false, false, false, false];
  String _centerName = '';
  String _greetName = ''; // م88 — اسم Google لسطر الترحيب.
  String _formError = '';
  bool _saving = false;

  // م135 — حالة شاشة التفعيل.
  LicenseSnapshot? _license;
  final _codeCtl = TextEditingController();
  bool _activating = false;
  String _activationError = '';

  final _centerCtl = TextEditingController();
  final List<TextEditingController> _clinicCtls = [TextEditingController()];

  // ═══ م180/ج — معالج الإعداد ثلاثي الخطوات (قرار المالك) ═══
  // 0 = المركز والعيادات · 1 = المعالجات وأسعارها · 2 = المختبرات وأنواعها.
  // «حفظ ومتابعة» يكتب خطوته في app.config فوراً ثم ينتقل؛ و«حفظ وإنهاء»
  // في الأخيرة يختم علم الإكمال ويتابع لشاشة البدء بالسلوك القديم نفسه.
  int _step = 0;

  /// معالجات الخطوة ٢: (الاسم، السعر) — مبذورة بالافتراضية القائمة.
  /// م181 — «تركيبات» لم تعد صفاً حراً هنا: معالجة نظامية مثبتة تُعرض
  /// صفاً مقفلاً (بلا اسم يحرَّر ولا سعر ولا حذف) وتُكتب دائماً عند
  /// الحفظ — سعرها متغيّر بطبيعته (وحدات × سعر نوع المختبر لكل حالة).
  final List<(TextEditingController, TextEditingController)> _svcCtls = [
    (TextEditingController(text: 'حشو عصب أمامي'), TextEditingController()),
    (TextEditingController(text: 'حشو عصب خلفي'), TextEditingController()),
  ];

  /// مختبرات الخطوة ٣: لكل مختبر اسمٌ وقائمة أنواع (اسم، سعر).
  final List<
      ({
        TextEditingController name,
        List<(TextEditingController, TextEditingController)> types,
      })> _labCtls = [];

  @override
  void initState() {
    super.initState();
    // م54 — البوابة حية طوال الجلسة الموقّعة: مراقبة دورة الحياة منها
    // تجعل العودة من الخلفية تركل مزامنة فورية (انظر أدناه).
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  /// م54 — استئناف التطبيق = لحظة نظر المستخدم: دورة مزامنة فورية تلتقط
  /// ما أضافه الجهاز الآخر (معالجة/سعر/مريض) بدل انتظار نبضة الاستطلاع —
  /// مؤقتات Dart قد تتجمد في الخلفية على أندرويد فيطول الانتظار أكثر.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      kickPresenceSync(ref);
      // م135 — إعادة التحقق من الترخيص عند العودة: حظرٌ/تجميدٌ من اللوحة
      // أو انتهاءُ صلاحيةٍ يُغلق الوصول عند «التحقق التالي» (مطلب المالك)،
      // لكن فقط ونحن داخل الصدفة (done) — لا نقاطع إعداداً أو ترحيباً.
      if (_state == _GateState.done) _recheckLicenseOnResume();
    }
  }

  /// إعادة تقييم الترخيص خلفيّاً؛ فإن مُنع الآن نقفز لشاشة التفعيل.
  Future<void> _recheckLicenseOnResume() async {
    final snap = await ref.read(licenseServiceProvider).evaluate();
    if (!mounted) return;
    if (!snap.allowed) {
      setState(() {
        _license = snap;
        _activationError = '';
        _state = _GateState.activation;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _centerCtl.dispose();
    // م180/ج — متحكمات خطوتَي المعالجات والمختبرات.
    for (final (a, b) in _svcCtls) {
      a.dispose();
      b.dispose();
    }
    for (final l in _labCtls) {
      l.name.dispose();
      for (final (a, b) in l.types) {
        a.dispose();
        b.dispose();
      }
    }
    _codeCtl.dispose();
    for (final c in _clinicCtls) {
      c.dispose();
    }
    super.dispose();
  }

  ({LocalDb db, String uid}) get _r => (
    db: ref.read(localDbProvider),
    uid: ref.read(authProvider) is SignedIn
        ? (ref.read(authProvider) as SignedIn).user.uid
        : '',
  );

  Map<String, Object?> _config() => ref.read(appConfigProvider);

  /// م32 — قفز كل عدّادات النسخ: يجبر كل المزوّدات المؤقتة على إعادة
  /// القراءة من القاعدة (النظيفة بعد مسح تبديل الحساب) قبل أي حكم/عرض.
  void _refreshAllCaches() {
    ref.read(configRevProvider.notifier).state++;
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    ref.read(queueRevProvider.notifier).state++;
    ref.read(apptRevProvider.notifier).state++;
    ref.read(xrayVersionProvider.notifier).state++;
  }

  /// م36 — تصفير حالة الواجهة عند **كل** عبور للبوابة (دخول أو فتح):
  /// حالة الجلسة السابقة (تبويب نشط، عيادة مفتوحة داخل السجلات، نص بحث،
  /// مسودات) كانت تعيش في الذاكرة عبر الخروج/الدخول فظهرت شاشة عيادة
  /// الحساب القديم تحت الحساب الجديد. القاعدة: البداية دائماً من
  /// «الرئيسية» بواجهة نظيفة بلا أي أثر من جلسة/حساب سابق.
  void _resetUiState() {
    ref.read(activeTabProvider.notifier).state = 'home';
    ref.read(openClinicProvider.notifier).state = null;
    ref.read(patientSearchProvider.notifier).state = '';
    ref.read(addVisitDraftProvider.notifier).state = null;
    ref.read(followUpDraftProvider.notifier).state = null;
    ref.read(financeSectionProvider.notifier).state = 'menu';
  }

  /// القرار على الإقلاع — توأم onMounted في الأصل.
  Future<void> _decide() async {
    _refreshAllCaches();
    _resetUiState();
    // إصلاح تبديل الحساب (حرج): بذر حصة/استهلاك الحساب الحالي من الخادم فور
    // العبور. خريطة الأحجام المحلية فارغةٌ لحسابٍ جديد على الجهاز نفسه، فلولا
    // هذا البذر لظهر حسابٌ ممتلئ على الخادم فارغاً محلياً وسُمح له بالرفع.
    // أفضل جهد ولا يعطّل البوابة (يبتلع الفشل داخلياً).
    unawaited(ref.read(storageMeterProvider).refreshFromServer());
    // م135 — حارس الترخيص أولاً: قبل أي ترحيبٍ أو إعداد. بينما الإجبار
    // مطفأ (gate.enforce=false) تعيد evaluate() «مسموح» دائماً فلا تتغيّر
    // التجربة؛ وحين يُفعَّل: المنتهي/المحظور/المجمَّد/بلا اشتراك ⇒ التفعيل.
    if (!await _checkLicense()) return;
    final r = _r;
    // ١) مكتمل محلياً (قديم/نفس الجهاز) ⇒ ترحيب (إن كان دخولاً صريحاً)
    //    أو الرئيسية مباشرة عند استعادة الجلسة.
    if (isSetupComplete(r.db, r.uid, _config())) {
      final fresh = ref.read(authProvider.notifier).justLoggedIn;
      if (fresh) {
        await _runWelcome();
      } else {
        // م86 — إقلاعٌ على جلسة مستعادة (لا دخولٌ صريح): إن وُجد مُتحقِّق
        // قفلٍ محلي فابدأ **مقفلاً**. قفلُ الخمول كان حالةَ ذاكرةٍ فقط
        // (`lockedProvider`), فإغلاقُ التطبيق وإعادةُ فتحه يُصفّرها ويدخل
        // بلا كلمة مرور — أي أن «الإغلاق» كان يتخطّى القفل كلّه. الآن كلُّ
        // إقلاعٍ بارد على جلسةٍ محفوظة يطلب كلمة المرور نفسها (أو الخروج)،
        // وهو سلوك المنتجات الطبية القياسي. والتحقّق محليٌّ فيعمل بلا شبكة.
        //
        // م87 — يحترم مفتاح الإعدادات: للمالك أن يعطّل قفل الإقلاع على جهازٍ
        // موثوق (تفضيلٌ محليٌّ لكل جهاز، لا مُزامَن). الافتراض مُفعَّل.
        //
        // م91 — البصمة وسيلةُ فتحٍ كاملة بذاتها: مفعِّلُها بلا مُتحقِّقٍ
        // (داخلُ Google قبل تعيين رمزٍ) كان إقلاعُه يتخطى القفل **صامتاً**
        // رغم أن مفتاح الإعدادات يوحي بعكس ذلك. الشرط الآن: توجد وسيلةُ
        // فتحٍ أيّاً كانت (مُتحقِّق أو بصمة) والمفتاح مفعَّل ⇒ ابدأ مقفلاً.
        // وبلا أي وسيلة يبقى الإقلاع مفتوحاً كما كان — قفلٌ لا فتحَ له
        // فخٌّ لا حماية، وتنبيهُ الإعدادات (م91/٥) يصارح المالك بذلك.
        if ((hasLockVerifier(r.db) || biometricEnabled(r.db)) &&
            lockOnStartEnabled(r.db)) {
          ref.read(lockedProvider.notifier).state = true;
        }
        _goHome();
      }
      return;
    }
    // ٢) لا دليل محلي ⇒ قد يكون قديماً على جهاز جديد: اسحب الخادم ثم احكم.
    if (!mounted) return;
    setState(() => _state = _GateState.loading);
    try {
      await ref.read(syncEngineProvider).syncNow();
    } catch (_) {
      /* أوفلاين ⇒ يُعامل كجديد فقط إن لا بيانات */
    }
    if (!mounted) return;
    if (isSetupComplete(r.db, r.uid, _config())) {
      await _runWelcome();
      return;
    }
    // ٣) جديد فعلاً ⇒ نموذج الإعداد الإجباري.
    setState(() => _state = _GateState.setup);
  }

  /// م135 — يقيّم الترخيص. يعيد true للمتابعة، أو يعرض شاشة التفعيل ويعيد
  /// false. يُبقي حالة التحميل أثناء نداء الخادم.
  Future<bool> _checkLicense() async {
    if (!mounted) return false;
    setState(() => _state = _GateState.loading);
    final snap = await ref.read(licenseServiceProvider).evaluate();
    if (!mounted) return false;
    // نُبقي اللقطة دائماً (حتى عند السماح) كي تقرأ شاشة الإعداد حدّ العيادات.
    _license = snap;
    if (snap.allowed) return true;
    setState(() {
      _activationError = '';
      _state = _GateState.activation;
    });
    return false;
  }

  /// حد العيادات الفعّال (0 = بلا حدّ) — من لقطة الترخيص أو التخبئة المتزامنة.
  int get _maxClinics {
    final m = _license?.maxClinics ?? 0;
    return m > 0 ? m : ref.read(licenseServiceProvider).cachedMaxClinics();
  }

  /// تفعيل بالكود المُدخَل — عند النجاح يُعاد الحسم من أول البوابة.
  Future<void> _activate() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty) {
      setState(() => _activationError = 'أدخل كود التفعيل.');
      return;
    }
    setState(() {
      _activating = true;
      _activationError = '';
    });
    try {
      final snap = await ref.read(licenseServiceProvider).activate(code);
      if (!mounted) return;
      if (snap.allowed) {
        _codeCtl.clear();
        setState(() => _activating = false);
        await _decide(); // اشتراكٌ فعّالٌ الآن ⇒ ترحيب/إعداد/رئيسية
      } else {
        setState(() {
          _activating = false;
          _license = snap;
          _activationError = 'فُعّل الكود لكن الاشتراك ما زال غير فعّال.';
        });
      }
    } on LicenseException catch (e) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _activationError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activating = false;
        _activationError = 'تعذّر التفعيل: $e';
      });
    }
  }

  Future<void> _logoutFromActivation() async {
    await ref.read(authProvider.notifier).logout();
  }

  /// الترحيب الفاخر: خلفية أولاً ← بعد ~300ms يبدأ الظهور المتدرّج للأسطر
  /// (0/140/300/460ms) ← ثبات (حد أدنى 2.8s + التحميل الفعلي معاً) ←
  /// تلاشٍ 500ms — توأم runWelcome حرفياً.
  Future<void> _runWelcome() async {
    if (!mounted) return;
    setState(() {
      _centerName = ref.read(centerNameProvider);
      // م88 — اسم حساب Google (إن وُجد) لترحيبٍ شخصيّ: «أهلاً بك مجدداً، د. أحمد».
      final a = ref.read(authProvider);
      _greetName = a is SignedIn ? (a.user.displayName ?? '') : '';
      _state = _GateState.welcome;
      _welcomeOut = false;
      for (var i = 0; i < 4; i++) {
        _lineIn[i] = false;
      }
    });
    await Future<void>.delayed(_fadeInDelay);
    if (!mounted) return;
    // تدرّج ظهور الأسطر — transition-delay: 0/140/300/460ms.
    const delays = [0, 140, 300, 460];
    for (var i = 0; i < 4; i++) {
      Future<void>.delayed(Duration(milliseconds: delays[i]), () {
        if (mounted && _state == _GateState.welcome) {
          setState(() => _lineIn[i] = true);
        }
      });
    }
    // الشرطان معاً: حد القراءة الأدنى + التحميل الفعلي (مزامنة أفضل-جهد).
    final load = () async {
      try {
        await ref.read(syncEngineProvider).syncNow();
      } catch (_) {
        /* فشل الشبكة لا يعلّق الشاشة */
      }
    }();
    await Future.wait([Future<void>.delayed(_minRead), load]);
    if (!mounted) return;
    setState(() => _welcomeOut = true);
    await Future<void>.delayed(_fadeOut);
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    setState(() => _state = _GateState.done);
    // المرحلة هـ — إشعارات فتح التطبيق: بعد أول إطارٍ داخل الصدفة، ومرةً
    // واحدةً فقط في عمر البوابة (حارس `_notifShown`). أفضلُ جهدٍ بالكامل —
    // الوضع المحلي لا يفعل شيئاً، وفشلُ الشبكة لا يُعطّل فتح التطبيق.
    if (!_notifShown) {
      _notifShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPendingNotifications(context, ref);
      });
    }
    // م96 — أُزيل اقتراحُ «رمز قفل التطبيق» عند أول دخول (قرار المالك):
    // لا نطلب من داخل Google شيئاً عند دخوله. لا قفلَ يشتعل بلا وسيلة فتح
    // (idle_lock/م96)، فلا فخّ ولا رسالة. ومن أراد قفلاً يعيّن الرمز متى
    // شاء من «إعدادات الحساب» (م93)، وتفعيلُ «القفل عند فتح التطبيق»
    // يقوده لتعيينه أولاً (settings/م96).
  }

  void _addClinic() {
    // المرحلة ب — حد العيادات: منع تجاوز max_clinics في الواجهة (والخادم
    // يفرضه أيضاً خلف مفتاحه). 0 = بلا حدّ.
    final max = _maxClinics;
    if (max > 0 && _clinicCtls.length >= max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطتك تسمح بـ$max ${max == 1 ? 'عيادة واحدة' : 'عيادات'} فقط. '
            'للمزيد رقِّ خطتك من لوحة الاشتراك.',
          ),
          backgroundColor: BrandColors.gold,
        ),
      );
      return;
    }
    setState(() => _clinicCtls.add(TextEditingController()));
  }

  void _removeClinic(int i) {
    if (_clinicCtls.length == 1) return;
    setState(() => _clinicCtls.removeAt(i).dispose());
  }

  /// م143 — قائمة «غائبة أو فارغة»؟ حارسُ البذر الحتمي: لا تُبذَر
  /// الافتراضات إلا حين لا وجود لقيمةٍ سابقة (idempotent).
  static bool _listIsEmpty(Object? v) =>
      v is! List || v.where((e) => '$e'.trim().isNotEmpty).isEmpty;

  /// م88/ج — مخرجُ مَن دخل بالحساب الخطأ: شاشة الإعداد إجبارية بالتصميم،
  /// وبلا هذا الرابط تصير **فخاً** لمن سجّل بحساب Google غير المقصود — لا
  /// طريق له إلا إكمال إعدادٍ لحسابٍ لا يريده. الخروج يعيده لشاشة الدخول،
  /// وعودتُه بنفس الحساب تعيده إلى الإعداد الإجباري نفسه (لم يكتمل بعد).
  Future<void> _logoutFromSetup() async {
    await ref.read(authProvider.notifier).logout();
    // لا setState: تغيّر حالة المصادقة يعيد بناء الجذر إلى شاشة الدخول.
  }

  /// م180/ج — الخطوة ١: المركز والعيادات ⇒ **حفظ ومتابعة** (تُكتب في
  /// app.config فوراً، ولا يُختم علم الإكمال قبل الخطوة الأخيرة).
  Future<void> _submitSetup() async {
    final name = _centerCtl.text.trim();
    final clinics = [
      for (final c in _clinicCtls)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (name.isEmpty) {
      setState(() => _formError = 'يرجى إدخال اسم المركز أو الطبيب');
      return;
    }
    if (clinics.isEmpty) {
      setState(() => _formError = 'أضف عيادة واحدة على الأقل');
      return;
    }
    // المرحلة ب — سقف العيادات: لا يُكمَل الإعداد بأكثر مما تسمح به الخطة.
    final max = _maxClinics;
    if (max > 0 && clinics.length > max) {
      setState(
        () => _formError =
            'خطتك تسمح بـ$max ${max == 1 ? 'عيادة واحدة' : 'عيادات'} فقط '
            '(أدخلت ${clinics.length}). احذف الزائدة أو رقِّ خطتك.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _formError = '';
      _state = _GateState.preparing;
    });
    // حفظ الإعداد في app.config (يُزامَن)، ثم ضبط علم الإكمال الدائم.
    final repos = ref.read(reposProvider);
    final cur = repos.settings.get('app.config');
    final cfg = cur is Map
        ? Map<String, Object?>.from(cur)
        : <String, Object?>{};
    cfg['centerName'] = name;
    cfg['clinics'] = clinics;
    // م143 — بذر افتراضيّ لطرق الدفع والمعالجات: يُكتب **فقط** حين تكون
    // القائمة غائبة/فارغة (لا يدهس بيانات مستخدمٍ قائمة ولا يصارع شواهد
    // القبور لكل صف). طرق الدفع كاش/تحويل مقفولتان لاحقاً في الإعدادات؛
    // «تركيبات» من المعالجات مقفولة الحذف — والبذر هنا يضمن وجودها لأول مرة.
    if (_listIsEmpty(cfg['payments'])) {
      cfg['payments'] = <String>['كاش', 'تحويل'];
    }
    repos.settings.set('app.config', cfg);
    ref.read(configRevProvider.notifier).state++;
    // م180/ج — لا ختم هنا: ننتقل للخطوة ٢ (المعالجات وأسعارها).
    setState(() {
      _saving = false;
      _formError = '';
      _state = _GateState.setup;
      _step = 1;
    });
  }

  /// م180/ج — الخطوة ٢: المعالجات وأسعارها (واحدة على الأقل — إلزامية).
  /// تُكتب `services` و`servicePrices` معاً ثم ننتقل للمختبرات.
  /// م181 — «تركيبات» تُلحق دائماً في ذيل القائمة (مثبتة، بلا سعر)؛
  /// وكتابتها يدوياً كصفٍّ حر مرفوضة كي لا تتكرر أو تحمل سعراً.
  void _submitServices() {
    final names = <String>[];
    final prices = <String, Object?>{};
    for (final (n, p) in _svcCtls) {
      final nm = n.text.trim();
      if (nm.isEmpty) continue;
      if (kLockedServices.contains(nm)) {
        setState(() =>
            _formError = '«$nm» مثبتة تلقائياً — لا حاجة لإدخالها');
        return;
      }
      if (names.contains(nm)) {
        setState(() => _formError = 'المعالجة «$nm» مكررة');
        return;
      }
      names.add(nm);
      final v = num.tryParse(p.text.trim()) ?? 0;
      if (v > 0) prices[nm] = v;
    }
    if (names.isEmpty) {
      setState(() => _formError = 'أضِف معالجة واحدة على الأقل');
      return;
    }
    names.addAll(kLockedServices);
    final repos = ref.read(reposProvider);
    final cur = repos.settings.get('app.config');
    final cfg = cur is Map
        ? Map<String, Object?>.from(cur)
        : <String, Object?>{};
    cfg['services'] = names;
    if (prices.isNotEmpty) {
      final old = cfg['servicePrices'];
      cfg['servicePrices'] = {
        if (old is Map) ...Map<String, Object?>.from(old),
        ...prices,
      };
    }
    repos.settings.set('app.config', cfg);
    ref.read(configRevProvider.notifier).state++;
    setState(() {
      _formError = '';
      _step = 2;
    });
  }

  /// م180/ج — الخطوة ٣: المختبرات وأنواعها ⇒ **حفظ وإنهاء**. المختبرات
  /// اختيارية (قد لا يتعامل مع مخبر بعد) — والقائمة الفارغة تُنهي الإعداد.
  /// هنا فقط يُختم علم الإكمال ويتابع لشاشة البدء بالسلوك القديم.
  Future<void> _submitLabs() async {
    final labs = <String>[];
    final byLab = <String, Object?>{};
    for (final l in _labCtls) {
      final nm = l.name.text.trim();
      if (nm.isEmpty) continue;
      if (labs.contains(nm)) {
        setState(() => _formError = 'المختبر «$nm» مكرر');
        return;
      }
      labs.add(nm);
      final types = <Map<String, Object?>>[];
      for (final (tn, tp) in l.types) {
        final t = tn.text.trim();
        if (t.isEmpty) continue;
        types.add({'name': t, 'defaultPrice': num.tryParse(tp.text.trim()) ?? 0});
      }
      if (types.isNotEmpty) byLab[nm] = types;
    }
    setState(() {
      _saving = true;
      _formError = '';
      _state = _GateState.preparing;
    });
    final repos = ref.read(reposProvider);
    final cur = repos.settings.get('app.config');
    final cfg = cur is Map
        ? Map<String, Object?>.from(cur)
        : <String, Object?>{};
    if (labs.isNotEmpty) {
      cfg['labs'] = labs;
      if (byLab.isNotEmpty) cfg['labTypesByLab'] = byLab;
    }
    repos.settings.set('app.config', cfg);
    ref.read(configRevProvider.notifier).state++;
    final r = _r;
    markSetupComplete(r.db, r.uid);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _goHome();
  }

  // ── م180/ج — مقابض صفوف الخطوتين ──
  void _addService() =>
      setState(() => _svcCtls.add((TextEditingController(),
          TextEditingController())));

  void _removeService(int i) {
    if (_svcCtls.length == 1) return;
    setState(() {
      final (a, b) = _svcCtls.removeAt(i);
      a.dispose();
      b.dispose();
    });
  }

  void _addLab() => setState(() => _labCtls.add((
        name: TextEditingController(),
        types: <(TextEditingController, TextEditingController)>[
          (TextEditingController(), TextEditingController()),
        ],
      )));

  void _removeLab(int i) {
    setState(() {
      final l = _labCtls.removeAt(i);
      l.name.dispose();
      for (final (a, b) in l.types) {
        a.dispose();
        b.dispose();
      }
    });
  }

  void _addLabType(int li) => setState(() => _labCtls[li].types.add(
        (TextEditingController(), TextEditingController()),
      ));

  void _removeLabType(int li, int ti) {
    if (_labCtls[li].types.length == 1) return;
    setState(() {
      final (a, b) = _labCtls[li].types.removeAt(ti);
      a.dispose();
      b.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    // م79 — قفل الخمول يلفّ الصدفة: الشجرة تحت الغطاء تبقى حيّة
    // فلا يُفقد عمل غير محفوظ عند القفل.
    if (_state == _GateState.done) {
      return const IdleLockScope(child: AppShellScreen());
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // ── login-bg: التدرج 160° بثلاث محطات — حرفياً ──
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-0.34, -0.94),
                    end: Alignment(0.34, 0.94),
                    stops: [0.0, 0.6, 1.0],
                    colors: [
                      Color(0xFF15604A),
                      Color(0xFF0A3024),
                      Color(0xFF071E16),
                    ],
                  ),
                ),
              ),
            ),
            // ── login-header-pattern: النقش الهندسي الذهبي (شفافية 7%) ──
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _GoldPatternPainter()),
              ),
            ),
            // المحتوى — بطاقة متوسطة (padding: 24px 16px كالأصل).
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                child: switch (_state) {
                  _GateState.activation => _activationCard(),
                  _GateState.setup => switch (_step) {
                    1 => _servicesCard(),
                    2 => _labsCard(),
                    _ => _setupCard(),
                  },
                  _GateState.welcome => _welcomeCard(),
                  _GateState.preparing => _spinnerCard(
                    'يرجى الانتظار قليلاً...',
                    sub: 'يتم تجهيز حسابك لأول مرة.',
                  ),
                  _ => _spinnerCard('يرجى الانتظار قليلاً...'),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── .glass: أبيض، زوايا 22، حد rgba(20,80,59,.12)، ظل sh-1 ────────────────
  Widget _glass({
    required Widget child,
    double maxWidth = 360,
    EdgeInsets padding = const EdgeInsets.fromLTRB(28, 40, 28, 40),
  }) => Container(
    constraints: BoxConstraints(maxWidth: maxWidth),
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color.fromRGBO(20, 80, 59, .12)),
      boxShadow: const [
        BoxShadow(
          color: Color.fromRGBO(10, 48, 36, .06),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  // ── .pg-spinner: حلقة 44px بسماكة 3 — مسار ذهبي 22% ورأس ذهبي ─────────────
  Widget _pgSpinner() => const SizedBox(
    width: 44,
    height: 44,
    child: CircularProgressIndicator(
      strokeWidth: 3,
      color: _gold,
      backgroundColor: Color.fromRGBO(201, 162, 75, .22),
    ),
  );

  // ── م135 — شاشة تفعيل الاشتراك ──────────────────────────────────────────
  //  رسالةٌ حسب سبب الحجب + حقل كود + زر تفعيل + رابط خروج صغير (كالإعداد).
  //  بهوية البوابة نفسها (زجاجٌ فوق تدرّج العلامة).
  ({String title, String body, IconData icon, Color tint}) _activationCopy() {
    switch (_license?.result) {
      case LicenseGateResult.banned:
        return (
          title: 'الحساب محظور',
          body:
              'أُوقف هذا الحساب من الإدارة. للتواصل أو رفع الحظر راجع مزوّد '
              'الخدمة — لا يمكن استخدام التطبيق حتى فكّ الحظر.',
          icon: Icons.block_rounded,
          tint: _softRed,
        );
      case LicenseGateResult.frozen:
        return (
          title: 'الاشتراك مجمَّد',
          body:
              'جُمّد اشتراكك مؤقتاً من الإدارة. إلغاء التجميد يعيد الوصول '
              'فوراً — أو فعّل بكودٍ جديد.',
          icon: Icons.ac_unit_rounded,
          tint: _gold,
        );
      case LicenseGateResult.offlineExpired:
        return (
          title: 'يلزم التحقق من الاشتراك',
          body:
              'مضت فترة السماح دون اتصال بالخادم. اتصل بالإنترنت مرةً '
              'ليتحقق التطبيق من اشتراكك، أو أدخل كود تفعيل.',
          icon: Icons.wifi_off_rounded,
          tint: _gold,
        );
      case LicenseGateResult.clockTampered:
        return (
          title: 'تعذّر التحقق من التاريخ',
          body:
              'ساعة الجهاز أقدم مما ينبغي. اضبط تاريخ الجهاز ووقته على '
              'الصحيح ثم أعد المحاولة، أو اتصل بالإنترنت للتحقق.',
          icon: Icons.schedule_rounded,
          tint: _softRed,
        );
      case LicenseGateResult.deviceLimit:
        return (
          title: 'تجاوزت حدّ الأجهزة',
          body:
              'خطتك تسمح بعددٍ محدود من الأجهزة، وهذا جهازٌ إضافي. أزِل جهازاً '
              'قديماً من لوحة الاشتراك أو اطلب من الإدارة إعادة تعيين أجهزتك '
              'أو رفع الحد، ثم أعد المحاولة.',
          icon: Icons.devices_other_rounded,
          tint: _softRed,
        );
      default: // needsActivation / none / expired
        return (
          title: 'تفعيل الاشتراك',
          body:
              'أدخل كود التفعيل لبدء استخدام التطبيق. إن انتهى اشتراكك '
              'فأدخل كوداً جديداً لتجديده.',
          icon: Icons.vpn_key_rounded,
          tint: _gold,
        );
    }
  }

  Widget _activationCard() {
    final c = _activationCopy();
    return _glass(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.tint.withValues(alpha: .14),
            ),
            child: Icon(c.icon, size: 28, color: c.tint),
          ),
          const SizedBox(height: 14),
          Text(
            c.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _brand700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: _ink.withValues(alpha: .8),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('activation-code'),
            controller: _codeCtl,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            enabled: !_activating,
            decoration: InputDecoration(
              hintText: 'DENT-XXXX-XXXX-XXXX',
              hintStyle: TextStyle(
                color: _ink.withValues(alpha: .35),
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: BrandColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: BrandColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _brand, width: 1.6),
              ),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            onSubmitted: (_) => _activating ? null : _activate(),
          ),
          if (_activationError.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _activationError,
              key: const Key('activation-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _softRed,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('activation-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _activating ? null : _activate,
              child: _activating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'تفعيل',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('activation-logout'),
            onPressed: _activating ? null : _logoutFromActivation,
            child: Text(
              'تسجيل الخروج',
              style: TextStyle(
                color: _ink.withValues(alpha: .6),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── حالة التحميل/التجهيز: سبنر + نص ذهبي فاتح عريض (كالأصل) ───────────────
  Widget _spinnerCard(String msg, {String? sub}) => _glass(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pgSpinner(),
        const SizedBox(height: 20),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _goldL,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .75)),
          ),
        ],
      ],
    ),
  );

  // ── سطر ترحيب متدرّج (wm-line): تلاشٍ + انزلاق 12px بمنحنى الأصل ──────────
  Widget _wmLine(int i, Widget child, {double targetOpacity = 1}) {
    const curve = Cubic(0.22, 1, 0.36, 1);
    const dur = Duration(milliseconds: 600);
    return AnimatedSlide(
      offset: _lineIn[i] ? Offset.zero : const Offset(0, 0.18),
      duration: dur,
      curve: curve,
      child: AnimatedOpacity(
        opacity: _lineIn[i] ? targetOpacity : 0,
        duration: dur,
        curve: curve,
        child: child,
      ),
    );
  }

  // ── شاشة الترحيب (wm-card): 4 أسطر متدرجة + خروج بتلاشٍ وانزياح ───────────
  Widget _welcomeCard() => AnimatedScale(
    scale: _welcomeOut ? 0.99 : 1,
    duration: _fadeOut,
    child: AnimatedSlide(
      offset: _welcomeOut ? const Offset(0, -0.01) : Offset.zero,
      duration: _fadeOut,
      child: AnimatedOpacity(
        opacity: _welcomeOut ? 0 : 1,
        duration: _fadeOut,
        child: _glass(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _wmLine(
                0,
                Text(
                  _greetName.isEmpty
                      ? 'أهلاً بك مجدداً'
                      : 'أهلاً بك مجدداً، $_greetName',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _goldL.withValues(alpha: .9),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _wmLine(
                1,
                Text(
                  _centerName,
                  key: const Key('gate-welcome-name'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                    color: _goldL,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _wmLine(
                2,
                Text(
                  'يتم الآن تجهيز الإعدادات والبيانات...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _ink.withValues(alpha: .7),
                  ),
                ),
                targetOpacity: 0.7,
              ),
              const SizedBox(height: 20),
              _wmLine(3, _pgSpinner()),
            ],
          ),
        ),
      ),
    ),
  );

  // ── .sec-h: شريط ذهبي يمين 3px + نص أخضر داكن عريض ────────────────────────
  Widget _secH(String s) => Row(
    children: [
      Container(width: 3, height: 16, color: _gold),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          s,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _brand700,
            letterSpacing: .3,
          ),
        ),
      ),
    ],
  );

  // ── .inp: حقل أبيض بحد أخضر شفاف وزوايا 12 وتركيز بحد أخضر ────────────────
  Widget _inp(
    TextEditingController ctl,
    String hint, {
    Key? key,
    void Function(String)? onSubmitted,
  }) => TextField(
    key: key,
    controller: ctl,
    textAlign: TextAlign.right,
    onSubmitted: onSubmitted,
    style: const TextStyle(fontSize: 15, color: _ink),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 15, color: _ink.withValues(alpha: .5)),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color.fromRGBO(20, 80, 59, .14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    ),
  );

  // ── .pg-del: زر حذف عيادة 38×38 أحمر ناعم ─────────────────────────────────
  Widget _pgDel({required bool enabled, required VoidCallback onTap}) =>
      Opacity(
        opacity: enabled ? 1 : .4,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color.fromRGBO(248, 113, 113, .35),
              ),
              color: const Color.fromRGBO(248, 113, 113, .08),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 17,
              color: _softRed,
            ),
          ),
        ),
      );

  // ═══ م180/ج — عناصر معالج الإعداد المشتركة (هوية البطاقة نفسها) ═══

  /// مؤشر التقدم: ثلاث حبّات ذهبية — المكتملة والحالية ممتلئتان.
  Widget _stepDots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              Container(
                width: 22,
                height: 2,
                color: i <= _step
                    ? const Color.fromRGBO(201, 162, 75, .7)
                    : const Color.fromRGBO(20, 80, 59, .14),
              ),
            Container(
              key: Key('gate-step-dot-$i'),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= _step
                    ? _goldD
                    : const Color.fromRGBO(20, 80, 59, .16),
              ),
            ),
          ],
        ],
      );

  /// ترويسة خطوة: عنوان ذهبي + سطر شرح + مؤشر التقدم.
  Widget _stepHead(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w900,
              color: _goldL,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12, color: _ink.withValues(alpha: .75)),
          ),
          const SizedBox(height: 12),
          _stepDots(),
          const SizedBox(height: 18),
        ],
      );

  /// الزر الأخضر الرئيسي (نفس كبسولة «بدء تجهيز الحساب» حرفياً).
  Widget _primaryBtn(String label, VoidCallback? onTap, {required Key key}) =>
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(50),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              gradient: const LinearGradient(
                begin: Alignment(-0.34, -0.94),
                end: Alignment(0.34, 0.94),
                colors: [Color(0xFF15604A), Color(0xFF0A3024)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(10, 48, 36, .25),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );

  /// كبسولة «إضافة …» بحد ذهبي (توأم «إضافة عيادة»).
  Widget _addBtn(String label, VoidCallback onTap, {required Key key}) =>
      Material(
        color: const Color.fromRGBO(201, 162, 75, .08),
        borderRadius: BorderRadius.circular(50),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              border:
                  Border.all(color: const Color.fromRGBO(201, 162, 75, .3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, size: 15, color: _goldD),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _goldD,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _errorLine() => _formError.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _formError,
            key: const Key('gate-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
          ),
        );

  /// م180/ج — الخطوة ٢: المعالجات وأسعارها.
  Widget _servicesCard() => _glass(
        maxWidth: 400,
        padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHead('المعالجات وأسعارها',
                'أضِف معالجات عيادتك وسعر كلٍّ منها — يملأ السعر قيمة '
                'السجل تلقائياً عند اختيار المعالجة.'),
            _secH('المعالجات'),
            const SizedBox(height: 8),
            for (var i = 0; i < _svcCtls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _inp(_svcCtls[i].$1, 'اسم المعالجة',
                          key: Key('gate-svc-name-$i')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _inp(_svcCtls[i].$2, 'السعر',
                          key: Key('gate-svc-price-$i')),
                    ),
                    const SizedBox(width: 8),
                    _pgDel(
                      enabled: _svcCtls.length > 1,
                      onTap: () => _removeService(i),
                    ),
                  ],
                ),
              ),
            // م181 — صف «تركيبات» المثبت: معالجة نظامية تُكتب دائماً،
            // بلا اسم يحرَّر ولا حقل سعر ولا حذف — سعرها متغيّر بطبيعته
            // (وحدات × سعر نوع المختبر) فيُدخل مع كل حالة لا هنا.
            for (final locked in kLockedServices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  key: Key('gate-svc-locked-$locked'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: BrandColors.gold.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: BrandColors.gold.withValues(alpha: .30),
                        width: .8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 14, color: BrandColors.goldDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(locked,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: BrandColors.brandText)),
                      ),
                      Text(kVariablePriceLabel,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: BrandColors.goldDark)),
                    ],
                  ),
                ),
              ),
            _addBtn('إضافة معالجة', _addService,
                key: const Key('gate-add-service')),
            _errorLine(),
            const SizedBox(height: 18),
            _primaryBtn('حفظ ومتابعة', _saving ? null : _submitServices,
                key: const Key('gate-services-next')),
          ],
        ),
      );

  /// م180/ج — الخطوة ٣: المختبرات وأنواعها (اختيارية) ⇒ حفظ وإنهاء.
  Widget _labsCard() => _glass(
        maxWidth: 400,
        padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHead('المختبرات التي تتعامل معها',
                'أضِف كل مختبر وأنواع التركيبات وأسعارها لديه. يمكنك '
                'تخطّي هذه الخطوة وإضافتها لاحقاً من الإعدادات.'),
            for (var li = 0; li < _labCtls.length; li++)
              Container(
                key: Key('gate-lab-$li'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(20, 80, 59, .03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color.fromRGBO(20, 80, 59, .12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _inp(_labCtls[li].name, 'اسم المختبر',
                              key: Key('gate-lab-name-$li')),
                        ),
                        const SizedBox(width: 8),
                        _pgDel(enabled: true, onTap: () => _removeLab(li)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (var ti = 0; ti < _labCtls[li].types.length; ti++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _inp(_labCtls[li].types[ti].$1,
                                  'نوع التركيبة',
                                  key: Key('gate-labtype-$li-$ti')),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _inp(_labCtls[li].types[ti].$2, 'السعر',
                                  key: Key('gate-labprice-$li-$ti')),
                            ),
                            const SizedBox(width: 8),
                            _pgDel(
                              enabled: _labCtls[li].types.length > 1,
                              onTap: () => _removeLabType(li, ti),
                            ),
                          ],
                        ),
                      ),
                    _addBtn('إضافة نوع', () => _addLabType(li),
                        key: Key('gate-add-labtype-$li')),
                  ],
                ),
              ),
            _addBtn('إضافة مختبر', _addLab, key: const Key('gate-add-lab')),
            _errorLine(),
            const SizedBox(height: 18),
            _primaryBtn('حفظ وإنهاء', _saving ? null : _submitLabs,
                key: const Key('gate-labs-finish')),
          ],
        ),
      );

  // ── شاشة الإعداد الإجباري (setup) — توأم القالب حرفياً ─────────────────────
  Widget _setupCard() => _glass(
    maxWidth: 400,
    padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // العنوان: مرحباً بك + لنبدأ بإعداد حسابك.
        const Text(
          'مرحباً بك',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            height: 1.25,
            fontWeight: FontWeight.w900,
            color: _goldL,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'لنبدأ بإعداد حسابك.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _ink.withValues(alpha: .75)),
        ),
        const SizedBox(height: 12),
        // م180/ج — مؤشر خطوات المعالج (١ المركز · ٢ المعالجات · ٣ المختبرات).
        _stepDots(),
        const SizedBox(height: 18),

        // اسم المركز أو الطبيب (إجباري).
        _secH('اسم المركز أو الطبيب'),
        const SizedBox(height: 8),
        _inp(
          _centerCtl,
          'اسم المركز أو الطبيب',
          key: const Key('gate-center-name'),
        ),
        const SizedBox(height: 16),

        // قائمة العيادات (واحدة أو أكثر).
        _secH('العيادات'),
        const SizedBox(height: 8),
        for (var i = 0; i < _clinicCtls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _inp(
                    _clinicCtls[i],
                    'العيادة ${i + 1}',
                    key: Key('gate-clinic-$i'),
                    onSubmitted: (_) => _addClinic(),
                  ),
                ),
                const SizedBox(width: 8),
                _pgDel(
                  enabled: _clinicCtls.length > 1,
                  onTap: () => _removeClinic(i),
                ),
              ],
            ),
          ),
        // .btn-o: إضافة عيادة — كبسولة بحد ذهبي وخلفية ذهبية 8%.
        Material(
          color: const Color.fromRGBO(201, 162, 75, .08),
          borderRadius: BorderRadius.circular(50),
          child: InkWell(
            key: const Key('gate-add-clinic'),
            onTap: _addClinic,
            borderRadius: BorderRadius.circular(50),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: const Color.fromRGBO(201, 162, 75, .3),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 15, color: _goldD),
                  SizedBox(width: 5),
                  Text(
                    'إضافة عيادة',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _goldD,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (_formError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _formError,
            key: const Key('gate-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
          ),
        ],
        const SizedBox(height: 18),

        // .btn-g: بدء تجهيز الحساب — كبسولة بتدرج أخضر ونص أبيض عريض.
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          child: InkWell(
            key: const Key('gate-submit'),
            onTap: _saving ? null : _submitSetup,
            borderRadius: BorderRadius.circular(50),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                gradient: const LinearGradient(
                  begin: Alignment(-0.34, -0.94),
                  end: Alignment(0.34, 0.94),
                  colors: [Color(0xFF15604A), Color(0xFF0A3024)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(10, 48, 36, .25),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'حفظ ومتابعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),

        // م88/ج — مخرج صغير أسفل الإعداد الإجباري (طلب المالك حرفياً:
        // «بخط صغير صغير»): دخل بالحساب الخطأ ⇒ يخرج ويعود لشاشة
        // الدخول؛ وعودته بنفس الحساب تعيده لهذا الإعداد حتى يكمله.
        const SizedBox(height: 12),
        Center(
          child: InkWell(
            key: const Key('gate-logout'),
            onTap: _saving ? null : _logoutFromSetup,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'تسجيل الخروج',
                style: TextStyle(
                  fontSize: 11,
                  color: _ink.withValues(alpha: .55),
                  decoration: TextDecoration.underline,
                  decorationColor: _ink.withValues(alpha: .35),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// النقش الهندسي الذهبي — login-header-pattern حرفياً: بلاطة 60×60 فيها
/// معيّن خارجي (حد 0.5) ومعيّن داخلي (0.3) ودائرة نصف قطرها 8 (0.3)،
/// كلها بذهبي ‎#C9A24B وشفافية 7%.
class _GoldPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 60.0;
    final gold = _gold.withValues(alpha: .07);
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .5
      ..color = gold;
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .3
      ..color = gold;
    for (var x = 0.0; x < size.width; x += tile) {
      for (var y = 0.0; y < size.height; y += tile) {
        // المعيّن الخارجي: 30,0 → 60,30 → 30,60 → 0,30.
        final o = Path()
          ..moveTo(x + 30, y)
          ..lineTo(x + 60, y + 30)
          ..lineTo(x + 30, y + 60)
          ..lineTo(x, y + 30)
          ..close();
        canvas.drawPath(o, outer);
        // المعيّن الداخلي: 30,10 → 50,30 → 30,50 → 10,30.
        final i = Path()
          ..moveTo(x + 30, y + 10)
          ..lineTo(x + 50, y + 30)
          ..lineTo(x + 30, y + 50)
          ..lineTo(x + 10, y + 30)
          ..close();
        canvas.drawPath(i, inner);
        // الدائرة المركزية r=8.
        canvas.drawCircle(Offset(x + 30, y + 30), 8, inner);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GoldPatternPainter old) => false;
}
