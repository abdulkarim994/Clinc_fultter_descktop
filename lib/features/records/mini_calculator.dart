/// الآلة الحاسبة المصغرة (م60/م62) — مُستخرجة إلى ملف مشترك (م94) كي
/// تستعملها ورقة «الزيارة السريعة» في بطاقة المريض **وورقة الإدخال
/// الكامل** بالشاشة الرئيسية بهوية واحدة، بلا استيراد دائري بين
/// الشاشتين. المنطق منقول حرفياً بلا أي تغيير سلوكي.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

import '../../core/theme/app_theme.dart';

/// يعرض الحاسبة حواراً ويعيد الناتج رقمياً (null عند الإلغاء).
Future<num?> showMiniCalculator(BuildContext context) =>
    showDialog<num>(context: context, builder: (_) => const _MiniCalculator());

/// م60 — آلة حاسبة صغيرة داخل النافذة: شريط عمليات بسيط (+ − × ÷) مع
/// شاشة، وزر «إدراج» يعيد الناتج ليُوضع في حقل القيمة. لا اعتماديات.
class _MiniCalculator extends StatefulWidget {
  const _MiniCalculator();

  @override
  State<_MiniCalculator> createState() => _MiniCalculatorState();
}

class _MiniCalculatorState extends State<_MiniCalculator> {
  String _expr = '';
  String _display = '0';

  static const _ops = {'+', '-', '×', '÷'};

  void _tap(String t) {
    setState(() {
      if (t == 'C') {
        _expr = '';
        _display = '0';
      } else if (t == '=') {
        // الناتج يصير التعبير الجديد (فيمكن مواصلة الحساب أو الإدراج).
        _expr = _eval(_expr);
        _display = _expr;
      } else if (t == '⌫') {
        _expr = _expr.isEmpty ? '' : _expr.substring(0, _expr.length - 1);
        _display = _expr.isEmpty ? '0' : _expr;
      } else if (t == '%') {
        // م61 — النسبة المئوية: آخر رقم في التعبير ÷ 100 (سلوك الحاسبات
        // البسيطة: 50% ⇒ 0.5).
        final m = RegExp(r'([0-9.]+)$').firstMatch(_expr);
        if (m != null) {
          final v = (double.tryParse(m.group(1)!) ?? 0) / 100;
          _expr = _expr.substring(0, m.start) +
              (v == v.roundToDouble()
                  ? v.toStringAsFixed(0)
                  : '$v');
          _display = _expr;
        }
      } else {
        // منع مشغّلين متتاليين.
        if (_ops.contains(t) &&
            (_expr.isEmpty ||
                _ops.contains(_expr[_expr.length - 1]))) {
          return;
        }
        _expr += t;
        _display = _expr;
      }
    });
  }

