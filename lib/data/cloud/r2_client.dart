/// عميل عامل R2 (Cloudflare Worker) — نقل r2.service.js حرفياً:
///   POST   {worker}/upload?key=…   (Bearer + Content-Type + X-Patient-Name
///                                   + X-File-Name؛ الجسم = البايتات) — يعيد
///                                   JSON فيه المفتاح الفعلي الذي خزّن العامل
///                                   الكائن تحته (key|Key|path) — قد يختلف عن
///                                   المفتاح المؤقت المرسل.
///   GET    {worker}/image/{key}    (+ ?v=thumb للمصغرة الخادمية الاختيارية)
///   HEAD   {worker}/image/{key}    للتحقق قبل التنظيف (الحجم معلوماتي فقط)
///   DELETE {worker}/image/{key}    — 404/410 تُعامل نجاحاً («زال أصلاً»)
/// مهلة الرفع 120 ثانية ومحاولتا إعادة بتأخير 1s×(n+1) — نفس الثوابت.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const r2UploadTimeout = Duration(milliseconds: 120000);
const r2UploadMaxRetries = 2;

class R2HeadResult {
  const R2HeadResult({required this.ok, this.size, this.notFound = false});

  /// الكائن موجودٌ ومقروء (‏2xx).
  final bool ok;
  final int? size;

  /// الخادم أكّد **الغياب** صراحةً (‏404/410) — لا مجرّد إخفاق قراءة.
  ///
  /// ⚠ التمييز حرجٌ لأمن البيانات: كان `ok:false` يعني «غير موجود **أو**
  /// أخفق النداء» معاً، فجهازٌ جديد يقرأ فهرس الأرشيف أثناء عطلٍ لحظيّ
  /// (‏5xx، مهلة، رمزٌ منتهٍ) كان يستنتج «الفهرس غائب ⇒ أول تشغيل» فيدهس
  /// فهرساً سليماً على الخادم ويُيتّم كل الحزم السابقة. الغياب لا يُعلَن
  /// إلا حين يقوله الخادم صراحةً بـ404. (رُصد بالتشغيل.)
  final bool notFound;
}

/// واجهة الطرف البعيد للصور — R2Client ينفذها والاختبارات تزيّفها،
/// فيبقى خط أنابيب الأشعة قابلاً للاختبار بلا شبكة (نفس فلسفة SyncTransport).
abstract interface class XrayRemote {
  Future<String> upload(Uint8List bytes, String key,
      {String patientName, String fileName, String contentType});
  Future<R2HeadResult> headObject(String key);
  Future<Uint8List?> fetchBytes(String key, {bool thumb});
  Future<void> delete(String key);
}

class R2Client implements XrayRemote {
  R2Client({
    required this.workerUrl,
    required this.accessToken,
    http.Client? httpClient,
    Future<void> Function(Duration)? delay,
    this.fetchTimeout = const Duration(seconds: 20),
  })  : _http = httpClient ?? http.Client(),
        _delay = delay ?? Future<void>.delayed;

  final String workerUrl;
  final Future<String?> Function() accessToken;
  final http.Client _http;
  final Future<void> Function(Duration) _delay;

  /// م22 — سقف زمني لجلب الصورة/المصغرة: راديو ميت أو شبكة بالغة البطء
  /// كانا يعلّقان الجلب بلا نهاية فتبقى بلاطة المصغرة على السبينر أبداً
  /// (ويظل المفتاح «جارياً» فلا يعاد طلبه). المهلة تحوّل التعليق إلى فشل
  /// نظيف تعرضه الواجهة بلاطةً حمراء ويعاد المحاولة بعد تهدئة.
  final Duration fetchTimeout;

  Future<Map<String, String>> _auth() async => {
        'Authorization': 'Bearer ${await accessToken() ?? ''}',
      };

  String imageUrl(String key) =>
      '$workerUrl/image/${Uri.encodeComponent(key)}';

  /// uploadImage — يعيد المفتاح الفعلي من استجابة العامل (key|Key|path)،
  /// وإلا المفتاح المرسل.
  @override
  Future<String> upload(
    Uint8List bytes,
    String key, {
    String patientName = '',
    String fileName = '',
    String contentType = 'image/jpeg',
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= r2UploadMaxRetries; attempt++) {
      try {
        final res = await _http
            .post(
              Uri.parse('$workerUrl/upload?key=${Uri.encodeQueryComponent(key)}'),
              headers: {
                ...await _auth(),
                'Content-Type': contentType,
                'X-Patient-Name': Uri.encodeComponent(patientName),
                'X-File-Name': Uri.encodeComponent(fileName),
              },
              body: bytes,
            )
            .timeout(r2UploadTimeout);
        if (res.statusCode >= 400) {
          throw Exception('Upload failed: ${res.statusCode}');
        }
        try {
          final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
          if (j is Map) {
            return '${j['key'] ?? j['Key'] ?? j['path'] ?? key}';
          }
        } catch (_) {}
        return key;
      } catch (e) {
        lastError = e;
        if (attempt < r2UploadMaxRetries) {
          await _delay(Duration(seconds: attempt + 1));
        }
      }
    }
    throw Exception('$lastError');
  }

  /// جلب البايتات (النسخة الكاملة أو المصغرة الخادمية) — null عند الفشل
  /// أو تجاوز المهلة (م22: المهلة تشمل جلب الرمز والنداء معاً).
  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async {
    try {
      return await Future<Uint8List?>(() async {
        final res = await _http.get(
          Uri.parse('${imageUrl(key)}${thumb ? '?v=thumb' : ''}'),
          headers: await _auth(),
        );
        if (res.statusCode >= 400) return null;
        return res.bodyBytes;
      }).timeout(fetchTimeout);
    } catch (_) {
      return null;
    }
  }

  /// HEAD للتحقق قبل التنظيف — الحجم معلوماتي فقط.
  @override
  Future<R2HeadResult> headObject(String key) async {
    try {
      final res =
          await _http.head(Uri.parse(imageUrl(key)), headers: await _auth());
      // 404/410 ⇒ غيابٌ مؤكَّد. أي إخفاق آخر ⇒ وجودٌ مجهول لا غياب.
      if (res.statusCode == 404 || res.statusCode == 410) {
        return const R2HeadResult(ok: false, notFound: true);
      }
      if (res.statusCode >= 400) return const R2HeadResult(ok: false);
      final len = res.headers['content-length'];
      return R2HeadResult(ok: true, size: len == null ? null : int.tryParse(len));
    } catch (_) {
      // استثناء (مهلة/شبكة) ⇒ لا نعرف أموجودٌ هو أم لا — ليس غياباً.
      return const R2HeadResult(ok: false);
    }
  }

  /// deleteImage مع دلالة _r2DeleteSafe: «زال أصلاً» (404/410) نجاح.
  @override
  Future<void> delete(String key) async {
    final res = await _http.delete(Uri.parse(imageUrl(key)),
        headers: await _auth());
    if (res.statusCode >= 400 &&
        res.statusCode != 404 &&
        res.statusCode != 410) {
      throw Exception('Delete failed: ${res.statusCode}');
    }
  }
}
