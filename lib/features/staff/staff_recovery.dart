/// ============================================================================
///  استرداد كلمة مرور الإدارة + تفعيل/إيقاف نظام الموظفين
/// ============================================================================
///
///  نظام الموظفين اختياريٌّ (قرار المالك): طبيبٌ وحده لا يحتاجه، فيبقى في
///  «الوضع الفردي» بلا دخولٍ ولا كلمة مرور. متى شاء (توظيفُ مساعد) يُفعّله
///  من الإعدادات فيُنشئ حساب إدارةٍ أول ويُطلَب الدخول من بعدها.
///
///  ولأن كلمة المرور تحمي **الواجهة** فقط — لا تشفّر البيانات (مفتاح
///  SQLCipher في مخزن النظام مستقلٌّ عنها) — فاستعادتها آمنةٌ تماماً بلا
///  فقد. طبقتان (قرار المالك: «رمز استرداد + سحابي»):
///    ١) **رمز استرداد** يُعرَض مرةً عند الإنشاء (مُخزَّن مُجزّأً).
///    ٢) **الحساب السحابي** حين يكون الاتصال مضبوطاً (إثبات ملكية).
///    ٣) وإدارةٌ أخرى تُعيد التعيين إن وُجدت (عبر شاشة إدارة المستخدمين).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/audit/audit_trail.dart' show recordAudit;
import 'staff_session.dart' show applyStaffSession, currentStaffProvider;
import 'staff_store.dart';

/// يعرض رمز الاسترداد **مرةً واحدة** بخطٍّ كبير مع نسخٍ وتحذيرٍ صريح.
/// لا يُغلَق إلا بتأكيد «حفظتُه» (barrierDismissible=false) كي لا يمرّ
/// المستخدم عليه سهواً — فهو طريقه الوحيد للاستعادة بلا سحابة.
Future<void> showRecoveryCodeDialog(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dctx) => AlertDialog(
      key: const Key('recovery-code-dialog'),
      title: const Row(children: [
        Icon(Icons.vpn_key_rounded, color: BrandColors.goldDark, size: 22),
        SizedBox(width: 8),
        Expanded(child: Text('رمز الاسترداد', style: TextStyle(fontSize: 16))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'احفظ هذا الرمز في مكانٍ آمن (صوّره أو اطبعه). هو طريقك '
            'لاستعادة الدخول إن نسيت كلمة المرور — ولن يُعرض مرةً أخرى.',
            style: TextStyle(fontSize: 12.5, height: 1.7, color: BrandColors.mut),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              color: BrandColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color.fromRGBO(201, 162, 75, .4)),
            ),
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: BrandColors.brandText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('recovery-copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(dctx).showSnackBar(const SnackBar(
                  content: Text('نُسخ رمز الاسترداد'),
                  duration: Duration(milliseconds: 1200)));
            },
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('نسخ الرمز'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('recovery-saved'),
          style: FilledButton.styleFrom(backgroundColor: BrandColors.brand600),
          onPressed: () => Navigator.pop(dctx),
          child: const Text('حفظتُه — متابعة'),
        ),
      ],
    ),
  );
}