  /// تقييم يسار-إلى-يمين بأولوية الضرب/القسمة (كافٍ لجمع أسعار سريع).
  String _eval(String raw) {
    if (raw.isEmpty) return '0';
    final s = raw.replaceAll('×', '*').replaceAll('÷', '/');
    final tokens = <String>[];
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      if ('+-*/'.contains(ch)) {
        if (buf.isNotEmpty) tokens.add(buf.toString());
        tokens.add(ch);
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    if (tokens.isEmpty) return '0';
    // تمريرة أولى: × ÷.
    final pass = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t == '*' || t == '/') {
        final prev = double.tryParse(pass.removeLast()) ?? 0;
        final next = double.tryParse(tokens[++i]) ?? 0;
        pass.add(t == '*'
            ? '${prev * next}'
            : '${next == 0 ? 0 : prev / next}');
      } else {
        pass.add(t);
      }
    }
    // تمريرة ثانية: + −.
    var acc = double.tryParse(pass.first) ?? 0;
    for (var i = 1; i < pass.length; i += 2) {
      final op = pass[i];
      final v = double.tryParse(pass[i + 1]) ?? 0;
      acc = op == '+' ? acc + v : acc - v;
    }
    return acc == acc.roundToDouble()
        ? acc.toStringAsFixed(0)
        : acc.toStringAsFixed(2);
  }

  /// م167/ج — الكيبورد كامل: أرقام (علوية وNumpad) وعمليات وناتج ومسح —
  /// كل مفتاحٍ يمر بنفس محرك _tap القائم حرفياً (لا منطق جديد).
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _tap('=');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _tap('⌫');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete) {
      _tap('C');
      return KeyEventResult.handled;
    }
    // مفاتيح Numpad الصريحة (بعض المنصات لا تبعث character لها).
    final numpad = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.numpadAdd: '+',
      LogicalKeyboardKey.numpadSubtract: '-',
      LogicalKeyboardKey.numpadMultiply: '×',
      LogicalKeyboardKey.numpadDivide: '÷',
      LogicalKeyboardKey.numpadDecimal: '.',
    };
    final np = numpad[k];
    if (np != null) {
      _tap(np);
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty) {
      const map = {
        '0': '0', '1': '1', '2': '2', '3': '3', '4': '4',
        '5': '5', '6': '6', '7': '7', '8': '8', '9': '9',
        '.': '.', '+': '+', '-': '-',
        '*': '×', 'x': '×', '/': '÷', '%': '%', '=': '=',
        'c': 'C', 'C': 'C',
      };
      final t = map[ch];
      if (t != null) {
        _tap(t);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // م62 — ألوان هوية التطبيق (لا البرتقالي): لوح كريمي، مفاتيح بيضاء،
  // أرقام داكنة، عمليات ورموز ذهبية غامقة، «=» أخضر معبأ، C أحمر.
  // والحاسبة مغلّفة LTR فترجع للتخطيط القياسي (العمليات يميناً والأرقام
  // بترتيبها الطبيعي) بدل انعكاس RTL.

  @override
  Widget build(BuildContext context) {
    final dark = BrandColors.darkMode;
    final padBg = dark ? const Color(0xFF0E3D2E) : BrandColors.paperLight;
    final keyBg = dark ? const Color(0xFF15604A) : Colors.white;
    final digit = dark ? const Color(0xFFEAF3EE) : BrandColors.ink;
    const op = BrandColors.goldDark; // العمليات والرموز

    Widget key(String t,
        {Widget? child, Color? bg, Color? fg, VoidCallback? onTap}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Material(
            color: bg ?? keyBg,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('calc-$t'),
              onTap: onTap ?? () => _tap(t),
              child: AspectRatio(
                aspectRatio: 1.15,
                child: Center(
                  child: child ??
                      Text(t,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: fg ?? digit)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: padBg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      // م62 — LTR: تخطيط قياسي (العمليات في العمود الأيمن، الأرقام
      // بترتيبها الطبيعي) بدل انعكاس الواجهة العربية.
      // م167/ج — Focus مستقبِل: الحاسبة تعمل بالكيبورد كاملاً.
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // الشاشة — الرقم محاذى يميناً كالحاسبات القياسية.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _display,
                    key: const Key('calc-display'),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: digit),
                  ),
                ),
              ),
              // الشبكة القياسية — العمليات في العمود الأيمن.
              Row(children: [
                key('C', fg: BrandColors.red),
                key('⌫',
                    child: const Icon(Icons.backspace_outlined,
                        size: 22, color: op)),
                key('%', fg: op),
                key('÷', fg: op),
              ]),
              Row(children: [
                key('7'),
                key('8'),
                key('9'),
                key('×', fg: op),
              ]),
              Row(children: [
                key('4'),
                key('5'),
                key('6'),
                key('-',
                    child: const Text('−',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: op))),
              ]),
              Row(children: [
                key('1'),
                key('2'),
                key('3'),
                key('+', fg: op),
              ]),
              Row(children: [
                key('00', onTap: () {
                  _tap('0');
                  _tap('0');
                }),
                key('0'),
                key('.'),
                key('=',
                    bg: BrandColors.brand600,
                    child: const Text('=',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white))),
              ]),
              const SizedBox(height: 6),
              // م62 — زر إدراج القيمة عريض منفصل أسفل الشبكة (كما كان).
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('calc-insert'),
                  style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.brand600,
                      padding:
                          const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () {
                    final v = double.tryParse(_eval(_expr)) ?? 0;
                    Navigator.of(context).pop(v);
                  },
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('إدراج القيمة',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
      ),
    );
  }
}
