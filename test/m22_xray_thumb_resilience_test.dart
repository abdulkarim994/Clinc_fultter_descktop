/// اختبارات م22 — صمود مصغرات الأشعة (علة «بتضل شاشة تحميل»):
///   1) مهلة جلب R2: راديو ميت كان يعلّق الجلب بلا نهاية فيبقى المفتاح
///      «جارياً» والسبينر أبدياً — المهلة تحوّله فشلاً نظيفاً.
///   2) تهدئة إعادة المحاولة: كان request يمسح علامة الفشل عند كل إعادة
///      بناء فيتناوب السبينر أبداً ولا تظهر بلاطة الفشل — الآن الفشل يثبت
///      (بلاطة حمراء) حتى تنقضي التهدئة ثم يعاد تلقائياً.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

/// بديل بعيد قابل للبرمجة.
class ScriptedRemote implements XrayRemote {
  int calls = 0;
  Uint8List? Function()? onFetch;

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async {
    calls++;
    return onFetch?.call();
  }

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String> upload(Uint8List bytes, String key,
          {String patientName = '',
          String fileName = '',
          String contentType = 'image/jpeg'}) async =>
      key;

  @override
  Future<R2HeadResult> headObject(String key) async =>
      const R2HeadResult(ok: true);
}

void main() {
  late Directory tmp;
  late ProviderContainer c;
  late XrayStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m22_');
    c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    store = XrayStore(
        repos: c.read(reposProvider), baseDir: tmp.path, uid: 'anon');
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('مهلة fetchBytes: شبكة معلّقة تعود null سريعاً بدل التعليق الأبدي',
      () async {
    final client = MockClient((req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return http.Response('late', 200);
    });
    final r2 = R2Client(
      workerUrl: 'https://worker.test',
      accessToken: () async => 'jwt',
      httpClient: client,
      fetchTimeout: const Duration(milliseconds: 120),
    );
    final sw = Stopwatch()..start();
    final out = await r2.fetchBytes('k1');
    sw.stop();
    expect(out, isNull);
    expect(sw.elapsedMilliseconds, lessThan(1500),
        reason: 'المهلة يجب أن تقطع التعليق');
  });

  test('التهدئة: الفشل يثبت بين عمليات إعادة البناء ثم يعاد بعد انقضائها',
      () async {
    var now = DateTime(2026, 7, 27, 12, 0, 0);
    final remote = ScriptedRemote()..onFetch = (() => null); // فشل دائم
    final restorer = XrayThumbRestorer(
      store: store,
      remote: remote,
      retryCooldown: const Duration(seconds: 30),
      now: () => now,
    );

    restorer.request('k1', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restorer.isFailed('k1'), isTrue);
    expect(remote.calls, 2); // مصغرة ثم كاملة

    // إعادة بناء فورية (سلوك الواجهة القديم كان يمسح الفشل هنا):
    restorer.request('k1', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(remote.calls, 2, reason: 'لا محاولة جديدة داخل التهدئة');
    expect(restorer.isFailed('k1'), isTrue,
        reason: 'بلاطة الفشل تبقى ظاهرة لا سبينر أبدي');

    // بعد انقضاء التهدئة: محاولة جديدة تلقائياً — وهذه المرة تنجح.
    now = now.add(const Duration(seconds: 31));
    remote.onFetch = () => Uint8List.fromList(List.filled(32, 9));
    restorer.request('k1', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restorer.isFailed('k1'), isFalse);
    expect(store.thumbnailBytes('k1'), isNotNull,
        reason: 'المصغرة المسترجعة كُتبت للمخزن');
  });

  test('أوفلاين: الفشل لا يُمسح ولو انقضت التهدئة (لا محاولات عبثية)',
      () async {
    var now = DateTime(2026, 7, 27, 12, 0, 0);
    final remote = ScriptedRemote()..onFetch = (() => null);
    final restorer = XrayThumbRestorer(
      store: store,
      remote: remote,
      retryCooldown: const Duration(seconds: 30),
      now: () => now,
    );
    restorer.request('k2', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(restorer.isFailed('k2'), isTrue);
    now = now.add(const Duration(minutes: 5));
    restorer.request('k2', online: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(remote.calls, 2, reason: 'لا إعادة محاولة بلا اتصال');
    expect(restorer.isFailed('k2'), isTrue);
  });
}
