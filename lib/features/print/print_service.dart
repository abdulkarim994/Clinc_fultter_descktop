/// خدمة الطباعة — تحميل خطي القاهرة من الأصول ثم Printing.layoutPdf
/// (حوار الطباعة الأصلي على ويندوز وأندرويد)، وعند تعذره مشاركة الملف،
/// وعند تعذر الاثنين حفظ PDF بجوار قاعدة البيانات (أفضل جهد لا يفشل أبداً
/// أمام المستخدم). عزل حزمة printing هنا يبقي بناة التقارير أنفسهم دوالَّ
/// نقية قابلة للاختبار بلا منصة.
library;

import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../../app/providers.dart' show appConfigProvider;
import '../../data/db/local_db.dart' show LocalDb;
import '../patients/audit_trail.dart' show AuditAction, recordAudit;
import 'reports.dart';
import '../staff/staff_gate.dart' show staffAllowed;

/// فك dataURL شعارٍ إلى بايتات صورة نقطية (SVG يُتجاهل — حزمة pdf لا
/// ترسمه مباشرة).
Uint8List? decodeLogoDataUrl(Object? logo) {
  final s = '${logo ?? ''}';
  if (!s.startsWith('data:') || s.contains('svg')) return null;
  final i = s.indexOf('base64,');
  if (i < 0) return null;
  try {
    return Uint8List.fromList(base64Decode(s.substring(i + 7)));
  } catch (_) {
    return null;
  }
}

/// v50 — تحويل صورة الشعار إلى أبيض/أسود (رمادية بمصفوفة إنارة Rec.709)
/// عبر dart:ui — لطباعة ملف المريض الرسمية. عند أي فشل يُعاد الأصل
/// (شعار ملون خير من لا شعار).
Future<Uint8List?> grayscalePngBytes(Uint8List? src) async {
  if (src == null) return null;
  try {
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final paint = ui.Paint()
      ..colorFilter = const ui.ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0, 0, 0, 1, 0,
      ]);
    canvas.drawImage(img, ui.Offset.zero, paint);
    final out =
        await rec.endRecording().toImage(img.width, img.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List() ?? src;
  } catch (_) {
    return src;
  }
}

/// تحميل خطوط الطباعة + ضبط شعار المركز من الإعدادات — نقطة الدخول
/// الموحدة لكل بناء PDF (تحقن config.logo في ترويسة الصفحة كما الأصل).
Future<PdfFonts> loadPdfBrand(dynamic ref) async {
  final fonts = await ref.read(pdfFontsProvider.future) as PdfFonts;
  pdfLogoBytes =
      decodeLogoDataUrl((ref.read(appConfigProvider) as Map)['logo']);
  return fonts;
}

/// خطا PDF (قاهرة عادي/عريض) — مرة واحدة لكل جلسة.
final pdfFontsProvider = FutureProvider<PdfFonts>((ref) async {
  final regular = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  // م67 — خط احتياطي يملك الأشكال العربية المعزولة الناقصة من Cairo
  // (أهمها U+FEF1 ياء آخر الكلمة). يُحلّ لكل محرف على حدة فلا يغيّر مظهر
  // Cairo إلا للمحارف المفقودة فعلاً.
  final fallback = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
  return PdfFonts(regular: regular, bold: bold, fallback: fallback);
});

/// طباعة ← مشاركة ← حفظ ملف في {dbDir}/exports.
/// تعيد وصفاً عربياً لما جرى (للسناك بار).
///
/// م79 — [auditDb] اختياري: تمريره يُسجّل حدث تصدير في سجلّ التدقيق.
/// وُضع هنا لا في المستدعين الخمسة عمداً — التسجيل في موضع واحد لا يمكن
/// أن يُنسى عند إضافة تقرير سادس، والنسيان هو ما يجعل سجلّات التدقيق
/// ناقصةً بمرور الوقت.
///
/// **يُسجَّل قبل المحاولة لا بعد النجاح**: تصديرُ بيانات صحية إلى ملف أو
/// طابعة هو الحدث الجدير بالتسجيل، ونجاحه من عدمه تفصيل. ومحاولةٌ فاشلة
/// قد تكون بالضبط ما يبحث عنه المحقّق.
Future<String> printOrSharePdf(
  String dbDir,
  Uint8List bytes,
  String filename, {
  LocalDb? auditDb,
  String? auditEntity,
  String? auditId,
}) async {
  // م119 — بوابة الطباعة المركزية: كل مسارات الطباعة/المشاركة في
  // التطبيق تمر من هنا، فصلاحية واحدة تفرضها جميعاً.
  if (!staffAllowed('print')) {
    return 'الطباعة والمشاركة تتطلبان صلاحية من الإدارة';
  }
  if (auditDb != null) {
    recordAudit(
      auditDb,
      action: AuditAction.exportPdf,
      entity: auditEntity,
      entityId: auditId,
      detail: {'bytes': bytes.length},
    );
  }
  try {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    return 'أُرسل إلى الطابعة';
  } catch (_) {/* لا طابعة/منصة بلا حوار طباعة */}
  try {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return 'فُتحت المشاركة';
  } catch (_) {/* بيئة بلا مشاركة */}
  try {
    final dir = Directory(p.join(dbDir, 'exports'));
    dir.createSync(recursive: true);
    final f = File(p.join(dir.path, filename));
    f.writeAsBytesSync(bytes);
    return 'حُفظ في ${f.path}';
  } catch (e) {
    return 'تعذرت الطباعة: $e';
  }
}
