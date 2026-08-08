/// ============================================================================
///  م91 — حوار «رمز قفل التطبيق»: وسيلةُ فتحٍ لمن دخل بلا كلمة مرور
/// ============================================================================
///
///  العلة التي يسدّها
///  ─────────────────
///  داخلُ Google لا تمرّ كلمةُ مروره بالتطبيق أبداً (جوهر أمان OAuth)، فلا
///  يُخزَّن له مُتحقِّقُ قفلٍ عند الدخول — وكان يبلغ شاشةَ القفل وخيارُها
///  الوحيد «تسجيل الخروج». هذا الحوار يعرض عليه تعيين رمزٍ رقمي محلي
///  **فور دخوله** (قابلاً للتخطي)، ويُستدعى ثانيةً من الإعدادات لمن أجَّل
///  أو أراد التغيير.
///
///  الضمانات — نفس ضمانات مُتحقِّق كلمة المرور حرفياً
///  ──────────────────────────────────────────────────
///    • يُخزَّن مغلّفَ PBKDF2 بملحٍ تحت نفس المفتاح (انظر [storeLockPin])
///      — لا الرمز نفسه، ولا آلية تخزين جديدة.
///    • محليٌّ لكل جهاز: لا يُزامَن ولا يدخل أي حمولة شبكة، ويُمحى مع مسح
///      تبديل الحساب وخروجِ شاشة القفل.
///    • قفلُ شاشةٍ فوق بياناتٍ مشفَّرة أصلاً (م83) — ليس بديلاً عن التشفير.
///
///  مستخدمُ البريد+كلمة المرور لا يمرّ بهذا الحوار إطلاقاً: دخولُه يخزّن
///  مُتحقِّقه دائماً، وقاعدة العرض في الموضعين تتحقق من غياب المُتحقِّق
///  أو من نوعه — انظر [postLoginPinOfferDue] و[pinSettingsEntryVisible].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db/local_db.dart';
import 'idle_lock.dart'
    show hasLockVerifier, lockVerifierKind, storeLockPin, validateLockPin;
import 'lock_prefs.dart' show biometricEnabled, lockOnStartEnabled;

/// سبب فتح الحوار — يُغيّر العنوان والشرح وزرَّ الصرف.
enum PinSetupReason {
  /// فور دخول Google: شرحٌ كامل وزر «لاحقاً» (الحوار اقتراحٌ لا إجبار).
  postLogin,

  /// من بند الإعدادات: تعيينٌ أو تغيير، والصرف «إلغاء».
  settings,
}

/// هل حان عرضُ اقتراح الرمز بعد هذا الدخول؟ دخولٌ صريح (لا جلسة مستعادة)
/// **بلا** مُتحقِّق — أي مسار OAuth حصراً: دخول كلمة المرور يخزّن مُتحقِّقه
/// في نفس اللحظة فلا يستوفي الشرط أبداً.
bool postLoginPinOfferDue(LocalDb db, {required bool justLoggedIn}) =>
    justLoggedIn && !hasLockVerifier(db);

/// هل المُتحقِّق المخزَّن رمزُ قفلٍ (لا كلمةَ مرور)؟
bool hasPinVerifier(LocalDb db) =>
    hasLockVerifier(db) && lockVerifierKind(db) == 'pin';

/// هل يظهر بند «تعيين / تغيير رمز القفل» في الإعدادات؟ لمن لا مُتحقِّق له
/// (Google قبل التعيين) أو من مُتحقِّقُه رمزٌ أصلاً. صاحبُ كلمة المرور لا
/// يرى شيئاً جديداً — كلمتُه هي مفتاحه، ودخولُه القادم يجدّدها حتماً.
bool pinSettingsEntryVisible(LocalDb db) =>
    !hasLockVerifier(db) || hasPinVerifier(db);

/// م91/٥ — التنبيه الصادق: «القفل عند فتح التطبيق» مفعَّل ولا وسيلةَ فتحٍ
/// أصلاً (لا مُتحقِّق ولا بصمة) ⇒ صاحبُ الجهاز سيقابل شاشةَ قفلٍ خيارُها
/// الوحيد الخروج. يُعرض تحذيرٌ وزرُّ تعيينٍ فوري بجواره.
bool lockTrapWarningDue(LocalDb db) =>
    lockOnStartEnabled(db) && !hasLockVerifier(db) && !biometricEnabled(db);

