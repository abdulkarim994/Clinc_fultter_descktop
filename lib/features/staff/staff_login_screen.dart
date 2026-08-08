/// م118 — شاشة دخول الموظفين (المرحلة 1 من نظام الصلاحيات).
///
///  • لا مستخدمين بعد ⇒ «وضع التأسيس»: إنشاء حساب الإدارة الأول.
///  • خلاف ذلك: اختيار الموظف من قائمة النشطين + كلمة المرور.
///  • قفل مؤقت متصاعد بعد المحاولات الفاشلة، وكل محاولة (نجاحاً وفشلاً)
///    تُسجَّل في سجل التدقيق باسم الحساب.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/audit/audit_trail.dart' show recordAudit;
import 'staff_recovery.dart' show showForgotPasswordDialog;
import 'staff_session.dart';
import 'staff_store.dart';

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final passCtl = TextEditingController();
  final pass2Ctl = TextEditingController();
  final nameCtl = TextEditingController();
  final userCtl = TextEditingController();
  String selectedId = '';
  String? error;
  bool busy = false;
  bool hidePass = true;

  @override
  void dispose() {
    for (final c in [passCtl, pass2Ctl, nameCtl, userCtl]) {
      c.dispose();
    }
    super.dispose();
  }

  StaffStore get _store => StaffStore(ref.read(reposProvider).settings);

  void _enter(Map<String, Object?> user) {
    applyStaffSession(user); // م120 — يختم هوية التدقيق أيضاً.
    // م121 — موظف بلا صلاحية التنقل بين الأشهر يبدأ على الشهر الحالي
    // دائماً (لا يرث شهراً سابقاً تركته جلسة الإدارة).
    if (!staffCan(user, 'months.nav')) {
      final now = DateTime.now();
      ref.read(selectedMonthProvider.notifier).state =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
    }
    ref.read(currentStaffProvider.notifier).state = user;
  }

  // ── وضع التأسيس: إنشاء حساب الإدارة الأول ──
  Future<void> _createFirstAdmin() async {
    final name = nameCtl.text.trim();
    final username = normalizeUsername(userCtl.text);
    final p1 = passCtl.text, p2 = pass2Ctl.text;
    if (name.isEmpty || username.isEmpty) {
      setState(() => error = 'أدخل الاسم واسم الدخول');
      return;
    }
    if (p1.length < 4) {
      setState(() => error = 'كلمة المرور 4 محارف على الأقل');
      return;
    }
    if (p1 != p2) {
      setState(() => error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final store = _store;
    final id = store.upsert(
        username: username, name: name, role: 'admin', active: true);
    store.setPassword(id, p1);
    store.setRecoveryCode(id); // يُبذَر رمز استرداد دائماً (مسارٌ إرثي).
    recordAudit(ref.read(reposProvider).db,
        action: 'staff.setup',
        entity: 'staff',
        entityId: id,
        detail: {'username': username, 'name': name});
    final u = store.byUsername(username);
    if (!mounted) return;
    setState(() => busy = false);
    if (u != null) _enter(u);
  }

  // ── الدخول ──
  Future<void> _login() async {
    final users = _store.listActive();
    final u = users.where((e) => '${e['id']}' == selectedId).toList();
    if (u.isEmpty) {
      setState(() => error = 'اختر الموظف');
      return;
    }
    final username = '${u.first['username']}';
    setState(() {
      busy = true;
      error = null;
    });
    // مهلة قصيرة تسمح برسم مؤشر الانشغال قبل حساب الهاش (PBKDF2 ثقيل عمداً).
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final res = _store.login(username, passCtl.text);
    final db = ref.read(reposProvider).db;
    if (!mounted) return;
    setState(() => busy = false);
    switch (res.status) {
      case StaffLoginStatus.ok:
        recordAudit(db,
            action: 'staff.login',
            entity: 'staff',
            entityId: '${res.user?['id']}',
            detail: {'username': username});
        passCtl.clear();
        _enter(res.user!);
      case StaffLoginStatus.locked:
        setState(() =>
            error = 'الحساب مقفول مؤقتاً — أعد المحاولة بعد ${res.lockedForSeconds} ثانية');
      case StaffLoginStatus.wrongPassword:
        recordAudit(db,
            action: 'staff.login.fail',
            entity: 'staff',
            detail: {'username': username});
        setState(() => error = res.lockedForSeconds > 0
            ? 'كلمة مرور خاطئة — قُفل الحساب ${res.lockedForSeconds} ثانية'
            : 'كلمة المرور خاطئة');
      case StaffLoginStatus.inactive:
        setState(() => error = 'هذا الحساب موقوف — راجع الإدارة');
      case StaffLoginStatus.notFound:
        setState(() => error = 'الحساب غير موجود');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StaffStore(ref.watch(reposProvider).settings);
    final setup = !store.hasAnyUser;
    final users = store.listActive();
    if (!setup && selectedId.isEmpty && users.isNotEmpty) {
      selectedId = '${users.first['id']}';
    }
    return Scaffold(
      backgroundColor: BrandColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: BrandColors.brandGradient,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color.fromRGBO(201, 162, 75, .4)),
                    ),
                    child: Icon(
                        setup
                            ? Icons.admin_panel_settings_rounded
                            : Icons.lock_person_rounded,
                        size: 36,
                        color: BrandColors.goldLight),
                  ),
                  const SizedBox(height: 14),
                  Text(setup ? 'إنشاء حساب الإدارة' : 'دخول الموظفين',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 4),
                  Text(
                      setup
                          ? 'أول تشغيل لنظام الصلاحيات: أنشئ حساب الإدارة — '
                              'به تدير الموظفين وصلاحياتهم.'
                          : 'اختر اسمك وأدخل كلمة مرورك لبدء وردية عملك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, height: 1.6, color: BrandColors.mut)),
                  const SizedBox(height: 20),
                  if (setup) ...[
                    TextField(
                      key: const Key('setup-name'),
                      controller: nameCtl,
                      decoration:
                          const InputDecoration(labelText: 'الاسم الظاهر'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('setup-username'),
                      controller: userCtl,
                      decoration: const InputDecoration(
                          labelText: 'اسم الدخول (لاتيني قصير)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('setup-pass'),
                      controller: passCtl,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'كلمة المرور'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('setup-pass2'),
                      controller: pass2Ctl,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور'),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      key: const Key('login-user'),
                      isExpanded: true,
                      initialValue:
                          selectedId.isEmpty ? null : selectedId,
                      decoration:
                          const InputDecoration(labelText: 'الموظف'),
                      items: [
                        for (final u in users)
                          DropdownMenuItem(
                            value: '${u['id']}',
                            child: Text(
                                '${u['name']}'
                                '${'${u['shift'] ?? ''}'.isEmpty ? '' : ' (${u['shift']})'}'
                                '${u['role'] == 'admin' ? ' — إدارة' : ''}',
                                style: const TextStyle(fontSize: 13.5)),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => selectedId = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('login-pass'),
                      controller: passCtl,
                      obscureText: hidePass,
                      onSubmitted: (_) => busy ? null : _login(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        suffixIcon: IconButton(
                          icon: Icon(hidePass
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                          onPressed: () =>
                              setState(() => hidePass = !hidePass),
                        ),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('staff-enter'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.brand600,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26)),
                    ),
                    onPressed:
                        busy ? null : (setup ? _createFirstAdmin : _login),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(
                            setup
                                ? Icons.check_circle_rounded
                                : Icons.login_rounded,
                            size: 19),
                    label: Text(setup ? 'إنشاء الحساب والدخول' : 'دخول',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  // «نسيت كلمة المرور؟» — استعادةٌ بالرمز أو الحساب السحابي
                  // (لا تظهر في وضع التأسيس؛ تعمل على الحساب المختار).
                  if (!setup) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      key: const Key('forgot-password-link'),
                      onPressed: busy ? null : _forgotPassword,
                      child: const Text('نسيت كلمة المرور؟',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final users = _store.listActive();
    final sel = users.where((e) => '${e['id']}' == selectedId).toList();
    if (sel.isEmpty) {
      setState(() => error = 'اختر الحساب أولاً');
      return;
    }
    final u = sel.first;
    await showForgotPasswordDialog(
      context,
      ref,
      accountId: '${u['id']}',
      username: '${u['username']}',
      displayName: '${u['name']}',
    );
    // بعد إعادة التعيين (إن تمّت) يبقى المستخدم على شاشة الدخول ليدخل
    // بكلمته الجديدة — لا دخول تلقائياً (قرار أمني: إعادة التعيين ليست دخولاً).
    if (mounted) setState(() {});
  }
}
