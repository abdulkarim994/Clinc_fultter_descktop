/// ============================================================================
///  م93 — قسم «إعدادات الحساب» في الإعدادات
/// ============================================================================
///
///  جسمُ القسم الحادي عشر (يظهر للحسابات السحابية وحدها — القائمة تحجبه في
///  الوضع المحلي). ثلاث بطاقات: البريد (قراءة + نسخ)، كلمة المرور (تعيين
///  أو إعادة تعيين حسب هوية الحساب)، وحذف الحساب (تأكيدٌ بعدّاد 5 ثوانٍ ثم
///  حذفٌ حقيقيٌّ من الخادم وR2 ومسحٌ محليّ وخروج).
///
///  المنطق كلُّه في [AccountAdmin] المحقون؛ هذا الملف واجهةٌ صرفة.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../auth/account_admin.dart';

/// حقل كلمة مرور مقنّع بنمط بطاقات الإعدادات.
class _PwField extends StatelessWidget {
  const _PwField(this.ctl, this.hint, {required this.fieldKey});
  final TextEditingController ctl;
  final String hint;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: ctl,
        obscureText: true,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: const OutlineInputBorder(),
        ),
      );
}

class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  final _oldCtl = TextEditingController();
  final _newCtl = TextEditingController();
  final _confirmCtl = TextEditingController();

  AccountPasswordState _pwState = AccountPasswordState.unknown;
  bool _loadingState = true;
  bool _savingPw = false;
  String? _pwError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPwState());
  }

  @override
  void dispose() {
    _oldCtl.dispose();
    _newCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  AccountAdmin? get _admin => ref.read(accountAdminProvider);

  Future<void> _loadPwState() async {
    final admin = _admin;
    if (admin == null) {
      setState(() => _loadingState = false);
      return;
    }
    final s = await admin.passwordState();
    if (mounted) {
      setState(() {
        _pwState = s;
        _loadingState = false;
      });
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _savePassword() async {
    final admin = _admin;
    if (admin == null || _savingPw) return;
    final isReset = _pwState == AccountPasswordState.hasPassword;
    if (_newCtl.text != _confirmCtl.text) {
      setState(() => _pwError = 'الكلمتان الجديدتان غير متطابقتين');
      return;
    }
    setState(() {
      _savingPw = true;
      _pwError = null;
    });
    try {
      if (isReset) {
        await admin.resetPassword(
            oldPassword: _oldCtl.text, newPassword: _newCtl.text);
      } else {
        await admin.setPassword(_newCtl.text);
      }
      _oldCtl.clear();
      _newCtl.clear();
      _confirmCtl.clear();
      // بعد التعيين أول مرة صار للحساب كلمةُ مرور ⇒ حدّث الحالة.
      final next = await admin.passwordState();
      if (!mounted) return;
      setState(() {
        _pwState = next;
        _savingPw = false;
      });
      _snack(isReset ? 'تم تغيير كلمة المرور' : 'تم تعيين كلمة المرور');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPw = false;
        _pwError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmDelete() async {
    final admin = _admin;
    if (admin == null) return;
    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _DeleteCountdownDialog(),
        ) ??
        false;
    if (!ok || !mounted) return;

    // شاشة حجبٍ أثناء الحذف (لا إلغاء). نلتقط الـNavigator قبل العمل
    // (نمط _runLogout): المسح المحلي الناجح يبدّل حالة المصادقة فيُعاد
    // بناء الجذر إلى شاشة الدخول، فلا نلمس context بعده.
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Row(children: [
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Expanded(child: Text('جارٍ حذف الحساب نهائياً...')),
          ]),
        ),
      ),
    );
    try {
      await admin.deleteAccount();
      // م94 — نجاحٌ ⇒ الحساب زال والجلسة أُنهيت. جذرُ التطبيق صار شاشةَ
      // الدخول (تغيّر حالة المصادقة)، لكن حوارَ الحجب وشاشةَ الإعدادات
      // مساران مكدّسان **فوق** الجذر لا يزيلهما تغيّر الحالة — فتُزال
      // كلها حتى الجذر ليجد المستخدم نفسه على شاشة الدخول تلقائياً.
      navigator.popUntil((r) => r.isFirst);
    } catch (e) {
      navigator.pop(); // إغلاق الحجب — والبقاء حيث هو مع رسالة صريحة
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = () {
      final s = ref.watch(authProvider);
      return s is SignedIn ? s.user.email : '';
    }();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── البريد ──
        _card(
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: BrandColors.brand600.withValues(alpha: .12),
              child: const Icon(Icons.person_rounded,
                  size: 19, color: BrandColors.brand600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('البريد الإلكتروني',
                      style:
                          TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
                  Text(email,
                      key: const Key('account-email'),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(
              key: const Key('account-copy-email'),
              tooltip: 'نسخ البريد',
              icon: const Icon(Icons.copy_rounded, size: 17),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: email));
                _snack('تم النسخ');
              },
            ),
          ]),
        ),

        // ── كلمة المرور ──
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _secH(_loadingState
                  ? 'كلمة المرور'
                  : _pwState == AccountPasswordState.hasPassword
                      ? 'إعادة تعيين كلمة المرور'
                      : 'تعيين كلمة المرور'),
              const SizedBox(height: 4),
              if (_loadingState)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.4))),
                )
              else if (_pwState == AccountPasswordState.unknown)
                Row(children: [
                  const Expanded(
                    child: Text('تعذّر تحديد حالة الحساب — تحقق من الاتصال',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                  TextButton(
                    key: const Key('account-pw-retry'),
                    onPressed: () {
                      setState(() => _loadingState = true);
                      _loadPwState();
                    },
                    child: const Text('إعادة'),
                  ),
                ])
              else ...[
                Text(
                    _pwState == AccountPasswordState.hasPassword
                        ? 'أدخل كلمتك الحالية ثم الجديدة (8 أحرف على الأقل).'
                        : 'دخلت بحساب Google — عيّن كلمة مرور لتدخل بها '
                            'بالبريد أيضاً (8 أحرف على الأقل).',
                    style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
                const SizedBox(height: 10),
                if (_pwState == AccountPasswordState.hasPassword) ...[
                  _PwField(_oldCtl, 'كلمة المرور الحالية',
                      fieldKey: const Key('account-pw-old')),
                  const SizedBox(height: 8),
                ],
                _PwField(_newCtl, 'كلمة المرور الجديدة',
                    fieldKey: const Key('account-pw-new')),
                const SizedBox(height: 8),
                _PwField(_confirmCtl, 'تأكيد كلمة المرور الجديدة',
                    fieldKey: const Key('account-pw-confirm')),
                if (_pwError != null) ...[
                  const SizedBox(height: 8),
                  Text(_pwError!,
                      key: const Key('account-pw-error'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFEF4444))),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('account-pw-save'),
                    onPressed: _savingPw ? null : _savePassword,
                    child: Text(_pwState == AccountPasswordState.hasPassword
                        ? 'تغيير كلمة المرور'
                        : 'تعيين كلمة المرور'),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── حذف الحساب ──
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4455).withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFFFF4455).withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _secH('حذف الحساب', color: const Color(0xFFB91C1C)),
              const SizedBox(height: 4),
              // م94 — بلا أسماء بنيةٍ تحتية: الرسالة بمفاهيم المستخدم
              // (حسابه وبياناته وصوره) لا بأسماء المزوّدين.
              const Text(
                  'حذفٌ نهائي لا رجعة فيه: يُمحى حسابك بكامل بياناته '
                  'وصوره من السحابة ومن هذا الجهاز.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.5, color: Color(0xFF92400E))),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('account-delete-btn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFFF4455)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('حذف الحساب نهائياً',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
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

  Widget _secH(String s, {Color? color}) => Row(children: [
        Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
                color: color ?? BrandColors.gold,
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(s,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      ]);
}

/// حوار التأكيد بعدّاد 5 ثوانٍ: زر التأكيد النهائي معطَّلٌ حتى ينقضي —
/// فلا نقرةَ اندفاعٍ تمحو حساباً. يعيد `true` عند التأكيد.
class _DeleteCountdownDialog extends StatefulWidget {
  const _DeleteCountdownDialog();

  @override
  State<_DeleteCountdownDialog> createState() => _DeleteCountdownDialogState();
}

class _DeleteCountdownDialogState extends State<_DeleteCountdownDialog> {
  int _left = 5;

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// عدٌّ تنازليّ 5→0 بنبضةٍ كل ثانية؛ عند الصفر يُسلَّح زرُّ الحذف.
  Future<void> _run() async {
    for (var i = 4; i >= 0; i--) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _left = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final armed = _left <= 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تأكيد حذف الحساب',
            key: Key('account-delete-title'),
            style: TextStyle(color: Color(0xFFB91C1C))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'سيتم حذف الحساب بكامل معلوماته نهائياً: بياناتك على الخادم، '
                'وكل صور الأشعة، وبيانات هذا الجهاز — بلا إمكانية استرجاع.',
                style: TextStyle(fontSize: 13, height: 1.6)),
            const SizedBox(height: 14),
            Center(
              child: Text(
                armed
                    ? 'يمكنك الآن تأكيد الحذف'
                    : 'يُفعَّل زر الحذف خلال $_left ثوانٍ...',
                key: const Key('account-delete-countdown'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: armed ? const Color(0xFFB91C1C) : BrandColors.mut2),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('account-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('account-delete-confirm'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C)),
            onPressed: armed ? () => Navigator.of(context).pop(true) : null,
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
  }
}
