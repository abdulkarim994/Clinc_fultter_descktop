/// قياس م72 — تكلفة الحركة اليومية على السلك (لا التخزين).
///
/// السؤال: كم بايتاً يستهلك الحساب الواحد شهرياً على سقف الصادر (5 غ.ب)؟
/// الحساب النظري لا يكفي — الترويسات وJSON والاستطلاع الفارغ كلها بايتات
/// حقيقية. لذا: **خادم HTTP محلي يعدّ كل بايت**، والناقل الحقيقي
/// (SupabaseTransport) يتحدث إليه بلا أي تزييف.
///
/// يُشغَّل كاختبار كي يبقى قابلاً للتكرار والمراجعة، ويطبع جدولاً.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/data/cloud/supabase_transport.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// خادم يعدّ بايتات الطلب (سطر الطلب + الترويسات + الجسم) والاستجابة.
class CountingServer {
  CountingServer(this._rows);

  final List<Map<String, Object?>> _rows;
  late HttpServer _s;
  int reqBytes = 0;
  int resBytes = 0;      // مضغوط — هذا ما يُحاسَب عليه الصادر
  int resBytesRaw = 0;   // غير مضغوط — للمقارنة فقط

  int get total => reqBytes + resBytes;

  Future<String> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((HttpRequest r) async {
      // ── عدّ الطلب: سطر الطلب + الترويسات + الجسم ──
      var head = '${r.method} ${r.uri} HTTP/1.1\r\n';
      r.headers.forEach((k, v) {
        for (final x in v) {
          head += '$k: $x\r\n';
        }
      });
      head += '\r\n';
      reqBytes += utf8.encode(head).length;
      final body = await utf8.decoder.bind(r).join();
      reqBytes += utf8.encode(body).length;

      // ── الرد بحسب الدالة ──
      final fn = r.uri.pathSegments.last;
      final Object payload;
      if (fn == 'pull_changes') {
        payload = {
          'rows': _rows,
          'next_lower': 1,
          'next_txid': null,
          'next_seq': 0,
          'has_more': false,
        };
      } else if (fn == 'apply_changes') {
        final ops = (jsonDecode(body) as Map)['ops'] as List;
        payload = {
          'results': [
            for (var i = 0; i < ops.length; i++)
              {
                'op_id': '${(ops[i] as Map)['op_id']}',
                'id': '${((ops[i] as Map)['row'] as Map)['id']}',
                'server_seq': i + 1,
              },
          ],
        };
      } else {
        payload = {'purged': 0};
      }
      final out = utf8.encode(jsonEncode(payload));

      // ترويسات استجابة واقعية (PostgREST خلف Cloudflare)
      final hdrs = <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'content-length': '${out.length}',
        'date': HttpDate.format(DateTime.now()),
        'server': 'cloudflare',
        'cf-ray': '8f2a1b3c4d5e6f70-FRA',
        'sb-gateway-version': '1',
        'x-content-type-options': 'nosniff',
        'strict-transport-security': 'max-age=31536000',
        'vary': 'Accept-Encoding',
      };
      var resHead = 'HTTP/1.1 200 OK\r\n';
      hdrs.forEach((k, v) {
        resHead += '$k: $v\r\n';
        r.response.headers.set(k, v);
      });
      resHead += '\r\n';
      // الصادر الحقيقي مضغوط: Cloudflare يخدم gzip/br لكل استجابة JSON.
      // نعدّ الجسم مضغوطاً (gzip) لأن هذا ما يعبر السلك فعلاً ويُحاسَب عليه.
      resBytes += utf8.encode(resHead).length + gzip.encode(out).length;
      resBytesRaw += utf8.encode(resHead).length + out.length;

      r.response.statusCode = 200;
      r.response.add(out);
      await r.response.close();
    });
    return 'http://${_s.address.address}:${_s.port}';
  }

  Future<void> stop() => _s.close(force: true);
  void reset() {
    reqBytes = 0;
    resBytes = 0;
    resBytesRaw = 0;
  }
}

