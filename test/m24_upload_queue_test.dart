/// اختبارات م24 — طابور رفع الصور التلقائي (توأم startUploadQueueListener):
///   • أحادية الرحلة: نداءات متزامنة (مؤقت + عودة اتصال + زر يدوي)
///     تتشارك التشغيلة نفسها — جذر منع الرفع المزدوج في الأصل.
///   • البدء يصرف فوراً ثم دورياً كل فاصل؛ الإيقاف يلغي المؤقت.
///   • عدّاد الصور المعلقة تفاعلي بنبضة xrayVersion وتظهر به لافتة
///     الرئيسية ويختفي عند الصفر.
library;

import 'dart:async';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart'
    show XrayUploadQueue;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('الوحدات — XrayUploadQueue', () {
    test('أحادية الرحلة: نداءان متزامنان = تشغيلة واحدة ثم يسمح بالتالية',
        () async {
      var runs = 0;
      final gate = Completer<void>();
      final q = XrayUploadQueue(drain: () async {
        runs++;
        await gate.future;
      });
      final f1 = q.drainNow();
      final f2 = q.drainNow(); // أثناء الرحلة — يعيد وعدها نفسه
      expect(runs, 1);
      gate.complete();
      await f1;
      await f2;
      await q.drainNow(); // بعد الاكتمال — تشغيلة جديدة مسموحة
      expect(runs, 2);
    });

    test('start يصرف فوراً ثم كل فاصل؛ stop يلغي؛ start idempotent', () {
      fakeAsync((async) {
        var runs = 0;
        final q = XrayUploadQueue(
          drain: () async => runs++,
          interval: const Duration(seconds: 30),
        );
        q.start();
        q.start(); // idempotent — لا مؤقت ثانٍ
        async.elapse(const Duration(milliseconds: 10));
        expect(runs, 1, reason: 'تصريف فوري عند البدء');
        async.elapse(const Duration(seconds: 30));
        expect(runs, 2, reason: 'الدورة الأولى للمؤقت');
        async.elapse(const Duration(seconds: 60));
        expect(runs, 4, reason: 'دورتان إضافيتان');
        q.stop();
        async.elapse(const Duration(minutes: 5));
        expect(runs, 4, reason: 'الإيقاف يلغي المؤقت');
      });
    });

    test('فشل التصريف لا يكسر الطابور — الدورة التالية تعمل', () {
      fakeAsync((async) {
        var runs = 0;
        final q = XrayUploadQueue(
          drain: () async {
            runs++;
            throw Exception('offline');
          },
          interval: const Duration(seconds: 30),
        );
        q.start();
        async.elapse(const Duration(seconds: 95));
        expect(runs, 4, reason: 'فوري + 3 دورات رغم الفشل الدائم');
        q.stop();
      });
    });
  });

  group('التكامل — عدّاد الصور المعلقة', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m24_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('العدّاد يتبع صفوف pending ويتحدث بنبضة xrayVersion', () {
      expect(c.read(pendingXrayUploadsProvider), 0);
      final repos = c.read(reposProvider);
      repos.xrays.upsertLocal({
        'id': 'x1', 'patient_name': 'سالم', 'file_key': 'k1',
        'upload_status': 'pending',
      });
      repos.xrays.upsertLocal({
        'id': 'x2', 'patient_name': 'سالم', 'file_key': 'k2',
        'upload_status': 'pending',
      });
      c.read(xrayVersionProvider.notifier).state++;
      expect(c.read(pendingXrayUploadsProvider), 2);

      // اكتمل رفع واحدة (ما يفعله reconcileOne) — النبضة تحدّث العدّاد.
      repos.xrays.upsertLocal({
        'id': 'x1', 'patient_name': 'سالم', 'file_key': 'k1',
        'upload_status': 'uploaded',
      });
      c.read(xrayVersionProvider.notifier).state++;
      expect(c.read(pendingXrayUploadsProvider), 1);
    });
  });
}
