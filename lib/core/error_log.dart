/// ============================================================================
///  م77 — سجلّ أعطال محلي: كيف يعلم المطوّر أن عيادةً تعطّلت؟
/// ============================================================================
///
///  المشكلة
///  ───────
///  لا يوجد في المشروع أي رصد أعطال — لا Sentry ولا أي قناة تلمترية، ولا
///  `FlutterError.onError`، ولا `runZonedGuarded`. فأي استثناء غير ملتقَط
///  في مسار كتابة **يختفي بلا أثر**: لا المستخدم يعلم، ولا المطوّر. في
///  تطبيق سجلّات طبية هذا أسوأ من العطل نفسه.
///
///  ولماذا لا نرسل شيئاً
///  ────────────────────
///  إرسال الأعطال إلى خدمة خارجية يعني قناة خروج جديدة من جهاز يحمل بيانات
///  صحية — وهي مقايضة لا تُتخذ ضمناً في دفعة إصلاح. فالبديل هنا **محلي
///  بالكامل**: ملف مُقيَّد الحجم بجوار القاعدة، يُطلب من العيادة عند
///  التشخيص. لا شبكة، لا اعتماد جديد، ولا مقايضة خصوصية.
///
///  ⚠ الانضباط المحفوظ: رسائل الاستثناءات **قد تحمل بيانات مرضى** (اسم في
///  `ArgumentError`، معاملات استعلام، محتوى حقل). ولأن هذا المشروع يحافظ
///  على صفر تسريب في السجلّات، يمرّ كل نصّ هنا عبر [redactPhi] قبل الكتابة.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// سقف حجم الملف. عند تجاوزه يُقصّ النصف الأقدم — فلا ينمو بلا حدّ على
/// جهاز عيادة، ويبقى الأحدث (وهو المطلوب عند التشخيص) دائماً.
const int kErrorLogMaxBytes = 64 * 1024;

/// عدد الأسطر المحفوظة من أثر المكدس. الأثر لا يحمل **قيماً** — أسماء دوال
/// وملفات وأرقام أسطر فقط — فهو آمن كاملاً ومفيد جداً.
const int kStackLines = 12;

final RegExp _arabicRun = RegExp(r'[؀-ۿ][؀-ۿ\s]*');
final RegExp _digitsRun = RegExp(r'\d{4,}');
final RegExp _emailLike = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');

/// يحجب ما يُرجَّح أنه بيانات مريض من نصّ حرّ.
///
/// المنطق مبنيّ على واقع هذه الشيفرة تحديداً: **المعرّفات إنجليزية
/// والتعليقات والبيانات عربية**. فأي مقطع عربي في رسالة استثناء هو على
/// الأرجح اسم مريض أو ملاحظة سريرية أو اسم خدمة — لا مصطلح تقني. تُحجب
/// كذلك سلاسل الأرقام الطويلة (هواتف، معرّفات) والبُنى الشبيهة بالبريد.
///
/// الحجب متحفّظ عمداً: خسارة بعض السياق التشخيصي أهون بكثير من تسريب اسم
/// مريض إلى ملف قد يُرسَل بالبريد لاحقاً.
///
/// ⚠ الرموز البديلة **بالإنجليزية عمداً** رغم أن الملف كلّه عربي: رمزٌ عربي
/// مثل `<نص>` يقع فريسةَ تمريرة العربية التالية فيُحجَب هو نفسه، فيصير
/// `<بريد>` ← `<<نص>>`. (رُصد بمحاكاة الدالة قبل الاعتماد.)
String redactPhi(String input) => input
    .replaceAll(_emailLike, '<email>')
    .replaceAll(_arabicRun, '<text>')
    .replaceAll(_digitsRun, '<num>');

/// وجهة الكتابة — تُضبط مرة عند الإقلاع بعد معرفة مجلد البيانات.
String? _dir;

void initErrorLog(String dbDir) => _dir = dbDir;

/// للاختبارات: إيقاف الكتابة على القرص.
void disposeErrorLog() => _dir = null;

File? errorLogFile(String dbDir) => File(p.join(dbDir, 'errors.log'));

/// عدّاد داخل التشغيل الواحد — تقرؤه الواجهة بلا لمس القرص.
int errorsThisRun = 0;

/// آخر نوع عطل — للعرض المختصر.
String? lastErrorType;

/// يسجّل عطلاً. **لا يرمي أبداً**: سجلٌّ يُسقط التطبيق أسوأ من لا سجلّ.
void recordError(Object error, StackTrace? stack, {String? context}) {
  errorsThisRun += 1;
  lastErrorType = error.runtimeType.toString();

  final dir = _dir;
  if (dir == null) return; // قبل الإقلاع أو في الاختبارات

  try {
    final buf = StringBuffer()
      ..writeln('── ${DateTime.now().toIso8601String()} ──')
      ..writeln('type   : ${error.runtimeType}')
      ..writeln('context: ${redactPhi(context ?? '-')}')
      ..writeln('message: ${redactPhi(error.toString())}');
    if (stack != null) {
      final lines = stack.toString().split('\n');
      for (final l in lines.take(kStackLines)) {
        if (l.trim().isNotEmpty) buf.writeln('  $l');
      }
    }
    buf.writeln();

    final f = errorLogFile(dir)!;
    f.writeAsStringSync(buf.toString(),
        mode: FileMode.append, flush: false, encoding: utf8);
    _trimIfLarge(f);
  } catch (_) {
    // القرص ممتلئ أو المسار غير قابل للكتابة — لا شيء نفعله، ولا نُسقط.
  }
}

void _trimIfLarge(File f) {
  try {
    if (f.lengthSync() <= kErrorLogMaxBytes) return;
    final text = f.readAsStringSync(encoding: utf8);
    // نُبقي النصف الأحدث ونبدأ من أول فاصل سجلّ كامل كي لا يبقى نصف قيد.
    final half = text.substring(text.length ~/ 2);
    final cut = half.indexOf('── ');
    f.writeAsStringSync(cut >= 0 ? half.substring(cut) : half,
        flush: false, encoding: utf8);
  } catch (_) {/* أفضل جهد */}
}
