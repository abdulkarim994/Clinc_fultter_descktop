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
const _goldL = Color(0xFFE4CA85);
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

  /// م180/د — «نسيت كلمة المرور؟»: حوار يؤكد البريد ثم إرسال حقيقي عبر
  /// Supabase (نقطة recover). الخادم لا يفصح عن وجود الحساب — فالرسالة
  /// محايدة عمداً.
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
                'أدخل بريد حسابك وسنرسل لك رابط إعادة التعيين.',
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
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
    final email = ctl.text.trim();
    ctl.dispose();
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
        content: Text('أرسلنا رابط إعادة التعيين إلى بريدك إن كان مسجلاً'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPassword = TextEditingController();

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
    _regEmail.dispose();
    _regPassword.dispose();
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
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authProvider.notifier)
          .register(_regEmail.text, _regPassword.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء الحساب — سجّل الدخول الآن')),
      );
      setState(() => _showRegister = false);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
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
          // ── الشعار: حلقة ذهبية متدرجة تحتضن أيقونة السن ──
          Center(
            child: Container(
              width: 86,
              height: 86,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [_goldL, _goldD],
                ),
                boxShadow: [
                  BoxShadow(
                      color: _gold.withValues(alpha: .35),
                      blurRadius: 26,
                      offset: const Offset(0, 10)),
                ],
              ),
              // م180/د — شعار DENTSHINE الرسمي بدل أيقونة التبويب.
              child: ClipOval(
                child: Image.asset(
                  'assets/icon/icon-512.png',
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // م180/د — اسم العلامة بخط غامق من هوية التطبيق.
          const Text(
            'DENTSHINE',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: Color(0xFF114A38), // أخضر داكن — تباين واضح جداً
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'لعيادة أكثر ذكاءً وتنظيمًا',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _goldD,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),

          // ── الحقول (الترتيب الحرفي: 0 بريد، 1 كلمة المرور) ──
          // م180/د — المبدّل المنزلق أعلى الحقول (بدل الطي أسفل الشاشة).
          _authSwitcher(),
          const SizedBox(height: 14),
          if (!_showRegister) ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
                color: Color(0xFF0F2A20), fontSize: 13.5),
            decoration: _dec('البريد الإلكتروني',
                icon: Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            onSubmitted: (_) => _login(),
            style: const TextStyle(
                color: Color(0xFF0F2A20), fontSize: 13.5),
            decoration: _dec('كلمة المرور', icon: Icons.lock_outline_rounded)
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
          Row(
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
                thumbColor: const WidgetStatePropertyAll(Colors.white),
                onChanged: (v) => setState(() => _remember = v),
              ),
            ],
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

          // ── زر الدخول: أخضر متدرج — الظل على الحاوية الخارجية
          //   (يتبع الكبسولة تماماً — لا مستطيل حاداً) والتموج مقصوص. ──
          GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed ? .97 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  gradient: const LinearGradient(
                    begin: Alignment(-0.34, -0.94),
                    end: Alignment(0.34, 0.94),
                    colors: [_brand600, _brand900],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: _brand900.withValues(alpha: .30),
                        blurRadius: 18,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(50),
                  child: InkWell(
                    key: const Key('login-btn'),
                    borderRadius: BorderRadius.circular(50),
                    onTap: _loading ? null : _login,
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
                            _loading ? 'جار الدخول...' : 'تسجيل الدخول',
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
          // م180/د — «نسيت كلمة المرور؟» أسفل زر الدخول مباشرة.
          const SizedBox(height: 10),
          Center(
            child: InkWell(
              key: const Key('forgot-password'),
              onTap: _loading ? null : _forgotPassword,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'نسيت كلمة المرور؟',
                  style: TextStyle(
                    color: _goldD,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: _goldD.withValues(alpha: .5),
                  ),
                ),
              ),
            ),
          ),
          ], // نهاية كتلة «تسجيل الدخول» (م180/د)

          // ── م88 — المتابعة باستخدام Google ──
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('google-signin-btn'),
              onTap: _loading ? null : _googleLogin,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                      color: const Color.fromRGBO(20, 80, 59, .18)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // شعار G بألوانه — مرسومٌ نصّاً كي لا نضيف أصلاً صورةً.
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
          // م180/د — قسم إنشاء الحساب: يظهر باختيار تبويبه من المبدّل
          // المنزلق (زال زر الطي القديم أسفل الشاشة).
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: !_showRegister
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 4),
                      TextField(
                        controller: _regEmail,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                            color: Color(0xFF0F2A20),
                            fontSize: 13.5),
                        decoration: _dec('البريد الإلكتروني',
                            icon: Icons.alternate_email_rounded),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _regPassword,
                        obscureText: true,
                        style: const TextStyle(
                            color: Color(0xFF0F2A20),
                            fontSize: 13.5),
                        decoration: _dec('كلمة المرور (6 أحرف+)',
                            icon: Icons.lock_outline_rounded),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: _gold.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(50),
                        child: InkWell(
                          key: const Key('register-btn'),
                          borderRadius: BorderRadius.circular(50),
                          onTap: _loading ? null : _register,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color:
                                      _gold.withValues(alpha: .45)),
                            ),
                            child: const Text(
                              'إنشاء الحساب',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _goldD,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ],
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
