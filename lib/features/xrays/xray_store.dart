/// مخزن الأشعة المحلي — نقل جوهر image.service + xrays.service:
/// الإدخال يضغط الصورة بنفس درجات uploadXrayImage (حسب الحجم: 1200/50 —
/// 1600/60 — 1800/70 — 2000/80) ويحفظ النسخة الكاملة محلياً في ملف تحت
/// مجلد القاعدة (نظير IndexedDB — طابور الرفع إلى R2 في م5 يقرأ منه)،
/// ويولّد مصغرة ≈300px تُخزَّن data URL في صف xrays (upload_status=pending
/// حتى يؤكد الرفع في م5). مفاتيح الصور بنفس الصيغة xray/{uid}/{name}/{ts}_{file}.
/// مرايا الإعداد (patientXrays/xrayMeta) دوال نقية فوق config — كما في
/// onXrayUpload/onXrayDelete/saveRenameXray — تُكتب عبر settings.set في الواجهة.
library;

import '../../data/db/blob_vault.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/utils/js_compat.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/feature_flags.dart'
    show isClinicXrayIsolationEnabled;
import '../patients/clinic_scope.dart' show medicalScopedKey;

typedef JMap = Map<String, Object?>;

const maxXrayFileSizeMb = 25;

/// م-عزل الهوية — مفتاح معرض الأشعة الهوياتي: «اسم|أرقام الهاتف» متى
/// عُرف هاتف، وإلا الاسمُ وحده حرفياً (السلوك القائم).
///
/// **لِمَ الهاتفُ وحده لا العيادة في مفتاح السطل؟** عزلُ العيادة للأشعة
/// قائمٌ سلفاً في طبقة الوسم/الترشيح (`isolationFilteredKeys` على
/// `xrayMeta[key].clinic`)، فإقحامُ العيادة في مفتاح السطل تكرارٌ يفصم
/// المعرضَ القديم (المخزَّن بالاسم وحده) بلا فائدة. المُمَيِّز الذي يفصل
/// السميّين هو الهاتف — وهو هويتهم في الخلفية — فيكفي وحده هنا. (توأم
/// `medicalScopedKey` بعيادةٍ فارغة: نفس صياغة اللاحقة الرقمية.)
String xrayGalleryKey(String patient, {Object? phone}) =>
    medicalScopedKey(patient, '', phone);

/// bytes ← data URL (أو null).
Uint8List? dataUrlBytes(Object? dataUrl) {
  final s = '${dataUrl ?? ''}';
  final i = s.indexOf('base64,');
  if (!s.startsWith('data:') || i < 0) return null;
  try {
    return base64Decode(s.substring(i + 7));
  } catch (_) {
    return null;
  }
}

List<String> _keysAtBucket(JMap cfg, String bucketKey) {
  final px = cfg['patientXrays'];
  final list = px is Map ? px[bucketKey] : null;
  return list is List
      ? [
          for (final k in list)
            if (k is String && k.isNotEmpty) k,
        ]
      : const [];
}

/// مفاتيح معرض مريض من الإعدادات — config.patientXrays[key].
/// م-عزل الهوية — **قراءة متدرجة** (نمط clinic_scope/treatment_plan_store):
/// مفتاح الهوية «اسم|هاتف» أولاً ثم المدخل القديم بالاسم وحده — اتحاداً
/// بلا تكرار. الصور القديمة (المخزَّنة بالاسم) تبقى ظاهرةً دائماً (لا فقد)،
/// والجديدة تحت مفتاح الهوية معزولةٌ عن السميّ. غياب الهاتف يجعل المفتاحين
/// الاسمَ نفسه ⇒ السلوك القائم حرفياً (سطل الاسم وحده).
List<String> xrayKeysFor(JMap cfg, String patient, {Object? phone}) {
  final buckets = <String>{
    xrayGalleryKey(patient, phone: phone),
    patient.trim(),
  };
  final out = <String>[];
  final seen = <String>{};
  for (final b in buckets) {
    for (final k in _keysAtBucket(cfg, b)) {
      if (seen.add(k)) out.add(k);
    }
  }
  return out;
}

