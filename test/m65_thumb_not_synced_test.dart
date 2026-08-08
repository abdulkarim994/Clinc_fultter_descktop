/// اختبارات م65 — المصغّرة لا تسافر عبر المزامنة متى كان R2 مفعّلاً.
///
/// السبب: المصغّرة كانت مخزَّنة في مكانين معاً — على R2 (تُخدَم بـ`?v=thumb`)
/// وأيضاً base64 داخل صف `xrays` المتزامن، بنحو 27 كيلوبايت للصف الواحد.
/// القياس على PostgreSQL: إخراجها يوفّر 96.4٪ من حجم الصف.
///
/// والعلم **مشروط عمداً**: بلا R2 تبقى تسافر، فهي حينها السبيل الوحيد
/// لوصول معاينة إلى الجهاز الآخر. هذه الاختبارات تثبّت الاتجاهين معاً.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/sync/context.dart';
import 'package:dental_clinic_flutter/data/sync/push.dart' show buildOp;
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m65_');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ({ProviderContainer c, XrayStore store, dynamic repos}) boot() {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    final repos = c.read(reposProvider);
    return (
      c: c,
      store: XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1'),
      repos: repos
    );
  }

  Uint8List pngBytes() {
    final im = img.Image(width: 80, height: 60);
    img.fill(im, color: img.ColorRgb8(120, 120, 120));
    return Uint8List.fromList(img.encodePng(im));
  }

  group('م65 — حمولة المزامنة', () {
    test('مع R2: المصغّرة تُستثنى من الحمولة والصف المحلي يحتفظ بها', () {
      final b = boot();
      addTearDown(b.c.dispose);
      final r = b.store.ingest('نوري', 'scan.png', pngBytes());

      final row = b.repos.xrays.getByPatient('نوري').single;
      expect(row['thumbnail_data'], isNotNull,
          reason: 'الصف المحلي يحتفظ بالمصغّرة دائماً');

      final ctx = SyncContext(
          db: b.c.read(localDbProvider),
          repos: b.repos,
          transport: b.c.read(transportProvider),
          hasCloudImages: () => true);
      final op = buildOp(ctx, 'xrays', Map<String, Object?>.from(row));

      expect(op.row.containsKey('thumbnail_data'), isFalse,
          reason: 'م65: المصغّرة لا تسافر حين يخدمها R2');
      // بقية الحقول الوصفية تسافر كالمعتاد
      expect(op.row['file_key'], r.key);
      expect(op.row['patient_name'], 'نوري');
    });

    test('بلا R2: المصغّرة تبقى تسافر — لا فقد معاينة على الجهاز الآخر', () {
      final b = boot();
      addTearDown(b.c.dispose);
      b.store.ingest('نوري', 'scan.png', pngBytes());
      final row = b.repos.xrays.getByPatient('نوري').single;

      // الافتراضي في السياق: لا صور سحابية
      final ctx = b.c.read(syncContextProvider);
      expect(ctx.hasCloudImages(), isFalse);
      final op = buildOp(ctx, 'xrays', Map<String, Object?>.from(row));

      expect(op.row['thumbnail_data'], isNotNull,
          reason: 'بلا عامل R2 المصغّرة هي السبيل الوحيد للمعاينة');
    });

    test('الاستثناء يخص جدول الأشعة وحده', () {
      final b = boot();
      addTearDown(b.c.dispose);
      final ctx = SyncContext(
          db: b.c.read(localDbProvider),
          repos: b.repos,
          transport: b.c.read(transportProvider),
          hasCloudImages: () => true);
      final op = buildOp(ctx, 'patients',
          {'id': 'نوري', 'name': 'نوري', 'thumbnail_data': 'x', '_hlc': '1:0:d'});
      expect(op.row['thumbnail_data'], 'x',
          reason: 'الحذف مقيَّد بكيان xrays فلا يمسّ غيره');
    });
  });

  group('م65 — المصغّرة متاحة محلياً بلا الصف', () {
    test('الإدخال يكتب ملف مصغّرة، والقراءة تعمل بعد تفريغ الصف', () {
      final b = boot();
      addTearDown(b.c.dispose);
      final r = b.store.ingest('هدى', 'scan.png', pngBytes());

      expect(File('${tmp.path}/xray_images/'
              '${r.key.replaceAll(RegExp(r'[^A-Za-z0-9؀-ۿ._-]'), '_')}.thumb.jpg')
          .existsSync(), isTrue);

      // محاكاة جهاز استقبل الصف بلا مصغّرة: تفريغ الحقل من الصف
      b.repos.xrays.upsert({'id': r.key, 'thumbnail_data': null});
      expect(b.store.thumbnailBytes(r.key), isNotNull,
          reason: 'الملف المحلي يغطي غياب المصغّرة عن الصف');
    });
  });
}
