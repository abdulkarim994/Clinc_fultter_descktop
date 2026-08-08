/// اختبارات م5 — السحابة الحقيقية وخط أنابيب الصور وPDF العربي:
/// عميل GoTrue (دخول/تحديث/أخطاء عربية) وخدمة المصادقة (استعادة محلية صرفة،
/// تحديث استباقي قرب الانتهاء، خروج صريح)، وناقل Supabase (شكل السلك حرفياً
/// و401←تحديث←إعادة)، وعميل R2 (مفتاح العامل، إعادة المحاولة، 404 نجاح)،
/// وخط أنابيب الأشعة (حجز المفتاح ضد التكرار، تحقق-قبل-التنظيف، إعادة تخطيط
/// المفاتيح، الحارسان، طابور الحذف)، وأرقام جداول المعالجات واللقطات، وبناء
/// التقارير الثلاثة PDF بخط القاهرة — كله بلا شبكة حقيقية.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/data/cloud/cloud_config.dart';
import 'package:dental_clinic_flutter/data/cloud/gotrue_client.dart';
import 'package:dental_clinic_flutter/data/cloud/r2_client.dart';
import 'package:dental_clinic_flutter/data/cloud/supabase_auth_service.dart';
import 'package:dental_clinic_flutter/data/cloud/supabase_transport.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:dental_clinic_flutter/features/archive/month_stats.dart';
import 'package:dental_clinic_flutter/features/auth/auth_service.dart';
import 'package:dental_clinic_flutter/features/finance/treasury_logic.dart'
    show ProsGroup;
import 'package:dental_clinic_flutter/features/labs/labs_logic.dart';
import 'package:dental_clinic_flutter/features/print/reports.dart';
import 'package:dental_clinic_flutter/features/print/treatment_tables.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_pipeline.dart';
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

const _base = 'https://proj.supabase.co';

/// استجابة JSON بترميز UTF-8 (http.Response النصي يشفّر Latin-1 افتراضياً
/// فيرفض العربية — نفس السبب الذي جعل العملاء يفكّون bodyBytes صراحة).
http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

GotrueSession _session({int? expiresAt}) => GotrueSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiresAt:
          expiresAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      userId: 'uid-1',
      email: 'doc@clinic.ly',
    );

String _sessionJson({String access = 'access-1'}) => jsonEncode({
      'access_token': access,
      'refresh_token': 'refresh-2',
      'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      'user': {'id': 'uid-1', 'email': 'doc@clinic.ly'},
    });