/// بيانات صورة من الإعدادات — config.xrayMeta[key] = {name, createdAt, clinic}.
JMap xrayMetaFor(JMap cfg, String key) {
  final m = cfg['xrayMeta'];
  final v = m is Map ? m[key] : null;
  return v is Map ? Map<String, Object?>.from(v) : const {};
}

/// المرحلة H — ترشيح العزل بالعيادة (قراءة فقط، خلف العلم): الصور
/// الموسومة تظهر في عيادتها وحدها، وغير الموسومة (القديمة) تظهر دائماً
/// — لا تختفي صورة قديمة أبداً (xrayList حرفياً).
List<String> isolationFilteredKeys(
    JMap cfg, List<String> keys, String clinic) {
  if (!isClinicXrayIsolationEnabled() || clinic.isEmpty) return keys;
  return [
    for (final k in keys)
      if ('${xrayMetaFor(cfg, k)['clinic'] ?? ''}'.isEmpty ||
          '${xrayMetaFor(cfg, k)['clinic']}' == clinic)
        k,
  ];
}

/// إضافة مفتاح للمعرض + بياناته — نفس onXrayUpload (بدون إعادة هيكلة البنية).
/// م-عزل الهوية — الكتابة تذهب لمفتاح الهوية «اسم|عيادة|هاتف» وحده
/// (نسخ-عند-الكتابة): صورةُ سميٍّ لا تُلحق ببطاقة سميّه.
JMap addXrayKeyToConfig(
  JMap cfg,
  String patient,
  String key,
  String displayName, {
  String clinic = '',
  Object? phone,
}) {
  final bucket = xrayGalleryKey(patient, phone: phone);
  final px = Map<String, Object?>.from(
      cfg['patientXrays'] is Map ? cfg['patientXrays'] as Map : {});
  // الإضافة على مفتاح الهوية فقط (لا نضخّم سطل الاسم القديم).
  px[bucket] = [..._keysAtBucket(cfg, bucket), key];
  final meta = Map<String, Object?>.from(
      cfg['xrayMeta'] is Map ? cfg['xrayMeta'] as Map : {});
  meta[key] = {
    'name': displayName.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    'createdAt': jsNow(),
    'clinic': clinic,
  };
  return {...cfg, 'patientXrays': px, 'xrayMeta': meta};
}

/// حذف مفتاح — إزالة بالقيمة (لا بالفهرس الخام) كما في onXrayDelete.
/// م-عزل الهوية — الإزالة عابرة للمفاتيح المتدرجة (هوية/عيادة/اسم قديم):
/// المفتاح يُحذف من أيّ سطلٍ يقع فيه، فتُحذف الصورة أينما خُزِّنت.
JMap removeXrayKeyFromConfig(JMap cfg, String patient, String key,
    {String clinic = '', Object? phone}) {
  final buckets = <String>{
    xrayGalleryKey(patient, phone: phone),
    patient.trim(),
  };
  final px = Map<String, Object?>.from(
      cfg['patientXrays'] is Map ? cfg['patientXrays'] as Map : {});
  for (final b in buckets) {
    if (px[b] is! List) continue;
    px[b] = [
      for (final k in _keysAtBucket(cfg, b))
        if (k != key) k,
    ];
  }
  final meta = Map<String, Object?>.from(
      cfg['xrayMeta'] is Map ? cfg['xrayMeta'] as Map : {});
  meta.remove(key);
  return {...cfg, 'patientXrays': px, 'xrayMeta': meta};
}

/// إعادة تسمية — saveRenameXray.
JMap renameXrayInConfig(JMap cfg, String key, String newName) {
  final meta = Map<String, Object?>.from(
      cfg['xrayMeta'] is Map ? cfg['xrayMeta'] as Map : {});
  meta[key] = {...xrayMetaFor(cfg, key), 'name': newName.trim()};
  return {...cfg, 'xrayMeta': meta};
}

