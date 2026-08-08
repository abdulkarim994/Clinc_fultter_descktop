/// ============================================================================
///  م79 — قفل الخمول: لوحٌ متروك على مكتب الاستقبال لا يبقى مفتوحاً
/// ============================================================================
///
///  العلة
///  ─────
///  لا يوجد في التطبيق أي إنهاء تلقائي للجلسة. و`restoreSession` تُعيد
///  الجلسة **حتى لو انتهت صلاحية الرمز** (بتعليق صريح في الشيفرة). فجهازٌ
///  مفتوح على ملف مريض يبقى مفتوحاً إلى الأبد: من يمرّ بمكتب الاستقبال
///  يتصفّح السجلّات بلا كلمة مرور ولا أثر.
///
///  وهو أول ما تسأل عنه أي مراجعة تنظيمية لبيانات صحية بعد التشفير.
///
///  لماذا طبقةٌ فوق الشجرة لا شاشة جديدة
///  ────────────────────────────────────
///  القفل **غطاءٌ في Stack** لا `Navigator.push`. والفرق جوهري: الشجرة
///  تحته تبقى حيّة، فحقلُ نصٍّ نصفُ مكتوب وحوارٌ مفتوح وتمريرةُ قائمة كلها
///  تعود كما كانت بعد الفتح. قفلٌ يُضيع عمل الطبيب يُطفَأ في أسبوع.
///
///  التحقّق محلي وبلا شبكة
///  ──────────────────────
///  يُخزَّن مُتحقِّق (PBKDF2 بملح) عند أول دخول ناجح، ويُفحص الفتح ضدّه
///  محلياً. ولذلك يعمل القفل **بلا إنترنت** — وهو الشرط في عيادة تعمل
///  offline-first. وبلا مُتحقِّق مخزَّن (جلسة مستعادة بلا دخول) يبقى الخيار
///  الوحيد تسجيل الخروج، فلا يصير القفل بابَ تجاوز.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/db/local_db.dart';
import '../../data/sync/db_sync.dart' show getMetaValue, setMetaValue;
import '../patients/audit_trail.dart' show AuditAction, recordAudit;
import 'biometric_auth.dart';
import 'lock_prefs.dart' show biometricEnabled, lockOnStartEnabled;
import 'password_hash.dart';

/// تنفيذ المصادقة الحيوية — يُتجاوَز في الاختبارات بمزيّفٍ في الذاكرة.
final biometricAuthProvider =
    Provider<BiometricAuth>((ref) => PlatformBiometricAuth());

/// مهلة الخمول الافتراضية.
///
/// عشر دقائق: قصيرةٌ بما يكفي لجهاز متروك في ممرّ، وطويلةٌ بما يكفي ألّا
/// تقاطع طبيباً يفحص مريضاً ويعود إلى الشاشة. والقيمة قابلة للحقن كي
/// تُفحص في الاختبارات بلا انتظار حقيقي.
const Duration kIdleTimeout = Duration(minutes: 10);

const String _kLockVerifierKey = 'auth.lock_verifier';
const String _kLockKindKey = 'auth.lock_verifier_kind';

/// يخزّن مُتحقِّق الفتح عند الدخول الناجح. **لا يخزّن كلمة المرور** — بل
/// مغلّف PBKDF2 بملح، نفس صيغة الحسابات المحلية وبنفس ضماناتها.
void storeLockVerifier(LocalDb db, String password) {
  try {
    final owner = db.getOwnerUid() ?? '';
    setMetaValue(db, _kLockVerifierKey, hashPassword(password), owner);
    // م91 — وسم النوع: شاشة القفل تسمّي ما تطلبه باسمه الصادق
    // («كلمة المرور» لا «الرمز») وبند الإعدادات يعرف لمن يظهر.
    setMetaValue(db, _kLockKindKey, 'password', owner);
  } catch (_) {/* أفضل جهد — غيابه يعني قفلاً بخيار الخروج فقط */}
}

/// م91 — «رمز قفل التطبيق»: مُتحقِّقُ فتحٍ لمن دخل **بلا كلمة مرور**
/// (Google/OAuth — كلمته لا تمرّ بالتطبيق أبداً بالتصميم، فلا شيء يُخزَّن
/// عند الدخول ويقع في فخّ «الخروج فقط» عند القفل).
///
/// نفس المفتاح ونفس مغلّف PBKDF2 بملح حرفياً — فكل ما بُني فوق المُتحقِّق
/// يعمل تلقائياً بلا مسار موازٍ: قفل الإقلاع (م86)، الفتح المحلي بلا شبكة،
/// مسح تبديل الحساب (sync_meta تُمسح كلها)، وخروجُ شاشة القفل. محليٌّ لكل
/// جهاز، لا يُزامَن ولا يغادر الجهاز — وهو قفلُ شاشةٍ فوق بياناتٍ مشفَّرة
/// أصلاً (م83)، لا بديلاً عن التشفير.
void storeLockPin(LocalDb db, String pin) {
  try {
    final owner = db.getOwnerUid() ?? '';
    setMetaValue(db, _kLockVerifierKey, hashPassword(normalizePinDigits(pin)),
        owner);
    setMetaValue(db, _kLockKindKey, 'pin', owner);
  } catch (_) {/* أفضل جهد */}
}