/// يعرض الحوار ويعيد `true` إن حُفظ رمزٌ فعلاً (لا عند التخطي/الإلغاء).
///
/// النجاح يخزّن عبر [storeLockPin] مباشرةً — فيصير `hasLockVerifier`
/// صادقاً لحظةَ عودة الدالة: قفلُ الإقلاع القادم يجد وسيلةَ فتحٍ جاهزة.
Future<bool> showPinSetupDialog(
  BuildContext context, {
  required LocalDb db,
  PinSetupReason reason = PinSetupReason.settings,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    // فور الدخول: قرارٌ صريح (حفظ أو «لاحقاً») لا نقرة تسرّب خارج الحوار —
    // وإلا ضاع الاقتراح سهواً ووصل القفلُ القادم بلا وسيلة فتح.
    barrierDismissible: reason == PinSetupReason.settings,
    builder: (_) => _PinSetupDialog(db: db, reason: reason),
  );
  return saved ?? false;
}

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.db, required this.reason});

  final LocalDb db;
  final PinSetupReason reason;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _pinCtl = TextEditingController();
  final _confirmCtl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  bool get _changing => hasPinVerifier(widget.db);

  String get _title => widget.reason == PinSetupReason.postLogin
      ? 'أنشئ رمزَ قفلٍ لهذا الجهاز'
      : _changing
          ? 'تغيير رمز القفل'
          : 'تعيين رمز القفل';

  String get _explain => widget.reason == PinSetupReason.postLogin
      ? 'دخلتَ بحساب Google، فلا كلمةَ مرورٍ محلية تفتح قفل الشاشة على '
          'هذا الجهاز. عيِّن رمزاً رقمياً (4 أرقام فأكثر — يُنصح بستة) '
          'يفتح القفل بدلها.\n'
          'الرمز يبقى على هذا الجهاز فقط ولا يغادره، ويُمسح عند تسجيل '
          'الخروج.'
      : 'رمزٌ رقمي (4 أرقام فأكثر — يُنصح بستة) يفتح قفل الشاشة على هذا '
          'الجهاز. محليٌّ لا يُزامَن، ويُمسح عند تسجيل الخروج.';

  void _save() {
    final err = validateLockPin(_pinCtl.text, _confirmCtl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    storeLockPin(widget.db, _pinCtl.text);
    Navigator.of(context).pop(true);
  }

  /// حقل رمزٍ مقنَّع بلوحة أرقام. يقبل الأرقام العربية-الهندية أيضاً —
  /// تُطبَّع قبل التخزين والتحقق معاً (انظر normalizePinDigits) فلوحةُ
  /// المستخدم لا تغيّر هوية رمزه.
  Widget _pinField(TextEditingController ctl, String hint,
          {required Key key, void Function(String)? onSubmitted}) =>
      TextField(
        key: key,
        controller: ctl,
        obscureText: true,
        autofocus: ctl == _pinCtl,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]')),
          LengthLimitingTextInputFormatter(12),
        ],
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(_title, key: const Key('pin-setup-title')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_explain,
                  style: const TextStyle(fontSize: 12.5, height: 1.6)),
              const SizedBox(height: 14),
              _pinField(_pinCtl, 'الرمز',
                  key: const Key('pin-setup-field')),
              const SizedBox(height: 10),
              _pinField(_confirmCtl, 'تأكيد الرمز',
                  key: const Key('pin-setup-confirm'),
                  onSubmitted: (_) => _save()),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    key: const Key('pin-setup-error'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFEF4444))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('pin-setup-later'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.reason == PinSetupReason.postLogin
                ? 'لاحقاً'
                : 'إلغاء'),
          ),
          FilledButton(
            key: const Key('pin-setup-save'),
            onPressed: _save,
            child: const Text('حفظ الرمز'),
          ),
        ],
      ),
    );
  }
}