/// إعادة تخطيط مفتاح مؤقت ← مفتاح الخادم (بعد رفعٍ سكّ العامل مفتاحه) —
/// بالقيمة ومع الحفاظ على الترتيب، وتُنقل بيانات الصورة معه.
/// م-عزل الهوية — **عابرٌ للأسطل**: خط أنابيب الرفع يمرّر اسم المريض
/// الخام (بلا هاتف)، والمعرض الآن بمفتاح الهوية؛ فنبدّل المفتاح المؤقت
/// في أيّ سطلٍ يحويه (لا سطل الاسم وحده) — فلا يبقى إعدادٌ يشير لمفتاح
/// مؤقتٍ بعد الاستبدال على أي جهاز. [patient] محتفظ به للتوافق التوقيعي.
JMap remapXrayKeyInConfig(
    JMap cfg, String patient, String tempKey, String serverKey) {
  final px = Map<String, Object?>.from(
      cfg['patientXrays'] is Map ? cfg['patientXrays'] as Map : {});
  for (final entry in px.entries.toList()) {
    final v = entry.value;
    if (v is! List) continue;
    if (!v.any((k) => k == tempKey)) continue;
    px[entry.key] = [
      for (final k in v)
        if (k is String && k.isNotEmpty) (k == tempKey ? serverKey : k),
    ];
  }
  final meta = Map<String, Object?>.from(
      cfg['xrayMeta'] is Map ? cfg['xrayMeta'] as Map : {});
  final m = meta.remove(tempKey);
  if (m != null) meta[serverKey] = m;
  return {...cfg, 'patientXrays': px, 'xrayMeta': meta};
}

class XrayIngestResult {
  const XrayIngestResult({required this.key, required this.thumbDataUrl});

  final String key;
  final String thumbDataUrl;
}

class XrayStore {
  /// م83 — [encryptionKey] يحوّل تخزين الصور إلى خزنة SQLCipher.
  ///
  /// تمريرُ `null` يُبقي السلوك السابق حرفياً (ملفات `.jpg` في المجلد
  /// نفسه بالأسماء نفسها)، فالاختبارات القائمة ووضعُ `DB_PLAINTEXT` لا
  /// يتغيّران. والإنتاج يمرّر المفتاح، فتخرج الأشعة من العراء.
  XrayStore({
    required this.repos,
    required this.baseDir,
    required this.uid,
    String? encryptionKey,
    BlobVault? vault,
  }) : _vault = vault ??
            (encryptionKey == null || encryptionKey.isEmpty
                ? PlainFileVault(p.join(baseDir, 'xray_images'))
                : EncryptedBlobVault(
                    dir: p.join(baseDir, 'xray_images'),
                    hexKey: encryptionKey,
                  ));

  final Repositories repos;
  final String baseDir;
  final String uid;

  /// خلفية التخزين — العقد بالبايتات، فالمسارات لا تُسرَّب خارج هنا.
  final BlobVault _vault;

  Directory get _imagesDir => Directory(p.join(baseDir, 'xray_images'));

  /// يُغلق مقبض الخزنة. يستدعيه مزوّد Riverpod عند التخلّص.
  void close() => _vault.close();

  /// ينقل صور ما قبل التشفير إلى الخزنة مرّة واحدة (عمليةٌ عديمة الأثر).
  VaultMigrationResult migratePlainImages() => migratePlainImagesIntoVault(
        imagesDir: _imagesDir.path,
        vault: _vault,
      );