void clearLockVerifier(LocalDb db) {
  try {
    final owner = db.getOwnerUid() ?? '';
    setMetaValue(db, _kLockVerifierKey, null, owner);
    setMetaValue(db, _kLockKindKey, null, owner);
  } catch (_) {/* أفضل جهد */}
}

bool hasLockVerifier(LocalDb db) =>
    '${getMetaValue(db, _kLockVerifierKey) ?? ''}'.isNotEmpty;

/// م91 — نوع المُتحقِّق المخزَّن: `password` أو `pin`. الغياب = `password`:
/// كل التنصيبات السابقة لوجود الوسم خزّنت عبر مسار كلمة المرور حصراً.
String lockVerifierKind(LocalDb db) =>
    '${getMetaValue(db, _kLockKindKey) ?? ''}' == 'pin' ? 'pin' : 'password';

bool verifyLock(LocalDb db, String password) {
  final v = '${getMetaValue(db, _kLockVerifierKey) ?? ''}';
  if (v.isEmpty) return false;
  // م91 — الرمز يُطبَّع قبل التجزئة وقبل التحقق معاً (لوحة عربية تُنتج
  // ٠-٩ ولوحة غربية 0-9 — وكلاهما نفس الرمز). كلمة المرور لا تُمسّ:
  // جُزّئت كما كُتبت حرفياً عند التسجيل.
  final input =
      lockVerifierKind(db) == 'pin' ? normalizePinDigits(password) : password;
  return verifyPassword(input, v);
}

/// م91 — طيّ الأرقام العربية-الهندية (٠-٩) والفارسية (۰-۹) إلى ASCII —
/// نفس طيّة `normPhone` في `ar_normalize.dart`: الرمز رقمٌ لا نص، ولوحة
/// المستخدم لا تغيّر هويته.
String normalizePinDigits(String s) {
  final t = StringBuffer();
  for (final rune in s.trim().runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      t.write(rune - 0x0660); // ٠-٩
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      t.write(rune - 0x06F0); // ۰-۹
    } else {
      t.writeCharCode(rune);
    }
  }
  return t.toString();
}

/// م91 — صحّة رمز القفل قبل تخزينه: أرقام فقط وأربعة فأكثر، والتأكيد
/// مطابق. تعيد رسالة الخطأ العربية أو `null` عند الصحة.
String? validateLockPin(String pin, String confirm) {
  final p = normalizePinDigits(pin);
  if (p.length < 4) return 'الرمز أربعة أرقام على الأقل';
  if (!RegExp(r'^[0-9]+$').hasMatch(p)) return 'الرمز أرقامٌ فقط';
  if (p != normalizePinDigits(confirm)) return 'الرمزان غير متطابقين';
  return null;
}

/// حالة القفل — مُعلَنة عالمياً كي يستطيع أي مسار (زر «اقفل الآن» مثلاً)
/// فرضَ القفل فوراً.
final lockedProvider = StateProvider<bool>((ref) => false);

/// مهلة الخمول الفعّالة — تُتجاوَز في الاختبارات.
final idleTimeoutProvider = Provider<Duration>((ref) => kIdleTimeout);

/// م91 — خنق محاولات الفتح على الغطاء نفسه: خمسة إخفاقات ⇒ انتظار نصف
/// دقيقة. كان الغطاء **بلا أي خنق** (خلافاً لدخول `LocalAuthService` م68)،
/// ومع رمزٍ من أربعة أرقام يصير التخمين اليدوي على جهازٍ متروك واقعياً.
/// في الذاكرة عمداً — لا يُخزَّن ولا يُزامَن ولا يُستغل لقفلٍ عن بُعد —
/// ومُزوّدٌ كي تُختبَر النافذة بلا انتظارٍ حقيقي.
final lockThrottleProvider = Provider<({int maxFails, Duration window})>(
    (ref) => (maxFails: 5, window: const Duration(seconds: 30)));

/// يغلّف الشجرة، ويرصد النشاط، ويعرض غطاء القفل عند الخمول.
class IdleLockScope extends ConsumerStatefulWidget {
  const IdleLockScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IdleLockScope> createState() => _IdleLockScopeState();
}

