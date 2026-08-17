/// شاشة تسجيل الدخول — **بطاقة بيضاء بعائلة البوابة** (قرار مالك v21):
/// الخلفية كما هي (تدرج الهوية + النقش الذهبي + الهالات)، والبطاقة في
/// الوسط **بيضاء** بنمط شاشتي الترحيب والإعداد حرفياً (زوايا 22 وحد أخضر
/// شعري وظل ناعم) — عائلة واحدة لكل شاشات الدخول. الشعار الذهبي بأيقونة
/// السن، حقول inp البيضاء بتركيز أخضر، زر دخول **أخضر متدرج** فخم
/// (كزر «بدء تجهيز الحساب») بتصغير لمسي وسبنر داخلي، و«إنشاء حساب جديد»
/// كبسولة ذهبية — **بلا أي تغيير في السلوك**.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

// لوحة الهوية (نفس الشريط/الهيدر).
const _brand600 = Color(0xFF15604A);
const _brand900 = Color(0xFF0A3024);
const _brandDeep = Color(0xFF071E16);
const _gold = Color(0xFFC9A24B);
const _goldD = Color(0xFF9C7A2E);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  /// م180/د — مبدّل منزلق أعلى البطاقة: يمين «تسجيل الدخول» ويسار
  /// «إنشاء حساب جديد»، بخطٍّ متحرك تحت الخيار النشط (هوية مؤشر
  /// تبويبات م173). يستبدل القسم القابل للطي أسفل الشاشة.
  Widget _authSwitcher() => Container(
        key: const Key('auth-switcher'),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(20, 80, 59, .05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color.fromRGBO(20, 80, 59, .10)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 8) / 2;
            return SizedBox(
              height: 40,
              child: Stack(
                children: [
                  // الخط/الحبة المنزلقة: يمين للدخول ويسار للإنشاء.
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: _showRegister
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      width: w,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(10, 48, 36, .10),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                        border: Border(
                          bottom: BorderSide(color: _goldD, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                  Row(children: [
                    _switchTab('تسجيل الدخول', !_showRegister,
                        () => setState(() {
                              _showRegister = false;
                              _error = '';
                            }),
                        key: const Key('auth-tab-login')),
                    _switchTab('إنشاء حساب جديد', _showRegister,
                        () => setState(() {
                              _showRegister = true;
                              _error = '';
                            }),
                        key: const Key('auth-tab-register')),
                  ]),
                ],
              ),
            );
          },
        ),
      );

  Widget _switchTab(String label, bool on, VoidCallback onTap,
          {required Key key}) =>
      Expanded(
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                color: on
                    ? const Color(0xFF114A38)
                    : const Color(0xFF0F2A20).withValues(alpha: .55),
              ),
            ),
          ),
        ),
      );

  /// م186 — «نسيت كلمة المرور؟» صار تدفقاً كاملاً **داخل التطبيق**:
  /// (١) حوار البريد ⇐ إرسال رمز التحقق، (٢) حوار الرمز + كلمة المرور
  /// الجديدة وتأكيدها ⇐ تحقق واستبدال فوري. (رابط البريد القديم كان
  /// يوجّه لصفحة معطوبة — بلاغ المالك — فزال الاعتماد على المتصفح
  /// نهائياً: يعمل على الهاتف والكمبيوتر سواء.) الخادم لا يفصح عن وجود
  /// البريد من عدمه — فالصياغة محايدة عمداً.
  Future<void> _forgotPassword() async {
    final ctl = TextEditingController(text: _email.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          key: const Key('forgot-dialog'),
          title: const Text('إعادة تعيين كلمة المرور',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل بريد حسابك وسنرسل لك رمز تحقق مكوَّناً من 6 أرقام.',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('forgot-email'),
                controller: ctl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('forgot-send'),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('إرسال الرمز'),
            ),
          ],
        ),
      ),
    );
    final email = ctl.text.trim();
    _dialogCtls.add(ctl);
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أرسلنا رمز التحقق إلى بريدك إن كان مسجلاً'),
      ));
      await _resetWithCode(email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// م186 — الخطوة الثانية: الرمز + الكلمة الجديدة وتأكيدها. الخطأ يُعرض
  /// **داخل الحوار** (لا يُغلق) كي يصحح المستخدم الرمز ويعيد مباشرة.
  Future<void> _resetWithCode(String email) async {
    final codeCtl = TextEditingController();
    final passCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    var busy = false;
    String dialogError = '';
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            key: const Key('reset-dialog'),
            title: const Text('أدخل الرمز وكلمة المرور الجديدة',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'أرسلنا الرمز إلى $email — تحقق من صندوق الوارد '
                  'أو الرسائل غير المرغوبة.',
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('reset-code'),
                  controller: codeCtl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: '• • • • • •',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('reset-newpass'),
                  controller: passCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'كلمة المرور الجديدة (6 أحرف+)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('reset-confirm'),
                  controller: confirmCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'تأكيد كلمة المرور الجديدة',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (dialogError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    dialogError,
                    key: const Key('reset-error'),
                    style: const TextStyle(
                        color: Color(0xFFC62828), fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed:
                      busy ? null : () => Navigator.pop(dctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                key: const Key('reset-submit'),
                onPressed: busy
                    ? null
                    : () async {
                        if (passCtl.text != confirmCtl.text) {
                          setDialog(() =>
                              dialogError = 'كلمتا المرور غير متطابقتين');
                          return;
                        }
                        setDialog(() {
                          busy = true;
                          dialogError = '';
                        });
                        try {
                          await ref
                              .read(authServiceProvider)
                              .confirmPasswordReset(
                                email: email,
                                code: codeCtl.text,
                                newPassword: passCtl.text,
                              );
                          if (dctx.mounted) Navigator.pop(dctx, true);
                        } catch (e) {
                          setDialog(() {
                            busy = false;
                            dialogError =
                                '$e'.replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: Text(busy ? 'جار التحقق...' : 'تعيين كلمة المرور'),
              ),
            ],
          ),
        ),
      ),
    );
    _dialogCtls.addAll([codeCtl, passCtl, confirmCtl]);
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم تغيير كلمة المرور — سجّل الدخول بها الآن'),
      ));
    }
  }

  // م186 — متحكمان مشتركان بين التبويبين (قرار المالك: «مربع الإيميل
  // مكانه بتسجيل الدخول وإنشاء حساب») — ما يكتبه المستخدم يبقى عند
  // التبديل، وزال المتحكمان المكرران القديمان للإنشاء.
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// م186 — متحكمات حوارات الاستعادة: تُتلف مع الشاشة لا لحظة إغلاق
  /// الحوار — الإتلاف الفوري كان يفجّر حقول الحوار وهي تُعاد بناءً أثناء
  /// حركة الخروج (A TextEditingController was used after being disposed).
  final _dialogCtls = <TextEditingController>[];

  bool _showPassword = false;
  bool _remember = true;
  bool _loading = false;
  bool _showRegister = false;
  bool _pressed = false; // التصغير اللمسي لزر الدخول.
  bool _cardIn = false; // الدخول المتحرك للبطاقة.
  String _error = '';

  @override
  void initState() {
    super.initState();
    // login-card: انزلاق 28px + تكبير من .95 بمنحنى نابض (~550ms).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _cardIn = true);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    for (final c in _dialogCtls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(_email.text, _password.text, _remember);
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    // م186 — تحقق التطابق قبل أي نداء (حقل التأكيد الجديد).
    if (_password.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authProvider.notifier)
          .register(_email.text, _password.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء الحساب — سجّل الدخول الآن')),
      );
      _confirm.clear();
      setState(() => _showRegister = false);
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// م88 — دخول Google (OAuth PKCE عبر Supabase). البوابة نفسها تتكفّل بما
  /// بعده: جديدٌ ⇒ إعداد إجباري، عائدٌ ⇒ ترحيبٌ باسمه. وحتى اكتمال إعداد
  /// المزوّد، يرمي المزوّدُ الافتراضيّ رسالةً لطيفة تُعرَض هنا بلا انهيار.
  Future<void> _googleLogin() async {
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      await ref.read(authProvider.notifier).signInWithGoogle();
    } catch (e) {
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// حقل عائلة البوابة: أبيض بحد أخضر شفاف وزوايا 12 وتركيز أخضر.
  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color.fromRGBO(15, 42, 32, .55), fontSize: 13.5),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 19, color: _goldD.withValues(alpha: .8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color.fromRGBO(20, 80, 59, .14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1B5E47), width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // ── الخلفية: تدرج الهوية الثلاثي (نفس الشريط) ──
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.34, -0.94),
                end: Alignment(0.34, 0.94),
                stops: [0.0, 0.6, 1.0],
                colors: [_brand600, _brand900, _brandDeep],
              ),
            ),
          ),
        ),
        // ── هالات توهج ناعمة (عمق 2026) ──
        Positioned(
          top: -120,
          right: -80,
          child: _glow(_gold.withValues(alpha: .14), 300),
        ),
        Positioned(
          bottom: -140,
          left: -100,
          child: _glow(_brand600.withValues(alpha: .5), 340),
        ),
        // ── النقش الهندسي الذهبي ──
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _GoldPatternPainter()),
          ),
        ),

        // ── البطاقة الزجاجية المصنفرة بدخول متحرك ──
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedSlide(
              offset: _cardIn ? Offset.zero : const Offset(0, 0.06),
              duration: const Duration(milliseconds: 550),
              curve: const Cubic(0.34, 1.36, 0.64, 1),
              child: AnimatedScale(
                scale: _cardIn ? 1 : .95,
                duration: const Duration(milliseconds: 550),
                curve: const Cubic(0.34, 1.36, 0.64, 1),
                child: AnimatedOpacity(
                  opacity: _cardIn ? 1 : 0,
                  duration: const Duration(milliseconds: 420),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 372),
                    child: Container(
                      key: const Key('login-glass-card'),
                      padding:
                          const EdgeInsets.fromLTRB(26, 30, 26, 24),
                      decoration: BoxDecoration(
                        color: Colors.white, // عائلة بطاقة البوابة
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: const Color.fromRGBO(
                                20, 80, 59, .12)),
                        boxShadow: [
                          BoxShadow(
                            color:
                                _brandDeep.withValues(alpha: .28),
                            blurRadius: 44,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: _cardBody(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _cardBody() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── الشعار الرسمي كاملاً (لوحة الهوية نفسها) ──
          // م182 — الشعار صار لوحةً مربّعة بحوافّ مستديرة تحمل الاسم
          // «DENTSHINE PRO» داخلها، فحُذف القصّ الدائري (كان يبتر النصّ
          // والشريط السفلي) وحلّت محلّه حوافّ مستديرة بنسبة اللوحة نفسها،
          // وحُذف سطر «DENTSHINE» المكرَّر أسفلها (صار داخل الشعار).
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                      color: _gold.withValues(alpha: .30),
                      blurRadius: 28,
                      offset: const Offset(0, 12)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'assets/icon/icon-512.png',
                  width: 118,
                  height: 118,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'لعيادة أكثر ذكاءً وتنظيمًا',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _goldD,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),

          // ── الحقول (الترتيب الحرفي: 0 بريد، 1 كلمة المرور) ──
          // م180/د — المبدّل المنزلق أعلى الحقول (بدل الطي أسفل الشاشة).
          _authSwitcher(),
          const SizedBox(height: 14),
          // ═══ م186 — بنية صفوف واحدة ثابتة الارتفاع للتبويبين ═══
          // كانت البطاقة تقفز حجماً عند التبديل: كتلة الدخول تُخفى كلها
          // وتُبنى كتلة إنشاءٍ مختلفة فيتنقل زر Google من أسفل لأعلى
          // (بلاغ المالك: «المربع بكبر وبصغر»). الآن الصفوف نفسها في
          // التبويبين: البريد وكلمة المرور **نفس الصندوقين** (متحكمان
          // مشتركان — ما يُكتب يبقى عند التبديل)، والصف الثالث «تذكّر» ↔
          // «تأكيد كلمة المرور» بارتفاع مثبّت، والزر الرئيسي واحدٌ يتحول
          // لوناً ونصاً، وما بعده خانتان مثبتتا الارتفاع («نسيت» وGoogle
          // في الدخول، فراغان مكافئان في الإنشاء) — فارتفاع العمود متساوٍ
          // بالبناء لا بالمصادفة، وزر Google صار مسارَ دخولٍ حصراً.

          // ── الصف ١: البريد الإلكتروني (مشترك) ──
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
                color: Color(0xFF0F2A20), fontSize: 13.5),
            decoration: _dec('البريد الإلكتروني',
                icon: Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 12),

          // ── الصف ٢: كلمة المرور (مشتركة، بعين الإظهار) ──
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            onSubmitted: (_) => _showRegister ? _register() : _login(),
            style: const TextStyle(
                color: Color(0xFF0F2A20), fontSize: 13.5),
            decoration: _dec('كلمة المرور (6 أحرف+)',
                    icon: Icons.lock_outline_rounded)
                .copyWith(
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'إخفاء' : 'إظهار',
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _goldD.withValues(alpha: .85),
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── الصف ٣ (ارتفاع مثبت): «تذكّر» ↔ «تأكيد كلمة المرور» ──
          SizedBox(
            height: 50,
            child: Center(
              child: _showRegister
                  ? TextField(
                      key: const Key('reg-confirm'),
                      controller: _confirm,
                      obscureText: true,
                      onSubmitted: (_) => _register(),
                      style: const TextStyle(
                          color: Color(0xFF0F2A20), fontSize: 13.5),
                      decoration: _dec('تأكيد كلمة المرور',
                          icon: Icons.lock_reset_rounded),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'تذكّر بيانات الدخول',
                            style: TextStyle(
                                color: const Color(0xFF0F2A20)
                                    .withValues(alpha: .85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Switch(
                          value: _remember,
                          activeTrackColor: _gold,
                          thumbColor:
                              const WidgetStatePropertyAll(Colors.white),
                          onChanged: (v) =>
                              setState(() => _remember = v),
                        ),
                      ],
                    ),
            ),
          ),
          if (_error.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 68, 85, .12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color.fromRGBO(255, 68, 85, .3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    size: 15, color: Color(0xFFFF8A80)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _error,
                    style: const TextStyle(
                        color: Color(0xFFFF8A80), fontSize: 12),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 4),

          // ── الصف ٤: الزر الرئيسي الواحد — أخضر «تسجيل الدخول» يتحول
          //   ذهبياً «إنشاء الحساب» بانتقالٍ ناعم (الظل يتبع اللون). ──
          GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? .97 : 1,
              duration: const Duration(milliseconds: 120),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  gradient: LinearGradient(
                    begin: const Alignment(-0.34, -0.94),
                    end: const Alignment(0.34, 0.94),
                    colors: _showRegister
                        ? const [_gold, _goldD]
                        : const [_brand600, _brand900],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: (_showRegister ? _goldD : _brand900)
                            .withValues(alpha: .30),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(50),
                  child: InkWell(
                    key: Key(_showRegister ? 'register-btn' : 'login-btn'),
                    borderRadius: BorderRadius.circular(50),
                    onTap: _loading
                        ? null
                        : (_showRegister ? _register : _login),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_loading) ...[
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _loading
                                ? (_showRegister
                                    ? 'جار الإنشاء...'
                                    : 'جار الدخول...')
                                : (_showRegister
                                    ? 'إنشاء الحساب'
                                    : 'تسجيل الدخول'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              // قرار مالك: وزن medium بلا تثخين.
                              fontWeight: FontWeight.w500,
                              letterSpacing: .4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── الصف ٥ (ارتفاع مثبت): «نسيت كلمة المرور؟» ↔ فراغ ──
          SizedBox(
            height: 28,
            child: _showRegister
                ? const SizedBox.shrink()
                : Center(
                    child: InkWell(
                      key: const Key('forgot-password'),
                      onTap: _loading ? null : _forgotPassword,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          'نسيت كلمة المرور؟',
                          style: TextStyle(
                            color: _goldD,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            decorationColor:
                                _goldD.withValues(alpha: .5),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // ── الصف ٦ (ارتفاع مثبت): Google — مسار دخولٍ حصراً (م88) ──
          SizedBox(
            height: 44,
            child: _showRegister
                ? const SizedBox.shrink()
                : Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('google-signin-btn'),
                      onTap: _loading ? null : _googleLogin,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                              color:
                                  const Color.fromRGBO(20, 80, 59, .18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // شعار G بألوانه — مرسومٌ نصّاً كي لا نضيف
                            // أصلاً صورةً.
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4285F4),
                              ),
                              child: const Text('G',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 10),
                            const Flexible(
                              child: Text(
                                'المتابعة باستخدام Google',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Color(0xFF0F2A20),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );

  Widget _glow(Color color, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

/// النقش الهندسي الذهبي — نفس بلاطة login-header-pattern (60×60،
/// معيّنان ودائرة بخطوط ذهبية رفيعة، شفافية 7%).
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
        final o = Path()
          ..moveTo(x + 30, y)
          ..lineTo(x + 60, y + 30)
          ..lineTo(x + 30, y + 60)
          ..lineTo(x, y + 30)
          ..close();
        canvas.drawPath(o, outer);
        final i = Path()
          ..moveTo(x + 30, y + 10)
          ..lineTo(x + 50, y + 30)
          ..lineTo(x + 30, y + 50)
          ..lineTo(x + 10, y + 30)
          ..close();
        canvas.drawPath(i, inner);
        canvas.drawCircle(Offset(x + 30, y + 30), 8, inner);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GoldPatternPainter old) => false;
}