  String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9؀-ۿ._-]'), '_');

  /// أسماءُ المدخلات هي أسماء الملفات القديمة نفسها — فالترحيل مطابقةٌ
  /// مباشرة، ولا يحتاج جدول ربط.
  String _nameOf(String key) => '${_safeName(key)}.jpg';

  String _thumbNameOf(String key) => '${_safeName(key)}.thumb.jpg';

  /// حفظ مصغرة مسترجَعة من السحابة في الذاكرة المحلية.
  void writeThumbBytes(String key, Uint8List bytes) =>
      _vault.write(_thumbNameOf(key), bytes);

  /// إدخال صورة أشعة: ضغط بنفس درجات uploadXrayImage + مصغرة + صف xrays.
  /// يعيد المفتاح؛ استدعِ addXrayKeyToConfig بعده لتحديث المعرض.
  XrayIngestResult ingest(
    String patientName,
    String fileName,
    Uint8List bytes, {
    String clinic = '',
    // م-عزل الهوية — هاتف المريض المفتوح: يُختم على صف xrays (patient_id
    // هوياتي) فتعزله استعلامات المستودع، وتُنسب صورةُ السميّ لهويته.
    Object? phone,
  }) {
    final sizeMb = bytes.length / (1024 * 1024);
    if (sizeMb > maxXrayFileSizeMb) {
      throw Exception(
          'حجم الملف (${sizeMb.toStringAsFixed(1)} MB) يتجاوز الحد المسموح ($maxXrayFileSizeMb MB)');
    }
    final key = 'xray/$uid/$patientName/${jsNow()}_$fileName';

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('تعذّر قراءة الصورة');
    }

    // درجات الضغط نفسها (عرض أقصى + جودة) بحسب الحجم.
    final (maxWidth, quality) = sizeMb > 10
        ? (1200, 50)
        : sizeMb > 5
            ? (1600, 60)
            : sizeMb > 2
                ? (1800, 70)
                : (2000, 80);
    final full = decoded.width > maxWidth
        ? img.copyResize(decoded, width: maxWidth)
        : decoded;
    var fullBytes = Uint8List.fromList(img.encodeJpg(full, quality: quality));
    if (fullBytes.length >= bytes.length) fullBytes = bytes; // كما في الأصل

    // الحفظ المحلي أولاً (offline-first) — نظير IndexedDB.
    _vault.write(_nameOf(key), fullBytes);

    // مصغرة ≈300px q0.7 (compressThumbnailToSize).
    final thumb = decoded.width > 300
        ? img.copyResize(decoded, width: 300)
        : decoded;
    final thumbBytes = img.encodeJpg(thumb, quality: 70);
    final thumbUrl = 'data:image/jpeg;base64,${base64Encode(thumbBytes)}';

    // م65 — المصغّرة تُحفظ ملفاً محلياً أيضاً، لا في الصف وحده. الجهاز
    // المُنشئ يقرأها من هنا فلا يعتمد على بقائها في الصف المتزامن، وهذا
    // ما يجعل إخراجها من حمولة المزامنة آمناً بلا أي فقد للمعاينة.
    writeThumbBytes(key, Uint8List.fromList(thumbBytes));

    repos.xrays.addXray(
      patientName,
      key,
      thumbnailData: thumbUrl,
      clinic: clinic,
      phone: phone,
    );
    return XrayIngestResult(key: key, thumbDataUrl: thumbUrl);
  }

  /// النسخة الكاملة (الملف المحلي)، أو المصغرة عند غيابه — نظير سلوك العارض
  /// حين لا تتوفر النسخة الكاملة أوفلاين.
  Uint8List? fullImageBytes(String key) =>
      _vault.read(_nameOf(key)) ?? thumbnailBytes(key);

  /// بايتات الملف المحلي فقط (بلا تراجع للمصغرة) — لخط أنابيب الرفع.
  Uint8List? fileBytes(String key) => _vault.read(_nameOf(key));

  /// كتابة بايتات تحت مفتاح (إعادة تخطيط المفتاح المؤقت ← مفتاح الخادم).
  void writeFileBytes(String key, Uint8List bytes) =>
      _vault.write(_nameOf(key), bytes);

  /// حذف الملف المحلي لمفتاح.
  void deleteFile(String key) => _vault.delete(_nameOf(key));

  /// مصغرة: الملف المحلي أولاً ثم صف xrays.
  ///
  /// م65 — قُلب الترتيب عمداً. الملف المحلي يُكتب عند الإدخال وعند
  /// الاسترجاع من R2، فهو المصدر المتاح دائماً وقراءته لا تتطلب فك
  /// ترميز base64 في كل بناء. والصف يبقى تراجعاً للصفوف القديمة التي
  /// أُنشئت قبل هذا التغيير ولوضع «بلا R2» حيث تسافر المصغّرة.
  Uint8List? thumbnailBytes(String key) =>
      _vault.read(_thumbNameOf(key)) ??
      dataUrlBytes(repos.xrays.getThumbnail(key));

  /// حذف صورة: شاهدة على صف xrays (يتزامن) + حذف الملفين المحليين.
  /// (طابور حذف R2 السحابي في م5.)
  void deleteXray(String key) {
    repos.xrays.delete(key);
    _vault.delete(_nameOf(key));
    _vault.delete(_thumbNameOf(key));
  }
}
