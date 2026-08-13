/// م175 — لقطات للمراجعة (GOLDENS=1 محلياً فقط): القوالب الثمانية
/// لاستوديو المقارنة — 4 ابتسامة (فيسبوك) + 4 أشعة بمقاسات مختلفة،
/// بعناوين وشرائح مدةٍ ونصوصٍ واقعية. عدة الخطوط من م154.
library;

import 'dart:convert' show base64Decode;
import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/desktop/desktop_gate.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_compare_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _goldens = Platform.environment.containsKey('GOLDENS');

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Qomra',
      ['Qomra-Regular.ttf', 'Qomra-Medium.ttf', 'Qomra-Bold.ttf']);
  await load(
      'Cairo', ['Cairo-Regular.ttf', 'Cairo-SemiBold.ttf', 'Cairo-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final l = FontLoader('MaterialIcons');
      l.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await l.load();
    }
  }
}

/// عيّنتان بأسلوب صور الأشعة (تدرج داكن/فاتح) — 60×80 (من م174).
final Uint8List _dark = base64Decode(
  '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'
  'btX1V3L/Ao5YECWT2m5bAAAAAElFTkSuQmCC',
);
final Uint8List _light = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAADwAAABQCAIAAADKqIEEAAAFzElEQVR4nNWbV2/k'
  'RhCE5//jcHc65ZxzzjnnnHOOVjjLMgy/u4E6FBo9w/HCD4YGKAELskV+U1vTu0sO'
  '3ZcveV+/5n/7VvD9e2FeXtGPH8X5+SUFBaWFhWVFReXFxRUlJZWlpVVlZdWi8vKa'
  'iopaUWVlXVVVPVRd3SCqqWnMRSjm/8pxcEA5Mk4h55Izynnl7MIgJMIjVMImhMIp'
  'tI7EEVw5InDJqkFra5tEdXXNuQjF/gBAjxNF0MHtjME+rrY2CFpf3yJqaGjNRSgO'
  'DsA3XqNryx2Isww2uGTVoI2NbaKmpvZchGIzANJr9CzLhdbpSMRx6asBbW7uELW0'
  'dOYiFJsBaO8j6OR2fiSCuNpXsoKjtbULamvrjouVHADp6X0Q3VjuSGwMzsLVrEBp'
  'b++BOjp642Ilx6Dpg+jGcnA7+dORCBqscTUrUDo7+6Curv64WMkxaHqN7luuo+JI'
  'rCMRwaWpBO3uHoB6egbjYiUHQPsj6Doq4HY6xMZgH5fWkhU0vb1Dor6+4bhQpgcA'
  'em28Rs+KivOJfYN9XAPa3z8iGhgYjQtlZgA+um+54XaaWEfCGGxwyQqawcEx0dDQ'
  'eFwo4wBIb9C15Toq5HY+sY5EEFezgmZ4eEI0MjIZF8o4AE3vo+uoGG6niRkJY7DB'
  'pa8EHR2dEo2NTceFMg5Ae6/RjeUm4kLrIsRBgzUuWcfHZ0QTE7NxoUzTEz1oeRa3'
  '48zTxDoSWbiadXJyTjQ1NR8Xygx9EF1HRXMjJy5CrA32cWEeWaenF0QzM4tZQgHp'
  '6b1B15ZncTv2iiCxMZi4mhVMs7NLorm55SyhgAPQ9EA3lmdxC61jd9M5NsTGYBAD'
  'l6Dz8yuihYXVLKGAAyC65oblQW7dwp0Yzu4WJw7iEnRxcU20tLSeJRRwAEH0f+VG'
  'H3QIBrobZ54h1gYbXLIuL2+IVlY2s4QCTa/RteU+N+Yl+7dDMNiPMfN8YmMwcGEh'
  'WFdXt0Rra9tZQgHo6b0cx1juc7OfMNyOUUY/Zq8IEmuDNa4wra/viDY2drOEAtAT'
  'XVuexY1+ws8doXUMBqOMXsEc+8Q+LrA2N/e2tvazJHtJb9CD3Mg3+yDDLbSONjMY'
  '7G7IsSbWBhOXrNvbBzs7h1mSvZoe6Npyzc15iT5oQuJosw4GuhtnniHWBmvc3d0j'
  '0d7esS/s0ujacp8b85L9W4dEaB1tRsdAMBhlzDydChDTYOIK2f7+iejg4NQXdoGe'
  '6LBccyMn7CcMN8xmJ3G0mR1DB4O9IkiscYXs8PBMdHR07gu7QE/0LG70ExMSdhKh'
  'dUGbdTDQK5hjEGuDgQu44+OLk5NLX7Kd9FKvLSc38s0+qENizHa6adBmdAwEA1Hm'
  'zNMe02Dinp5enZ1d+5LtRKfl2m/OS4YbZrOTMNm/oNk0TJpNMDjzNLHBPT+/ubi4'
  '9SXbDbrhxrw0IQkmW2idtpnZCNoMYnlDmQoSE/fy8u7q6t6XbCe65kZOMC8ZEmM2'
  'E0KzXTAbJs2wmcFgjg2xwF1fP4hubh61sFH2Gm7mW4cEZptkm4Q4kw0zBYM2y9uK'
  'HJMYBgP39vbp7u43LdkCdFhObuQbIfHNjkzHALTOhp9mHQzJKD0m7v3988PDi5Zs'
  'ITr9lv/VIfGTHUzIL+h439DZCNrMVIBYEB8fX5+e3rRki2wHN3MSNNskJKuHBKCz'
  'ssGmgTTDZnm7kQpN/Pz8u5bmRk4QEphNaJodTMh/h2Y2fJslAyR+eXl/ff0Dktfk'
  'lpqg2SYh/wc0bSbx29vHz59/QvKa3DT700GLu8L6/v4XJK9lSzLQHx9/pwedktNp'
  'ZPqzd4/P26cT+ERM8rtHkt/ykvw+neQvlyR/Iyb5azzJ6x5JXmFK8lpekldNk7w+'
  'neSdgCTvuSR5dyvJ+4hJ3rFN8t54kqsQklzvkeTKmiTXMCW5WizJdXlJroBMcq1p'
  'kqt6k1w/neRK9SSfCUjy6Yskn3NJ8omiJJ/dSvEpuX8Ah7NctBg7xvkAAAAASUVO'
  'RK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(_loadAppFonts);
  setUp(() => tmp = Directory.systemTemp.createTempSync('m175g_'));
  tearDown(() {
    debugForceDesktopUi = null;
    tmp.deleteSync(recursive: true);
  });

  int ts(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

  /// عناصر عيّنة بعدد مطلوب (تواريخ متدرجة — الشريحة تحسب مدةً حقيقية).
  List<CompareItem> items(int n) {
    final dates = [
      ('١٠ يناير ٢٠٢٥', ts(2025, 1, 10)),
      ('٥ أبريل ٢٠٢٥', ts(2025, 4, 5)),
      ('٢٢ أغسطس ٢٠٢٥', ts(2025, 8, 22)),
      ('٣ يناير ٢٠٢٦', ts(2026, 1, 3)),
      ('١٥ مايو ٢٠٢٦', ts(2026, 5, 15)),
      ('١٢ أغسطس ٢٠٢٦', ts(2026, 8, 12)),
    ];
    return [
      for (var i = 0; i < n; i++)
        CompareItem(
          bytes: i.isEven ? _dark : _light,
          name: 'صورة ${i + 1}',
          date: dates[i].$1,
          ts: dates[i].$2,
        ),
    ];
  }

  Future<void> pumpStudio(WidgetTester t, String family, int n,
      {Size size = const Size(440, 1000)}) async {
    debugForceDesktopUi = false;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Cairo', useMaterial3: true),
          builder: (ctx, child) => Directionality(
              textDirection: TextDirection.rtl, child: child!),
          home: CompareStudioScreen(
            family: family,
            items: items(n),
            patientName: 'محمد حسين المحمد',
            centerName: 'عيادة الصفوة',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    // فك ترميز الصور قبل الالتقاط (كاش الصور يتشارك بين الاختبارات —
    // بدون هذا تظهر الفتحات فارغةً في أول اختبار).
    final ctx = t.element(find.byType(CompareStudioScreen));
    await t.runAsync(() async {
      await precacheImage(MemoryImage(_dark), ctx);
      await precacheImage(MemoryImage(_light), ctx);
    });
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) => expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));

  Future<void> pickTpl(WidgetTester t, String id) async {
    await t.tap(find.byKey(Key('cs-tpl-$id')));
    await t.pumpAndSettle();
  }

  group('لقطات م175 — قوالب الابتسامة (فيسبوك)', () {
    testWidgets('الذهبي الفاخر (مربع مكدس)', (t) async {
      await pumpStudio(t, 'smile', 2);
      await pickTpl(t, 'smile_gold');
      await shot(t, 'm175_smile_gold');
    }, skip: !_goldens);

    testWidgets('الأخضر الملكي (4:5 ثنائي)', (t) async {
      await pumpStudio(t, 'smile', 2);
      await pickTpl(t, 'smile_royal');
      await shot(t, 'm175_smile_royal');
    }, skip: !_goldens);

    testWidgets('الأبيض النقي (مربع ثنائي)', (t) async {
      await pumpStudio(t, 'smile', 2);
      await pickTpl(t, 'smile_pure');
      await shot(t, 'm175_smile_pure');
    }, skip: !_goldens);

    testWidgets('الليلي الأنيق (4:5 مكدس)', (t) async {
      await pumpStudio(t, 'smile', 2);
      await pickTpl(t, 'smile_night');
      await shot(t, 'm175_smile_night');
    }, skip: !_goldens);
  });

  group('لقطات م175 — قوالب الأشعة', () {
    testWidgets('الملكي قبل/بعد (ثنائي)', (t) async {
      await pumpStudio(t, 'xray', 2);
      await pickTpl(t, 'xray_royal');
      await shot(t, 'm175_xray_royal');
    }, skip: !_goldens);

    testWidgets('شريط التسلسل (4 صور عريض)', (t) async {
      await pumpStudio(t, 'xray', 4);
      await pickTpl(t, 'xray_strip');
      // إدراج شريحة المدة المحسوبة بالسطر الثاني.
      await t.tap(find.byKey(const Key('cs-followup')));
      await t.pumpAndSettle();
      await shot(t, 'm175_xray_strip');
    }, skip: !_goldens);

    testWidgets('الكهرماني الدافئ (3 صور)', (t) async {
      await pumpStudio(t, 'xray', 3);
      await pickTpl(t, 'xray_amber');
      await shot(t, 'm175_xray_amber');
    }, skip: !_goldens);

    testWidgets('الشبكة السريرية (6 صور)', (t) async {
      await pumpStudio(t, 'xray', 6);
      await pickTpl(t, 'xray_grid');
      await shot(t, 'm175_xray_grid');
    }, skip: !_goldens);
  });
}
