/// اختبارات م21 — أشكال صفوف Vue الحقيقية (علة «مسجّل أعلى الملف وما ظاهر
/// بالسجل»): كائنات Vue تحمل اسم المريض في حقل `name` ولا تملأ عمود
/// `patient_name` إطلاقاً — فالتجميعات الذاكريّة تری الصفوف بينما استعلامات
/// القوائم `WHERE patient_name = ?` تخفيها. الإصلاح: تطبيع عند الدمج
/// (normalizeServerRow) + مكنسة شفاء بعد كل سحب (backfillPulledRows)
/// للصفوف الواصلة قبل الإصلاح على أجهزة قائمة.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show patientMapProvider;
import 'package:dental_clinic_flutter/features/xrays/xray_store.dart'
    show dataUrlBytes;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const vueUid = 'vue-shared-account-uid';
const vueDevice = 'vue-desktop-7f3a';
const patientName = 'حشان الحقيقي';

final seedMs = DateTime.now().millisecondsSinceEpoch - 86400000;

Future<void> vuePush(
    FakeSyncServer server, String entity, Map<String, Object?> row) async {
  await server.applyChanges([
    WireOp(
      opId: '$entity:${row['id']}:${row['_hlc']}',
      entity: entity,
      action: '${row['_deleted']}' == '1' ? 'delete' : 'upsert',
      row: row,
      pushedHlc: '${row['_hlc']}',
    ),
  ]);
}

Map<String, Object?> _base(String id, int offset) => {
      'id': id,
      'created_at': '2026-07-20T10:00:00.000Z',
      'updated_at': '2026-07-20T10:00:00.000Z',
      '_mod': seedMs + offset,
      '_deleted': 0,
      'clinic_id': '',
      '_hlc': '${seedMs + offset}:0:$vueDevice',
      '_origin': vueDevice,
      'owner_uid': vueUid,
    };

/// البذر بالشكل الحقيقي: **لا patient_name ولا patient_id إطلاقاً** —
/// الاسم في حقل `name` وحده (كما تدفع كائنات Vue حرفياً).
Future<void> seedVueRealShapes(FakeSyncServer server) async {
  await vuePush(server, 'patients', {
    ..._base(patientName, 0),
    'name': patientName,
    'phone': '0913334455',
    'clinic': 'الصفوة',
  });
  await vuePush(server, 'records', {
    ..._base('r_real_1', 1000),
    'name': patientName,
    'date': '2026-07-20',
    'service': 'خلع',
    'amount': 1000,
    'clinic': 'الصفوة',
    'payment': 'كاش',
    'isDebt': 0,
    'isPros': 0,
    'isDebtPayment': 0,
  });
  await vuePush(server, 'prosthetics', {
    ..._base('p_real_1', 2000),
    'name': patientName,
    'date': '2026-07-21',
    'type': 'تاج زركون',
    'amount': 400,
    'clinic': 'الصفوة',
    'doctorShare': 120,
  });
  await vuePush(server, 'debts', {
    ..._base('d_real_1', 3000),
    'name': patientName,
    'date': '2026-07-20',
    'service': 'تقويم',
    'clinic': 'الصفوة',
    // مبالغ Vue بمفاتيحها الأصلية (camelCase في كتلة الـ blob).
    'totalAmount': 900,
    'paidAmount': 300,
    'remaining': 600,
  });
  await vuePush(server, 'xrays', {
    ..._base('x_real_1', 4000),
    'patient_name': patientName, // عمود قائم في الأصل منذ البداية
    'file_key': 'xr/2026/x_real_1.jpg',
    'thumbnail_data':
        'data:image/jpeg;base64,${base64Encode(List.filled(64, 7))}',
    'upload_status': 'uploaded',
  });
}

void main() {
  late FakeSyncServer server;
  late Directory tmp;

  setUp(() async {
    syncFlags.resetForTest();
    server = FakeSyncServer();
    await seedVueRealShapes(server);
    tmp = Directory.systemTemp.createTempSync('m21_dev_');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer freshDevice() {
    final c = ProviderContainer(overrides: [
      dbDirProvider.overrideWithValue(tmp.path),
      transportProvider.overrideWithValue(server),
    ]);
    c.read(localDbProvider).setOwnerUid(vueUid);
    return c;
  }

  group('م21/1 — التطبيع عند الدمج يملأ أعمدة الربط', () {
    test('قائمة زيارات الملف وديونه وأشعته تجد صفوف Vue الحقيقية', () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      final r = await c.read(syncEngineProvider).syncNow();
      expect(r.ok, isTrue);
      final repos = c.read(reposProvider);

      // جوهر العلة: القوائم تستعلم بعمود patient_name.
      final visits = repos.records.getByPatient(patientName);
      expect(visits, hasLength(1),
          reason: 'سجل المعالجة يجب أن يظهر في قائمة الزيارات');
      expect(visits.single['service'], 'خلع');
      expect(visits.single['patient_id'], patientName);

      expect(repos.debts.getDebtsByPatient(patientName), hasLength(1),
          reason: 'دين المريض يجب أن يظهر في قسم الديون');
      expect(repos.xrays.getByPatient(patientName), hasLength(1));

      // عمود التركيبات مُلئ أيضاً (تُقرأ ذاكرياً لكن العمود أساس مستقبلي).
      final pros = repos.prosthetics.getAll().single;
      expect(pros['patient_name'], patientName);

      // التجميعة أعلى الملف كما كانت — والاسمان متطابقان الآن مصدراً.
      // م35 — مفتاح الخريطة مركب (اسم|عيادة).
      final agg =
          c.read(patientMapProvider)['$patientName|الصفوة'];
      expect(agg, isNotNull);
      expect(agg!.visitCount, greaterThanOrEqualTo(1));

      // مصغرة الأشعة المتزامنة موجودة في العمود وقابلة للفك.
      final thumb =
          repos.xrays.getThumbnail('xr/2026/x_real_1.jpg');
      expect(dataUrlBytes(thumb), isNotNull,
          reason: 'المصغرة تسافر مع الصف ويجب أن تكون جاهزة بلا شبكة');
    });
  });

  group('م21/2 — مكنسة الشفاء بعد السحب', () {
    test('صف قديم وصل قبل الإصلاح (عموده فارغ) يُشفى بدورة مزامنة واحدة',
        () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);

      // محاكاة قاعدة الهاتف الحالية: صف خادم بالشكل القديم كُتب مباشرة
      // (كما كتبه الدمج قبل التطبيع) — عمود patient_name فارغ.
      repos.records.upsert({
        'id': 'r_pre_fix',
        'name': patientName, // في كتلة الـ blob فقط
        'date': '2026-07-19',
        'service': 'حشو قديم',
        'amount': 250,
        'clinic': 'الصفوة',
        'payment': 'كاش',
        '_dirty': 0,
        '_hlc': '${seedMs - 5000}:0:$vueDevice',
        '_origin': vueDevice,
      });
      expect(repos.records.getByPatient(patientName)
              .where((x) => x['id'] == 'r_pre_fix'),
          isEmpty,
          reason: 'قبل الشفاء: القائمة لا تراه');

      final r = await c.read(syncEngineProvider).syncNow();
      expect(r.ok, isTrue);

      final healed = repos.records.getByPatient(patientName);
      expect(healed.where((x) => x['id'] == 'r_pre_fix'), hasLength(1),
          reason: 'مكنسة ما بعد السحب تملأ العمود من كتلة الـ blob');
      final row =
          healed.firstWhere((x) => x['id'] == 'r_pre_fix');
      expect(row['patient_id'], patientName);
    });
  });
}