class _IdleLockScopeState extends ConsumerState<IdleLockScope>
    with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime _lastActivity = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // نبضة كل ثلاثين ثانية بدل مؤقّت يُعاد ضبطه عند كل لمسة: الثاني يُنشئ
    // ويُلغي آلاف المؤقّتات في جلسة عمل عادية بلا فائدة.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // العودة من الخلفية أهم لحظة للفحص: الجهاز قد يكون بقي في جيب أو على
    // طاولة ساعاتٍ، والمؤقّت الدوري لا يُوثَق به وقت تعليق التطبيق.
    if (state == AppLifecycleState.resumed) _check();
  }

  void _markActive() {
    if (ref.read(lockedProvider)) return; // لمسُ الغطاء ليس نشاطاً
    _lastActivity = DateTime.now();
  }

  void _check() {
    if (!mounted || ref.read(lockedProvider)) return;
    // م97 — القفل كلُّه (إقلاعاً وخمولاً) محكومٌ بمفتاحٍ واحد مطفأٍ
    // افتراضاً: إن لم يُفعِّله المالك فلا قفلَ إطلاقاً. وحين يُفعَّل فشرطُ
    // تفعيله كان تعيينَ رمزٍ (بوابة الإعدادات)، فتتحقق وسيلةُ الفتح دائماً.
    // م96 — حتى لو التفَّ أحدٌ على المفتاح: لا قفلَ بلا وسيلة فتح (رمز أو
    // بصمة) — قفلٌ لا مفتاح له حبسٌ لا أمان.
    final db = ref.read(localDbProvider);
    if (!lockOnStartEnabled(db)) return;
    if (!hasLockVerifier(db) && !biometricEnabled(db)) return;
    final timeout = ref.read(idleTimeoutProvider);
    if (DateTime.now().difference(_lastActivity) >= timeout) {
      ref.read(lockedProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(lockedProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markActive(),
      onPointerMove: (_) => _markActive(),
      onPointerSignal: (_) => _markActive(),
      child: Stack(
        children: [
          widget.child,
          // الشجرة تحت الغطاء تبقى حيّة — لا عمل يُفقد.
          if (locked) const Positioned.fill(child: _LockOverlay()),
        ],
      ),
    );
  }
}

class _LockOverlay extends ConsumerStatefulWidget {
  const _LockOverlay();

  @override
  ConsumerState<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<_LockOverlay> {
  final _ctl = TextEditingController();
  String? _error;
  bool _busy = false;

  /// هل تُعرَض البصمة؟ يُحسَب مرّةً عند البناء الأول: مفعَّلةٌ في الإعدادات
  /// **و** متاحةٌ على العتاد. تبقى `false` حتى يعود الفحص كي لا يومض الزر.
  bool _bioOffered = false;

  // م91 — خنق المحاولات (انظر lockThrottleProvider): عدّاد إخفاقات وسقف
  // انتظار، في ذاكرة الغطاء وحدها.
  int _fails = 0;
  DateTime? _coolUntil;

  @override
  void initState() {
    super.initState();
    _maybeOfferBiometric();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _maybeOfferBiometric() async {
    // م91 — كان هنا شرطُ `hasLockVerifier` أيضاً، فحُجبت البصمة عمّن
    // يحتاجها أشدّ الحاجة: داخلُ Google بلا مُتحقِّق (توثيق م88 وَعَد
    // بعكس ذلك حرفياً). مصادقة نظام التشغيل حجّةٌ كافية بذاتها — البصمة
    // تعمل وحدها، والمُتحقِّق حين يوجد يبقى البديل الدائم.
    final db = ref.read(localDbProvider);
    if (!biometricEnabled(db)) return;
    final available = await ref.read(biometricAuthProvider).isAvailable();
    if (available && mounted) {
      setState(() => _bioOffered = true);
      _promptBiometric(); // اعرضها فوراً — هذا سببُ تفعيلها: سرعة
    }
  }

  Future<void> _promptBiometric() async {
    if (_busy) return;
    final db = ref.read(localDbProvider);
    final ok = await ref
        .read(biometricAuthProvider)
        .authenticate('افتح جلسة العيادة ببصمتك');
    // نجاحٌ ⇒ رفعُ القفل. إخفاقٌ/إلغاءٌ ⇒ لا شيء: يبقى الرمز متاحاً.
    if (ok && mounted) {
      recordAudit(db, action: AuditAction.unlock);
      _ctl.clear();
      ref.read(lockedProvider.notifier).state = false;
    }
  }

  void _unlock() {
    if (_busy) return;
    // م91 — نافذة الخنق: تتابعُ إخفاقٍ بلغ السقف ⇒ رفضٌ فوري حتى تنقضي،
    // حتى لو كان الإدخال الحالي صحيحاً (وإلا واصل المخمِّن قصفه بلا كلفة).
    final throttle = ref.read(lockThrottleProvider);
    final now = DateTime.now();
    final cool = _coolUntil;
    if (cool != null && now.isBefore(cool)) {
      final secs = (cool.difference(now).inMilliseconds / 1000).ceil();
      setState(() =>
          _error = 'محاولات كثيرة — انتظر $secs ثانية ثم أعد المحاولة');
      return;
    }
    setState(() => _busy = true);
    final db = ref.read(localDbProvider);
    final ok = verifyLock(db, _ctl.text);
    if (ok) {
      _fails = 0;
      _coolUntil = null;
      recordAudit(db, action: AuditAction.unlock);
      _ctl.clear();
      ref.read(lockedProvider.notifier).state = false;
    } else {
      _fails++;
      if (_fails >= throttle.maxFails) {
        // النافذة تُحسب من **اكتمال** الإخفاق لا من بدء المحاولة: التحقق
        // نفسه (PBKDF2) يستهلك مئات المللي ثانية، ولو حُسبت من البدء
        // لانقضى جزءٌ منها قبل أن يرى المستخدم الرفض أصلاً.
        _coolUntil = DateTime.now().add(throttle.window);
        _fails = 0;
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = ok
            ? null
            : lockVerifierKind(db) == 'pin'
                ? 'الرمز غير صحيح'
                : 'كلمة المرور غير صحيحة';
      });
    }
  }

  Future<void> _signOut() async {
    final db = ref.read(localDbProvider);
    recordAudit(db, action: AuditAction.logout);
    clearLockVerifier(db);
    ref.read(lockedProvider.notifier).state = false;
    await ref.read(authProvider.notifier).logout();
  }

  /// م91 — سطر الحال تحت العنوان، صادقاً مع ما هو متاح فعلاً:
  ///   • مُتحقِّق موجود ⇒ نص الخمول المعهود.
  ///   • بصمة وحدها ⇒ وجّه إليها واذكر بديل الرمز في الإعدادات.
  ///   • لا شيء ⇒ اشرح المخرج بلا إيهام: الخروج آمن، والرمز يُعيَّن بعده.
  String _subtitle(bool canUnlock) {
    if (canUnlock) {
      return 'أُقفلت تلقائياً بعد فترة خمول. عملك محفوظ كما تركته.';
    }
    if (_bioOffered) {
      return 'أُقفلت تلقائياً بعد فترة خمول. افتحها ببصمتك — وبإمكانك '
          'تعيين «رمز قفل» من الإعدادات كبديلٍ دائم.';
    }
    return 'أُقفلت تلقائياً ولا وسيلة فتحٍ محفوظة على هذا الجهاز. '
        'سجّل الخروج ثم ادخل من جديد — بياناتك مصانة كما هي — '
        'ثم عيِّن «رمز قفل التطبيق» من الإعدادات (قسم قفل الدخول) '
        'أو فعِّل البصمة كي لا يتكرر هذا.';
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(localDbProvider);
    final canUnlock = hasLockVerifier(db);
    // م91 — سمِّ المطلوب باسمه: داخلُ كلمة المرور يُسأل كلمته، وصاحبُ
    // الرمز يُسأل رمزه بلوحة أرقام — لا حقلَ «كلمة مرور» لمن لا كلمة له.
    final isPin = canUnlock && lockVerifierKind(db) == 'pin';
    return Material(
      color: const Color(0xF20A3024),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded,
                    size: 46, color: BrandColors.goldLight),
                const SizedBox(height: 14),
                const Text('الجلسة مقفلة',
                    key: Key('idle-lock-title'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  _subtitle(canUnlock),
                  key: const Key('idle-lock-guidance'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 20),
                if (canUnlock) ...[
                  TextField(
                    key: const Key('idle-lock-field'),
                    controller: _ctl,
                    obscureText: true,
                    autofocus: true,
                    keyboardType: isPin ? TextInputType.number : null,
                    onSubmitted: (_) => _unlock(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: isPin ? 'رمز القفل' : 'كلمة المرور',
                      hintStyle: const TextStyle(color: Colors.white38),
                      errorText: _error,
                      filled: true,
                      fillColor: Colors.white10,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('idle-lock-unlock'),
                      onPressed: _busy ? null : _unlock,
                      child: const Text('فتح'),
                    ),
                  ),
                ],
                // م87 — زرّ البصمة: بديلٌ أسرع، يظهر حين تُفعَّل وتتاح.
                // م91 — خارج شرط المُتحقِّق: تعمل وحدها لمن لا رمز له.
                if (_bioOffered) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const Key('idle-lock-biometric'),
                    onPressed: _busy ? null : _promptBiometric,
                    icon: Icon(Icons.fingerprint_rounded,
                        color: BrandColors.goldLight),
                    label: const Text('الدخول بالبصمة',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('idle-lock-signout'),
                  onPressed: _signOut,
                  child: const Text('تسجيل الخروج',
                      style: TextStyle(color: Colors.white60)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