/// حمولة سجل واقعية **متنوّعة** — الأشكال والأطوال مطابقة للمقيس من
/// الإنتاج، والمحتوى مختلف بين الصفوف كما في عيادة حقيقية. التنويع ضروري:
/// صفوف متطابقة تعطي ضغطاً وهمياً عالياً ورقماً متفائلاً كاذباً.
const _names = [
  'محمد علي المبروك', 'فاطمة الزهراء سالم', 'أحمد عبدالسلام قنيوة',
  'خديجة المهدي الفيتوري', 'عمر يوسف الشريف', 'مريم عبدالله بن نصر',
  'يوسف إبراهيم الورفلي', 'زينب مصطفى العبيدي', 'صالح ناصر الزوي',
  'نور الهدى خالد بالحاج',
];
const _services = [
  'حشو ضرس تجميلي', 'خلع بسيط بالبنج الموضعي', 'تنظيف جير وتلميع',
  'علاج عصب لضرس علوي', 'تركيبة زيركون كاملة', 'تبييض بالليزر',
  'حشو أمامي تجميلي', 'جسر خزفي ثلاثي', 'زراعة سن أمامي', 'تقويم شفاف',
];
const _notes = [
  'المريض يشكو من ألم عند المضغ على الجهة اليمنى',
  'حساسية معروفة من البنج الموضعي — استُعمل بديل',
  'يحتاج متابعة بعد أسبوعين لتقييم الالتهاب',
  'شُرحت خطة العلاج كاملة ووافق المريض عليها',
  null,
];
const _pays = ['كاش', 'دين', 'تحويل', 'بطاقة'];

Map<String, Object?> realRecord(int i) {
  final n = _names[i % _names.length];
  final sv = _services[(i * 3) % _services.length];
  final nt = _notes[(i * 7) % _notes.length];
  final amt = 40 + (i * 137) % 860;
  final ph = '09${(10000000 + i * 8675309) % 90000000}';
  final hlc = '${1785361250645 + i * 977}:${i % 97}:dev${(i * 31) % 9997}';
  return {
    'entity': 'records',
    'id': 'rec_${(i * 2654435761) % 4294967296}',
    'payload': {
      '_hlc': hlc,
      'uid': 'aaaaaaaa-bbbb-4ccc-8ddd-${(100000000000 + i * 7919)}',
      'owner_uid': 'aaaaaaaa-bbbb-4ccc-8ddd-ffffffffffff',
      'id': 'rec_${(i * 2654435761) % 4294967296}',
      '_origin': 'dev${(i * 31) % 9997}a1b2c3d4e5f6g7h8',
      'clinic_id': 'cccccccc-dddd-4eee-8fff-00000000000${i % 3}',
      'updated_at': '2026-07-${10 + i % 20}T${8 + i % 12}:${i % 60}:00.000Z',
      'created_at': '2026-07-${10 + i % 20}T${8 + i % 12}:${i % 60}:00',
      'patient_id': 'p:$ph',
      '_activityAt': 1785361250645 + i * 977,
      '_mod': 1785361250645 + i * 977,
      'service': sv,
      'date': '2026-07-${(10 + i % 20).toString().padLeft(2, '0')}',
      'name': n,
      'patient_name': n,
      'clinic': i.isEven ? 'العيادة الرئيسية' : 'فرع الحي',
      'phone': ph,
      'payment': _pays[i % _pays.length],
      'amount': amt,
      'isDebt': i % 5 == 0 ? 1 : 0,
      'isPros': 0,
      'isDebtPayment': 0,
      'notes': nt,
      'phone2': null,
      '_edited': i % 4 == 0,
      'report': null,
      'reportMeta': null,
      'debtId': i % 5 == 0
          ? 'dddddddd-eeee-4fff-8aaa-${(200000000000 + i * 6271)}'
          : null,
      '_fullAmount': amt,
      '_rateSnapshot': {
        'usd': 4.9 + (i % 17) / 100,
        'eur': 5.3 + (i % 23) / 100,
        'at': '2026-07-${10 + i % 20}T${8 + i % 12}:${i % 60}:00.000Z',
        'src': i.isEven ? 'manual' : 'auto',
        'v': 2,
      },
    },
    '_hlc': hlc,
    '_deleted': false,
    'clinic_id': 'cccccccc-dddd-4eee-8fff-00000000000${i % 3}',
    'server_seq': i,
    'txid': i,
  };
}

