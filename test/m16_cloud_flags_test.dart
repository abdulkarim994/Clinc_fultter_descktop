/// اختبارات م16 — تفعيل السحابة: أعلام بيئة البناء (توأم VITE_*):
/// تطبيقها يطابق أعلام الإنتاج (PHONE_IDENTITY/COLD_FETCH) دون المساس
/// بوضع الاختبارات المحلي (لا تعريفات ⇒ لا تغيير)، وتحليل إعداد السحابة
/// (dart-define/ملف) يقرر الوضع السحابي.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/data/cloud/cloud_config.dart';
import 'package:dental_clinic_flutter/data/repositories/patients_repository.dart'
    show patientKeyFor;
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(syncFlags.resetForTest);
  tearDown(syncFlags.resetForTest);

  group('أعلام بيئة البناء', () {
    test('بلا تعريفات: الافتراضات المحلية لا تتغير', () {
      applyBuildTimeFlags();
      expect(isPhoneIdentityEnabled(), isFalse);
      expect(isColdFetchEnabled(), isFalse);
    });

    test('PHONE_IDENTITY=1 يقلب مفاتيح الهوية لصيغة الإنتاج p:هاتف:اسم',
        () {
      // قبل: مفتاح الاسم القديم TRIM(name).
      expect(patientKeyFor(name: ' هدى ', phone: '0919929558'), 'هدى');
      applyBuildTimeFlags(phoneIdentity: '1', coldFetch: '1');
      expect(isPhoneIdentityEnabled(), isTrue);
      expect(isColdFetchEnabled(), isTrue);
      // بعد: هوية الهاتف الحتمية — كما كُتبت بيانات الإنتاج.
      expect(patientKeyFor(name: 'هدى', phone: '0919929558'),
          startsWith('p:'));
    });

    test('قيم صائبة أخرى: true/on؛ والصفر لا يفعّل', () {
      applyBuildTimeFlags(phoneIdentity: 'true', coldFetch: '0');
      expect(isPhoneIdentityEnabled(), isTrue);
      expect(isColdFetchEnabled(), isFalse);
      applyBuildTimeFlags(phoneIdentity: '', coldFetch: 'on');
      expect(isColdFetchEnabled(), isTrue);
    });
  });

  group('إعداد السحابة', () {
    test('ملف cloud_config.json يقرأ ويقرر الوضع السحابي', () {
      final tmp = Directory.systemTemp.createTempSync('m16_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      // بلا ملف: وضع محلي.
      expect(loadCloudConfig(tmp.path), isNull);
      // ملف بقيم: سحابي مع تشذيب الشرطات الأخيرة.
      cloudConfigFile(tmp.path).writeAsStringSync(jsonEncode({
        'supabaseUrl': 'https://xyz.supabase.co/',
        'anonKey': 'k1',
        'r2WorkerUrl': 'https://w.workers.dev//',
      }));
      final cfg = loadCloudConfig(tmp.path)!;
      expect(cfg.hasSync, isTrue);
      expect(cfg.hasImages, isTrue);
      expect(cfg.supabaseUrl, 'https://xyz.supabase.co');
      expect(cfg.r2WorkerUrl, 'https://w.workers.dev');
      // مفتاح ناقص ⇒ محلي (لا اتصال نصفي).
      cloudConfigFile(tmp.path)
          .writeAsStringSync(jsonEncode({'supabaseUrl': 'https://x.co'}));
      expect(loadCloudConfig(tmp.path), isNull);
    });
  });
}