/// حوار «نسيت كلمة المرور؟» للحساب [accountId]/[username]. مساران:
///   • رمز الاسترداد (دائماً).
///   • الحساب السحابي (حين `cloudConfigProvider != null`).
/// عند النجاح يعيّن كلمة مرورٍ جديدة، ويولّد رمز استردادٍ جديداً ويعرضه.
/// يعيد true عند نجاح إعادة التعيين.
Future<bool> showForgotPasswordDialog(
  BuildContext context,
  WidgetRef ref, {
  required String accountId,
  required String username,
  required String displayName,
}) async {
  final store = StaffStore(ref.read(reposProvider).settings);
  final hasCloud = ref.read(cloudConfigProvider) != null;
  final hasCode = store.hasRecoveryCode(accountId);

  final codeCtl = TextEditingController();
  final emailCtl = TextEditingController();
  final cloudPassCtl = TextEditingController();
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  // المسار الافتراضي: الرمز إن وُجد، وإلا السحابة.
  var useCloud = !hasCode && hasCloud;
  String? error;
  var busy = false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSt) {
        Future<void> submit() async {
          final np1 = p1.text, np2 = p2.text;
          if (np1.length < 4) {
            setSt(() => error = 'كلمة المرور الجديدة 4 محارف على الأقل');
            return;
          }
          if (np1 != np2) {
            setSt(() => error = 'كلمتا المرور غير متطابقتين');
            return;
          }
          setSt(() {
            busy = true;
            error = null;
          });
          final db = ref.read(reposProvider).db;
          if (useCloud) {
            // إثبات ملكية الحساب السحابي (بريد + كلمة مرور Supabase).
            try {
              await ref
                  .read(authServiceProvider)
                  .login(emailCtl.text.trim(), cloudPassCtl.text,
                      remember: false);
            } catch (_) {
              setSt(() {
                busy = false;
                error = 'تعذّر التحقق من الحساب السحابي — راجع البريد وكلمة المرور';
              });
              return;
            }
            store.adminResetPassword(accountId, np1);
            recordAudit(db,
                action: 'staff.password.reset',
                entity: 'staff',
                entityId: accountId,
                detail: {'via': 'cloud', 'username': username});
          } else {
            final done =
                store.resetPasswordWithRecovery(accountId, codeCtl.text, np1);
            if (!done) {
              setSt(() {
                busy = false;
                error = 'رمز الاسترداد غير صحيح';
              });
              return;
            }
            recordAudit(db,
                action: 'staff.password.reset',
                entity: 'staff',
                entityId: accountId,
                detail: {'via': 'recovery-code', 'username': username});
          }
          if (dctx.mounted) Navigator.pop(dctx, true);
        }

        return AlertDialog(
          key: const Key('forgot-password-dialog'),
          title: const Text('استعادة كلمة المرور',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الحساب: $displayName',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.brandText)),
                const SizedBox(height: 4),
                Text(
                  'إعادة تعيين كلمة المرور لا تمسّ أي بيانات — بياناتك '
                  'محفوظةٌ ومشفّرة بمعزلٍ عن كلمة المرور.',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut2),
                ),
                const SizedBox(height: 12),
                // مبدّل المسار (يظهر فقط حين يتاح المساران).
                if (hasCode && hasCloud)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false,
                          label: Text('رمز الاسترداد'),
                          icon: Icon(Icons.vpn_key_rounded, size: 16)),
                      ButtonSegment(
                          value: true,
                          label: Text('الحساب السحابي'),
                          icon: Icon(Icons.cloud_rounded, size: 16)),
                    ],
                    selected: {useCloud},
                    onSelectionChanged: (s) =>
                        setSt(() => useCloud = s.first),
                  ),
                if (hasCode && hasCloud) const SizedBox(height: 12),
                if (!useCloud) ...[
                  if (!hasCode)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'لا يوجد رمز استردادٍ لهذا الحساب.'
                        '${hasCloud ? ' استخدم الحساب السحابي.' : ' راجع حساب إدارةٍ آخر أو إعادة التثبيت.'}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.red),
                      ),
                    ),
                  if (hasCode)
                    TextField(
                      key: const Key('forgot-recovery-code'),
                      controller: codeCtl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'رمز الاسترداد',
                        hintText: 'XXXX-XXXX-XXXX-XXXX',
                      ),
                    ),
                ] else ...[
                  TextField(
                    key: const Key('forgot-cloud-email'),
                    controller: emailCtl,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'البريد الإلكتروني السحابي'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('forgot-cloud-pass'),
                    controller: cloudPassCtl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة مرور الحساب السحابي'),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('forgot-new-pass'),
                  controller: p1,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('forgot-new-pass2'),
                  controller: p2,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(dctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('forgot-submit'),
              style:
                  FilledButton.styleFrom(backgroundColor: BrandColors.brand600),
              onPressed: (busy || (!useCloud && !hasCode)) ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('إعادة التعيين'),
            ),
          ],
        );
      },
    ),
  );

  if (ok == true) {
    // رمز استردادٍ جديد بعد الاستهلاك — يُعرَض مرةً واحدة.
    if (context.mounted) {
      final fresh = store.setRecoveryCode(accountId);
      await showRecoveryCodeDialog(context, fresh);
    }
    return true;
  }
  return false;
}