void main() {
  group('GotrueClient', () {
    test('الدخول يوزّع الجلسة والخطأ يترجم عربياً', () async {
      final calls = <http.Request>[];
      final client = GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          calls.add(req);
          if ('${req.url}'.contains('grant_type=password')) {
            final body = jsonDecode(req.body) as Map;
            if (body['password'] == 'good') {
              return http.Response(_sessionJson(), 200);
            }
            return http.Response(
                jsonEncode({'msg': 'Invalid login credentials'}), 400);
          }
          return http.Response('{}', 404);
        }),
      );

      final s = await client.signInWithPassword('doc@clinic.ly', 'good');
      expect(s.userId, 'uid-1');
      expect(s.accessToken, 'access-1');
      expect(calls.single.headers['apikey'], 'anon');

      await expectLater(
        client.signInWithPassword('doc@clinic.ly', 'bad1234'),
        throwsA(predicate(
            (e) => '$e' == 'البريد أو كلمة المرور غير صحيحة')),
      );
    });

    test('التحديث يرسل refresh_token والتسجيل المكرر يترجم', () async {
      final client = GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          if ('${req.url}'.contains('grant_type=refresh_token')) {
            expect((jsonDecode(req.body) as Map)['refresh_token'], 'r-1');
            return http.Response(_sessionJson(access: 'access-2'), 200);
          }
          if (req.url.path.endsWith('/signup')) {
            return http.Response(
                jsonEncode({'msg': 'User already registered'}), 422);
          }
          return http.Response('{}', 404);
        }),
      );
      final s = await client.refresh('r-1');
      expect(s.accessToken, 'access-2');
      await expectLater(
        client.signUp('a@b.ly', 'secret12'),
        throwsA(predicate((e) => '$e' == 'البريد مسجّل مسبقاً')),
      );
    });
  });

  group('SupabaseAuthService', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m5auth_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('الدخول يثبّت session.json والاستعادة محلية صرفة بلا شبكة',
        () async {
      var networkCalls = 0;
      final client = GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          networkCalls++;
          return http.Response(_sessionJson(), 200);
        }),
      );
      final svc = SupabaseAuthService(client: client, dbDir: tmp.path);
      addTearDown(svc.dispose);
      final user = await svc.login('doc@clinic.ly', 'secret12');
      expect(user.uid, 'uid-1');
      expect(File('${tmp.path}/session.json').existsSync(), isTrue);
      final before = networkCalls;

      // خدمة جديدة (تشغيل تالٍ): الاستعادة تقرأ الملف ولا تنادي الشبكة.
      final svc2 = SupabaseAuthService(
        client: GotrueClient(
          baseUrl: _base,
          anonKey: 'anon',
          httpClient: MockClient((req) async {
            fail('لا شبكة في الاستعادة');
          }),
        ),
        dbDir: tmp.path,
      );
      addTearDown(svc2.dispose);
      final restored = svc2.restoreSession();
      expect(restored?.uid, 'uid-1');
      expect(networkCalls, before);
    });

    test('قرب الانتهاء يحدّث استباقياً ويكتب الجلسة الجديدة', () async {
      var refreshes = 0;
      final client = GotrueClient(
        baseUrl: _base,
        anonKey: 'anon',
        httpClient: MockClient((req) async {
          if (req.method == 'HEAD') return http.Response('', 200);
          if ('${req.url}'.contains('grant_type=refresh_token')) {
            refreshes++;
            return http.Response(_sessionJson(access: 'access-fresh'), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      // جلسة على وشك الانتهاء (خلال دقيقة < هامش الخمس دقائق).
      File('${tmp.path}/session.json').writeAsStringSync(jsonEncode(
          _session(
                  expiresAt:
                      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60)
              .toJson()));
      final svc = SupabaseAuthService(client: client, dbDir: tmp.path);
      addTearDown(svc.dispose);
      final token = await svc.validAccessToken();
      expect(token, 'access-fresh');
      expect(refreshes, 1);
      // القفل: نداء ثانٍ فوري لا يكرر التحديث (حد أدنى 10 ثوانٍ).
      await svc.validAccessToken();
      expect(refreshes, 1);
    });

    test('الخروج يمسح الملف ويعلّم خروجاً صريحاً', () async {
      File('${tmp.path}/session.json')
          .writeAsStringSync(jsonEncode(_session().toJson()));
      final svc = SupabaseAuthService(
        client: GotrueClient(
          baseUrl: _base,
          anonKey: 'anon',
          httpClient: MockClient((req) async => http.Response('', 204)),
        ),
        dbDir: tmp.path,
      );
      addTearDown(svc.dispose);
      expect(svc.restoreSession(), isNotNull);
      await svc.logout();
      expect(File('${tmp.path}/session.json').existsSync(), isFalse);
      expect(svc.isExplicitLogout, isTrue);
      expect(svc.restoreSession(), isNull);
    });
  });

  group('SupabaseTransport', () {
    test('apply_changes: السلك حرفي والترويسات صحيحة والإشعارات تُفكّك',
        () async {
      late http.Request captured;
      final t = SupabaseTransport(
        baseUrl: _base,
        anonKey: 'anon',
        accessToken: () async => 'tok',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
              jsonEncode({
                'results': [
                  {'op_id': 'records:r1:h1', 'id': 'r1', 'server_seq': 7},
                ],
              }),
              200);
        }),
      );
      final acks = await t.applyChanges([
        const WireOp(
          opId: 'records:r1:h1',
          entity: 'records',
          action: 'upsert',
          row: {'id': 'r1', 'amount': 100},
          pushedHlc: 'h1',
        ),
      ]);
      expect(captured.url.path, '/rest/v1/rpc/apply_changes');
      expect(captured.headers['apikey'], 'anon');
      expect(captured.headers['authorization'], 'Bearer tok');
      final body = jsonDecode(captured.body) as Map;
      final op = (body['ops'] as List).single as Map;
      expect(op.keys.toSet(), {'op_id', 'entity', 'action', 'row'});
      expect(acks.single.serverSeq, 7);
      expect(acks.single.opId, 'records:r1:h1');
    });

    test('pull_changes: المعاملات والصفوف وsafe — و401 يجبر تحديثاً ويعيد',
        () async {
      var authFailures = 0;
      var refreshed = 0;
      final t = SupabaseTransport(
        baseUrl: _base,
        anonKey: 'anon',
        accessToken: () async => 'stale',
        onUnauthorized: () async {
          refreshed++;
          return 'fresh';
        },
        httpClient: MockClient((req) async {
          if (req.headers['authorization'] == 'Bearer stale') {
            authFailures++;
            return http.Response(jsonEncode({'message': 'JWT expired'}), 401);
          }
          final p = jsonDecode(req.body) as Map;
          expect(p['p_lower'], 5);
          expect(p['p_page_txid'], isNull);
          expect(p['p_page_seq'], 0);
          expect(p['p_limit'], 500);
          return _json({
            'rows': [
              {
                'entity': 'patients',
                'id': 'أحمد',
                'payload': {'id': 'أحمد', 'name': 'أحمد'},
                'clinic_id': null,
                '_hlc': '1:0:dev',
                '_deleted': false,
                '_origin': 'dev',
                'server_seq': 11,
                'txid': 900,
              },
            ],
            'safe': 1000,
          }, 200);
        }),
      );
      final page = await t.pullChanges(lower: 5, pageSeq: 0, limit: 500);
      expect(authFailures, 1);
      expect(refreshed, 1);
      expect(page.safe, 1000);
      final row = page.rows.single;
      expect(row.entity, 'patients');
      expect(row.payload['name'], 'أحمد');
      expect(row.deleted, isFalse);
      expect(row.txid, 900);
      expect(row.serverSeq, 11);
    });
  });

  group('R2Client', () {
    test('الرفع يعيد مفتاح العامل ويعيد المحاولة بعد فشل عابر', () async {
      var attempts = 0;
      final r2 = R2Client(
        workerUrl: 'https://xr.workers.dev',
        accessToken: () async => 'tok',
        delay: (_) async {},
        httpClient: MockClient((req) async {
          attempts++;
          if (attempts == 1) return http.Response('boom', 500);
          expect(req.headers['authorization'], 'Bearer tok');
          expect(req.url.queryParameters['key'], 'xray/u/p/1_a.png');
          return http.Response(jsonEncode({'key': 'srv/abc.jpg'}), 200);
        }),
      );
      final key = await r2.upload(
          Uint8List.fromList([1, 2, 3]), 'xray/u/p/1_a.png');
      expect(key, 'srv/abc.jpg');
      expect(attempts, 2);
    });

    test('الحذف: 404 نجاح («زال أصلاً») و500 فشل', () async {
      var status = 404;
      final r2 = R2Client(
        workerUrl: 'https://xr.workers.dev',
        accessToken: () async => 'tok',
        httpClient:
            MockClient((req) async => http.Response('', status)),
      );
      await r2.delete('k'); // لا رمي
      status = 500;
      await expectLater(r2.delete('k'), throwsException);
    });
  });

  group('خط أنابيب الأشعة', () {
    late Directory tmp;
    late ProviderContainer c;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('m5pipe_');
      c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Uint8List png() {
      final im = img.Image(width: 50, height: 30);
      img.fill(im, color: img.ColorRgb8(10, 90, 200));
      return img.encodePng(im);
    }

    test(
        'التصريف: مفتاح خادم مختلف ⇒ إعادة تخطيط كاملة بلا رفع مكرر، '
        'والتحقق الفاشل قاطعاً يبقيه معلقاً ثم يكمل بلا رفع ثانٍ (الحجز)',
        () async {
      final repos = c.read(reposProvider);
      final db = c.read(localDbProvider);
      final store =
          XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1');
      final r = store.ingest('هدى', 'scan.png', png());
      var cfg = addXrayKeyToConfig(
          <String, Object?>{}, 'هدى', r.key, 'scan.png');

      var uploads = 0;
      var corrupt = true; // أول تحقق يعيد بايتات خاطئة (تعارض قاطع)
      final remote = _FakeRemote(
        onUpload: (bytes, key) {
          uploads++;
          return 'srv/real_$uploads.jpg';
        },
        fetchOverride: (key) =>
            corrupt ? Uint8List.fromList([9, 9, 9]) : null,
      );
      final remaps = <(String, String)>[];
      final pipe = XrayPipeline(
        db: db,
        repos: repos,
        store: store,
        remote: remote,
        remapConfigKey: (temp, server, patient) {
          remaps.add((temp, server));
          cfg = remapXrayKeyInConfig(cfg, patient, temp, server);
        },
      );

      // جولة 1: الرفع يجري ويُحجز المفتاح، والتحقق يفشل قاطعاً ⇒ يبقى معلقاً.
      var res = await pipe.drainUploads();
      expect(res.kept, 1);
      expect(uploads, 1);
      expect(repos.xrays.getPendingUploads(), hasLength(1));

      // جولة 2: الشبكة سليمة الآن — يكمل **بلا رفع ثانٍ** (يستعمل الحجز).
      corrupt = false;
      res = await pipe.drainUploads();
      expect(res.uploaded, 1);
      expect(uploads, 1); // ← إصلاح التكرار: رفعة واحدة فقط
      expect(remaps.single, (r.key, 'srv/real_1.jpg'));

      // الصف الجديد مرفوع بمجموع تحقق، والمؤقت شاهدة ومستبعَد من القراءة.
      final rows = repos.xrays.getByPatient('هدى');
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'srv/real_1.jpg');
      expect(rows.single['upload_status'], 'uploaded');
      expect('${rows.single['checksum']}', isNotEmpty);
      expect(isXrayDeleted(db, r.key), isTrue); // مستبدَل ⇒ لا يظهر أبداً
      expect(xrayKeysFor(cfg, 'هدى'), ['srv/real_1.jpg']);
      expect(store.fileBytes('srv/real_1.jpg'), isNotNull);
      expect(store.fileBytes(r.key), isNull);
      expect(filterDeletedKeys(db, [r.key, 'srv/real_1.jpg']),
          ['srv/real_1.jpg']);

      // تصريف ثالث: لا معلق — لا شيء يحدث.
      res = await pipe.drainUploads();
      expect((res.uploaded, res.kept), (0, 0));
      expect(uploads, 1);
    });

    test('العامل يحترم المفتاح ⇒ markUploaded على الصف نفسه', () async {
      final repos = c.read(reposProvider);
      final store =
          XrayStore(repos: repos, baseDir: tmp.path, uid: 'u1');
      final r = store.ingest('سعاد', 'x.png', png());
      final pipe = XrayPipeline(
        db: c.read(localDbProvider),
        repos: repos,
        store: store,
        remote: _FakeRemote(onUpload: (bytes, key) => key),
      );
      final res = await pipe.drainUploads();
      expect(res.uploaded, 1);
      final row = repos.xrays.getByPatient('سعاد').single;
      expect(row['id'], r.key);
      expect(row['upload_status'], 'uploaded');
    });

    test('طابور الحذف: الفشل يبقي المفتاح والنجاح يفرغه', () async {
      final db = c.read(localDbProvider);
      enqueuePendingDelete(db, 'srv/a.jpg');
      enqueuePendingDelete(db, 'srv/a.jpg'); // لا تكرار
      enqueuePendingDelete(db, 'data:image/x'); // لا يُصفّ
      expect(pendingDeletes(db), ['srv/a.jpg']);

      var fail = true;
      final deleted = <String>[];
      final pipe = XrayPipeline(
        db: db,
        repos: c.read(reposProvider),
        store: XrayStore(
            repos: c.read(reposProvider), baseDir: tmp.path, uid: 'u1'),
        remote: _FakeRemote(onDelete: (k) {
          if (fail) throw Exception('offline');
          deleted.add(k);
        }),
      );
      var res = await pipe.drainDeletes();
      expect(res.kept, 1);
      expect(pendingDeletes(db), ['srv/a.jpg']);
      fail = false;
      res = await pipe.drainDeletes();
      expect(res.deleted, 1);
      expect(pendingDeletes(db), isEmpty);
      expect(deleted, ['srv/a.jpg']);
    });
  });

  group('جداول المعالجات — الأرقام حرفياً', () {
    test('التجميع باللقطات والنسبة الفعلية وفرع الصفر', () {
      final items = [
        {
          'name': 'أ', 'date': '2026-06-02', 'amount': 100,
          'payment': 'كاش',
          'service': 'حشو',
          '_rateSnapshot': {'doctorPct': 40},
        },
        {
          'name': 'ب', 'date': '2026-06-01', 'amount': 200,
          'payment': 'تحويل',
          'service': 'حشو',
          '_rateSnapshot': {'doctorPct': 40},
        },
        // سجل قديم بلا لقطة ⇒ النسبة الحية 50.
        {
          'name': 'ج', 'date': '2026-06-03', 'amount': 80,
          'payment': 'كاش', 'service': 'تنظيف',
        },
        // نسبة صفر ⇒ إيرادات فقط.
        {
          'name': 'د', 'date': '2026-06-04', 'amount': 60,
          'payment': 'كاش',
          'service': 'أشعة',
          '_rateSnapshot': {'doctorPct': 0},
        },
      ];
      final t = buildTreatmentTables(items, fallbackPct: 50);
      final byService = {for (final g in t.groups) g.service: g};

      final filling = byService['حشو']!;
      expect(filling.rows.first.name, 'ب'); // ترتيب بالتاريخ صعوداً
      expect(filling.revenue, 300);
      expect(filling.doctor, 120); // 40٪
      expect(filling.clinic, 180);
      expect(filling.effPct, 40);
      expect(filling.zeroPct, isFalse);

      expect(byService['تنظيف']!.doctor, 40); // النسبة الحية 50٪
      final xr = byService['أشعة']!;
      expect(xr.zeroPct, isTrue);
      expect(xr.revenue, 60);

      expect(t.revenue, 440);
      expect(t.doctor, 160);
      expect(t.clinic, 280);
    });

    test('formatNumber — فواصل الآلاف وخانتان عشريتان كحد أقصى', () {
      expect(formatNumber(1234567.5), '1,234,567.5');
      expect(formatNumber(1000), '1,000');
      expect(formatNumber(12.345), '12.35'); // تقريب لخانتين
      expect(formatNumber(0), '0');
      expect(formatNumber(null), '0');
      expect(formatNumber('x'), '0');
      expect(formatNumber(-5500.25), '-5,500.25');
    });
  });

  group('PDF عربي بخط القاهرة', () {
    PdfFonts fonts() => PdfFonts(
          regular: File('assets/fonts/Cairo-Regular.ttf')
              .readAsBytesSync()
              .buffer
              .asByteData(),
          bold: File('assets/fonts/Cairo-Bold.ttf')
              .readAsBytesSync()
              .buffer
              .asByteData(),
        );

    bool isPdf(Uint8List b) =>
        b.length > 1000 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44;

    test('التقارير الثلاثة تُبنى وتبدأ بتوقيع PDF', () async {
      final monthly = await monthlyReportPdf(
        fonts(),
        month: '2026-06',
        centerName: 'مركز الاختبار',
        currency: 'د.ل',
        data: const MonthData(
            inMem: true,
            cash: 200,
            xfer: 100,
            prosDoc: 90,
            prosTotal: 500,
            total: 800),
        recTables: buildTreatmentTables([
          {
            'name': 'أحمد', 'date': '2026-06-01', 'amount': 100,
            'payment': 'كاش',
            'service': 'حشو',
            '_rateSnapshot': {'doctorPct': 40},
          },
        ]),
        prosRows: [
          {
            'name': 'مريم', 'date': '2026-06-02', 'total': 500,
            'labValue': 200, 'doctorShare': 90, 'clinicShare': 210,
          },
        ],
        pendingDebts: [
          {'remaining': 150},
        ],
      );
      expect(isPdf(monthly), isTrue);

      final lab = await labReportPdf(
        fonts(),
        lab: 'مخبر النور',
        currency: 'د.ل',
        cases: labCases('مخبر النور', prosthetics: [
          {
            'id': 'p1', 'labName': 'مخبر النور', 'labValue': 200,
            'date': '2026-06-01', 'clinic': 'ع1', 'name': 'سالم',
            'prosType': 'زيركون', 'prosUnits': 2,
          },
        ], debts: const [], records: const []),
      );
      expect(isPdf(lab), isTrue);

      // v51 — طباعة التركيبات (تفصيل الخزينة) بالتصميم الجديد: مجموعة
      // بمريض واحد فيها تركيبة ودفعة دين — يمرّن مسارَي rowOf كليهما.
      final prosG = ProsGroup('سالم')
        ..total = 1000
        ..labTotal = 380
        ..docTotal = 310
        ..clinTotal = 310;
      prosG.items.add({
        '_t': 'p', 'date': '2026-06-03', 'prosType': 'زيركون',
        'prosUnits': 2, 'total': 1000, 'labValue': 300,
        'doctorShare': 350, 'clinicShare': 350,
      });
      prosG.items.add({
        'date': '2026-06-10', 'amount': 200,
        '_labAmount': 80, '_docAmount': 60,
      });
      final prosPdf = await prostheticsReportPdf(
        fonts(),
        title: 'ع1 — تركيبات',
        subtitle: '2026-06',
        currency: 'د.ل',
        groups: [prosG],
        doctorPct: 50,
      );
      expect(isPdf(prosPdf), isTrue);

      final tooth = await toothReportPdf(
        fonts(),
        clinicName: 'مركز الاختبار',
        date: getCurrentDate(),
        currency: 'د.ل',
        meta: {
          'name': 'هدى', 'phone': '0911111111', 'age': '30',
          'diagnosis': 'تسوس', 'notes': 'مراجعة بعد أسبوع',
          'conditions': ['السكري'],
        },
        entries: [
          {
            'teeth': [
              {'q': 'UR', 'n': 1},
              {'q': 'LL', 'n': 3},
            ],
            'service': 'حشو',
            'cost': 120,
          },
        ],
      );
      expect(isPdf(tooth), isTrue);
    });
  });

  group('الإعداد السحابي والمبدّل', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m5cfg_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('بلا ملف ⇒ وضع محلي؛ بملف ⇒ ناقل ومصادقة Supabase', () {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);
      expect(c.read(cloudConfigProvider), isNull);
      expect(c.read(transportProvider), isA<FakeSyncServer>());
      expect(c.read(authServiceProvider), isA<LocalAuthService>());
      expect(c.read(xrayPipelineProvider), isNull);

      saveCloudConfig(
          tmp.path,
          const CloudConfig(
              supabaseUrl: 'https://proj.supabase.co',
              anonKey: 'anon',
              r2WorkerUrl: 'https://xr.workers.dev'));
      c.read(cloudConfigRevProvider.notifier).state++;

      final cfg = c.read(cloudConfigProvider);
      expect(cfg?.hasSync, isTrue);
      expect(cfg?.hasImages, isTrue);
      expect(c.read(transportProvider), isA<SupabaseTransport>());
      expect(c.read(authServiceProvider), isA<SupabaseAuthService>());
      expect(c.read(xrayPipelineProvider), isNotNull);

      // المسح يعيد الوضع المحلي.
      saveCloudConfig(tmp.path, null);
      c.read(cloudConfigRevProvider.notifier).state++;
      expect(c.read(cloudConfigProvider), isNull);
      expect(c.read(transportProvider), isA<FakeSyncServer>());
    });

    test('ملف تالف أو ناقص ⇒ null (وضع محلي آمن)', () {
      File('${tmp.path}/cloud_config.json').writeAsStringSync('غير json');
      expect(loadCloudConfig(tmp.path), isNull);
      File('${tmp.path}/cloud_config.json')
          .writeAsStringSync(jsonEncode({'supabaseUrl': 'https://x.co'}));
      expect(loadCloudConfig(tmp.path), isNull); // بلا مفتاح
    });
  });
}

/// طرف بعيد مزيف للصور — سلوك قابل للبرمجة لكل اختبار.
class _FakeRemote implements XrayRemote {
  _FakeRemote({this.onUpload, this.onDelete, this.fetchOverride});

  final String Function(Uint8List bytes, String key)? onUpload;
  final void Function(String key)? onDelete;

  /// بايتات مخالفة للتحقق (null = يعيد ما رُفع).
  final Uint8List? Function(String key)? fetchOverride;

  final Map<String, Uint8List> objects = {};

  @override
  Future<String> upload(Uint8List bytes, String key,
      {String patientName = '',
      String fileName = '',
      String contentType = 'image/jpeg'}) async {
    final serverKey = onUpload?.call(bytes, key) ?? key;
    objects[serverKey] = bytes;
    return serverKey;
  }

  @override
  Future<R2HeadResult> headObject(String key) async =>
      R2HeadResult(ok: objects.containsKey(key), size: objects[key]?.length);

  @override
  Future<Uint8List?> fetchBytes(String key, {bool thumb = false}) async =>
      fetchOverride?.call(key) ?? objects[key];

  @override
  Future<void> delete(String key) async {
    onDelete?.call(key);
    objects.remove(key);
  }
}