void main() {
  test('م72 — قياس بايتات السلك الفعلية', () async {
    // ═══ ١) استطلاع فارغ ═══
    final empty = CountingServer([]);
    final urlE = await empty.start();
    addTearDown(empty.stop);
    final tE = SupabaseTransport(
      baseUrl: urlE,
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV4YW1wbGVyZWZ4eHh4eHh4eHh4Iiwicm9sZSI6'
          'ImFub24iLCJpYXQiOjE3NDY3MjAwMDAsImV4cCI6MjA2MjI5NjAwMH0.'
          'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfG',
      accessToken: () async =>
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNzg1MzY0ODAwLCJzdWIiOiI1OWI3Nzcy'
          'YS0zYjE2LTRmOTktOTNmOC02ZjQwMzY1MmU2NjciLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.'
          'ZyXwVuTsRqPoNmLkJiHgFeDcBa9876543210ZyXwVuT',
    );
    await tE.pullChanges(lower: 0, pageSeq: 0, limit: 500);
    final emptyOut = empty.resBytes;
    final emptyIn = empty.reqBytes;
    final emptyRaw = empty.resBytesRaw;

    // ═══ ٢) سحب دفعة (20 سجلاً) ═══
    final full = CountingServer([for (var i = 0; i < 20; i++) realRecord(i)]);
    final urlF = await full.start();
    addTearDown(full.stop);
    final tF = SupabaseTransport(
      baseUrl: urlF,
      anonKey: 'anon.jwt.placeholder-with-realistic-length-000000000000000000',
      accessToken: () async =>
          'access.jwt.placeholder-with-realistic-length-00000000000000000000',
    );
    await tF.pullChanges(lower: 0, pageSeq: 0, limit: 500);
    final pull20Out = full.resBytes;
    final pull20Raw = full.resBytesRaw;

    // ═══ ٣) دفع دفعة (20 عملية) ═══
    full.reset();
    await tF.applyChanges([
      for (var i = 0; i < 20; i++)
        WireOp(
          opId: 'records:rec_$i:178536125064$i:3:devA1b2c3',
          entity: 'records',
          action: 'upsert',
          row: realRecord(i)['payload']! as Map<String, Object?>,
          pushedHlc: '178536125064$i:3:devA1b2c3',
        ),
    ]);
    final push20Out = full.resBytes;
    final push20In = full.reqBytes;

    // ═══ النتائج ═══
    // ignore: avoid_print
    print('''

╔══════════════════════════════════════════════════════════════╗
║  قياس بايتات السلك — خادم محلي يعدّ الطلب والاستجابة كاملين  ║
╚══════════════════════════════════════════════════════════════╝
  الصادر = الاستجابات فقط (مضغوطة gzip كما تخدمها Cloudflare)

  استطلاع فارغ  : صادر $emptyOut ب  · وارد $emptyIn ب  (بلا ضغط: $emptyRaw)
  سحب 20 سجلاً   : صادر $pull20Out ب  ⇒ ${(pull20Out / 20).round()} ب/سجل  (بلا ضغط: $pull20Raw)
  دفع 20 عملية   : صادر $push20Out ب  · وارد $push20In ب
  نسبة الضغط    : ${(100 - pull20Out / pull20Raw * 100).round()}٪ توفير
''');

    // حراسة: الأرقام يجب أن تبقى في نطاق معقول وإلا تغيّر شيء جوهري.
    expect(emptyOut, greaterThan(200));
    expect(emptyOut, lessThan(3000));
    expect(pull20Out, greaterThan(emptyOut));
  });
}