/// تفعيل نظام الموظفين: إنشاء حساب الإدارة الأول (اسم/دخول/كلمة مرور)،
/// ثم توليد رمز استردادٍ وعرضه، ثم الدخول بالحساب. يعيد true عند النجاح.
/// يُستدعى من الإعدادات في الوضع الفردي (اختيارٌ لا فرض).
Future<bool> showEnableStaffSystemDialog(
    BuildContext context, WidgetRef ref) async {
  final nameCtl = TextEditingController();
  final userCtl = TextEditingController();
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? error;
  var busy = false;

  final created = await showDialog<Map<String, Object?>>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSt) {
        Future<void> submit() async {
          final name = nameCtl.text.trim();
          final username = normalizeUsername(userCtl.text);
          if (name.isEmpty || username.isEmpty) {
            setSt(() => error = 'أدخل الاسم واسم الدخول');
            return;
          }
          if (p1.text.length < 4) {
            setSt(() => error = 'كلمة المرور 4 محارف على الأقل');
            return;
          }
          if (p1.text != p2.text) {
            setSt(() => error = 'كلمتا المرور غير متطابقتين');
            return;
          }
          setSt(() {
            busy = true;
            error = null;
          });
          await Future<void>.delayed(const Duration(milliseconds: 30));
          final store = StaffStore(ref.read(reposProvider).settings);
          final id = store.upsert(
              username: username, name: name, role: 'admin', active: true);
          store.setPassword(id, p1.text);
          final code = store.setRecoveryCode(id);
          recordAudit(ref.read(reposProvider).db,
              action: 'staff.setup',
              entity: 'staff',
              entityId: id,
              detail: {'username': username, 'name': name});
          if (dctx.mounted) {
            Navigator.pop(dctx, {'id': id, 'code': code, 'username': username});
          }
        }

        return AlertDialog(
          key: const Key('enable-staff-dialog'),
          title: const Text('تفعيل نظام الموظفين',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'أنشئ حساب الإدارة. بعد التفعيل سيُطلب تسجيل الدخول عند '
                  'كل فتح — يمكنك لاحقاً إضافة موظفين بصلاحياتٍ محدودة، أو '
                  'إيقاف النظام والعودة للاستخدام الفردي.',
                  style: TextStyle(fontSize: 12, height: 1.7, color: BrandColors.mut),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('enable-name'),
                  controller: nameCtl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'الاسم الظاهر'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('enable-username'),
                  controller: userCtl,
                  decoration:
                      const InputDecoration(labelText: 'اسم الدخول'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('enable-pass'),
                  controller: p1,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'كلمة المرور'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('enable-pass2'),
                  controller: p2,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'تأكيد كلمة المرور'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(dctx),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('enable-submit'),
              style:
                  FilledButton.styleFrom(backgroundColor: BrandColors.brand600),
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('تفعيل وإنشاء الإدارة'),
            ),
          ],
        );
      },
    ),
  );

  if (created == null) return false;
  // عرض رمز الاسترداد مرةً واحدة، ثم الدخول بحساب الإدارة الجديد.
  if (context.mounted) {
    await showRecoveryCodeDialog(context, '${created['code']}');
  }
  final store = StaffStore(ref.read(reposProvider).settings);
  final u = store.byUsername('${created['username']}');
  if (u != null) {
    applyStaffSession(u);
    ref.read(currentStaffProvider.notifier).state = u;
  }
  return true;
}

/// إيقاف نظام الموظفين والعودة للوضع الفردي — يتطلب تأكيداً صريحاً.
/// آمنٌ للبيانات تماماً (لا يمسّ إلا صفوف حسابات الموظفين). يعيد true
/// عند الإيقاف.
Future<bool> showDisableStaffSystemDialog(
    BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      key: const Key('disable-staff-dialog'),
      title: const Text('إيقاف نظام الموظفين',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      content: const Text(
        'سيعود التطبيق للاستخدام الفردي: بلا تسجيل دخولٍ ولا كلمات مرور، '
        'وتُحذف كل حسابات الموظفين وصلاحياتها.\n\n'
        'بياناتك (المرضى والسجلات والمالية) لا تتأثر إطلاقاً. يمكنك '
        'إعادة تفعيل النظام لاحقاً من الإعدادات.',
        style: TextStyle(fontSize: 13, height: 1.7),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('إلغاء')),
        FilledButton(
          key: const Key('disable-confirm'),
          style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('إيقاف والعودة للوضع الفردي'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final repos = ref.read(reposProvider);
  recordAudit(repos.db,
      action: 'staff.disable', entity: 'staff', entityId: 'all');
  StaffStore(repos.settings).disableStaffSystem();
  applyStaffSession(null);
  ref.read(currentStaffProvider.notifier).state = null;
  return true;
}
