/// اختبارات م18 — تكافؤ السلك مع تطبيق Vue الأصلي (علة «المعالجات ما ظهرت»):
/// م17 أثبت الإسقاط ببذور Flutter؛ هنا نبذر الخادم بحمولات مطابقة **حرفياً**
/// لما يدفعه push.js في Vue (سجل معالجة مسطّح بحقول الـ blob مدموجة على
/// الصف + صف settings قيمته كائن فيه treatmentPlans/patientMedical) ثم:
///   1) جهاز Flutter جديد يسحب فتظهر سجلات المعالجة وخطط العلاج فوراً في
///      إسقاطات الواجهة الفعلية (patientMap/appConfig) بلا إعادة تشغيل.
///   2) سيناريو الاستنساخ الجذري: كتابة إعدادات محلية قبل أول مزامنة
///      (ما تفعله شاشة الإضافة عند حفظ معلومات طبية) يجب ألا تحجب إعدادات
///      الحساب النازلة ولا تمسح خطط العلاج صعوداً — توأم قائمة
///      FIELD_MERGE_ROLLOUT الإنتاجية الشاملة `settings` في featureFlags.js.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/data/sync/feature_flags.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:dental_clinic_flutter/features/finance/finance_screen.dart'
    show financeRevProvider;
import 'package:dental_clinic_flutter/features/patients/patients_tab.dart'
    show patientMapProvider, patientsRevProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// حساب الإنتاج المشترك بين التطبيقين (RLS يعزل به الصفوف على الخادم).
const vueUid = 'vue-shared-account-uid';
const vueDevice = 'vue-desktop-7f3a';
const patientName = 'سالم المقطوف';

/// قاعدة زمنية ماضية (أمس تقريباً) — ساعة HLC لجهاز Vue أقدم حتماً من ساعة
/// حائط الجهاز الجديد، وهي حال الحساب الحقيقي (بياناته كُتبت قبل التثبيت).
final seedMs = DateTime.now().millisecondsSinceEpoch - 86400000;

/// دفعة «جهاز Vue»: op_id/entity/action/row كما يبنيها push.js حرفياً
/// (الحمولة صف مسطّح بلا data/_dirty/server_seq).
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

/// إعدادات حساب Vue — فيها خطط علاج وقوائم ومعلومات طبية (شكل الإنتاج).
Map<String, Object?> vueConfig() => {
      'centerName': 'مركز الأصل السحابي',
      'doctorPct': 45,
      'clinics': ['عيادة الصفوة'],
      'services': ['حشو ضوئي', 'تنظيف'],
      'payments': ['كاش', 'بطاقة'],
      'treatmentPlans': {
        patientName: [
          {
            'id': 'tp1',
            'desc': 'مرحلة الحشو',
            'done': true,
            'doneDate': '2026-07-20',
          },
          {'id': 'tp2', 'desc': 'مرحلة التنظيف', 'done': false, 'doneDate': ''},
        ],
      },
      'patientMedical': {
        patientName: {
          'gender': 'ذكر',
          'age': 40,
          'conditions': ['ضغط'],
          'diagnosis': '',
          'notes': '',
        },
      },
    };

/// يبذر الخادم بما يدفعه تطبيق Vue فعلياً: مريض + سجل معالجة + الإعدادات.
Future<void> seedVueAccount(FakeSyncServer server) async {
  // مريض — id بمفتاح الاسم (دلالة patients.id القديمة في الأصل).
  await vuePush(server, 'patients', {
    'id': patientName,
    'name': patientName,
    'phone': '0912345678',
    'notes': '',
    'last_visit': '2026-07-20',
    'created_at': '2026-07-01T10:00:00.000Z',
    'updated_at': '2026-07-20T10:00:00.000Z',
    '_mod': seedMs,
    '_deleted': 0,
    'owner_uid': vueUid,
    '_hlc': '$seedMs:0:$vueDevice',
    '_origin': vueDevice,
    'clinic_id': '',
    'patient_id': patientName,
    // حقول blob تسافر مسطّحة على السلك:
    'clinic': 'عيادة الصفوة',
    'gender': 'ذكر',
  });
  // سجل معالجة — الأعمدة المرقّاة + حقول الـ blob (name/phone/tooth/notes).
  await vuePush(server, 'records', {
    'id': 'r_vue_1001',
    'patient_name': patientName,
    'date': '2026-07-20',
    'service': 'حشو ضوئي',
    'amount': 250,
    'clinic': 'عيادة الصفوة',
    'created_at': '2026-07-20T11:00:00.000Z',
    'updated_at': '2026-07-20T11:00:00.000Z',
    '_mod': seedMs + 1000,
    '_deleted': 0,
    'clinic_id': '',
    '_hlc': '${seedMs + 1000}:0:$vueDevice',
    '_origin': vueDevice,
    'owner_uid': vueUid,
    'payment': 'كاش',
    'isDebt': 0,
    'isPros': 0,
    'isDebtPayment': 0,
    'debtId': null,
    'patient_id': patientName,
    'name': patientName,
    'phone': '0912345678',
    'tooth': '26',
    'notes': 'زيارة أولى',
  });
  // الإعدادات — حمولة settings في push.js: { id, value, clinic_id, _hlc, _origin }.
  await vuePush(server, 'settings', {
    'id': 'app.config',
    'value': vueConfig(),
    'clinic_id': '',
    '_hlc': '${seedMs + 2000}:0:$vueDevice',
    '_origin': vueDevice,
  });
}

void main() {
  late FakeSyncServer server;
  late Directory tmp;

  setUp(() async {
    syncFlags.resetForTest();
    server = FakeSyncServer();
    await seedVueAccount(server);
    tmp = Directory.systemTemp.createTempSync('m18_dev_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer freshDevice() {
    final c = ProviderContainer(overrides: [
      dbDirProvider.overrideWithValue(tmp.path),
      transportProvider.overrideWithValue(server),
    ]);
    // إنتاجياً يتشارك التطبيقان حساباً واحداً: استرجاع الجلسة يثبّت uid
    // الحساب نفسه قبل أي مزامنة (توأم setRepositoryOwner بعد الدخول).
    c.read(localDbProvider).setOwnerUid(vueUid);
    return c;
  }

  group('م18/1 — صفوف Vue الحرفية تظهر فوراً على جهاز Flutter جديد', () {
    test('سجل المعالجة وخطة العلاج والإعدادات تصل وتُسقط على الواجهة بلا إعادة تشغيل',
        () async {
      final c = freshDevice();
      addTearDown(c.dispose);

      // قبل: لا شيء (شكوى المستخدم حرفياً).
      expect(c.read(appConfigProvider), isEmpty);
      expect(c.read(patientMapProvider), isEmpty);
      final cfg0 = c.read(configRevProvider);
      final pat0 = c.read(patientsRevProvider);
      final fin0 = c.read(financeRevProvider);

      final r = await c.read(syncEngineProvider).syncNow();
      expect(r.ok, isTrue);
      expect(r.merged, greaterThanOrEqualTo(3));

      // سجل المعالجة وصل بحقول الـ blob سليمة (name من داخل data).
      final recs = c.read(reposProvider).records.getAll();
      expect(recs, hasLength(1));
      expect(recs.first['name'], patientName);
      expect(recs.first['payment'], 'كاش');
      expect(recs.first['tooth'], '26');

      // إسقاط «السجلات» الفعلي: خريطة المرضى تحوي المريض بزيارة ومجموعها.
      // م35 — مفتاح الخريطة مركب (اسم|عيادة).
      final pmap = c.read(patientMapProvider);
      const pKey = '$patientName|عيادة الصفوة';
      expect(pmap.containsKey(pKey), isTrue,
          reason: 'المريض يجب أن يظهر في تبويب السجلات فوراً');
      expect(pmap[pKey]!.visitCount, 1);
      expect(pmap[pKey]!.total, 250);

      // خطة العلاج وصلت داخل app.config (مصدر نافذة خطة العلاج في الملف).
      final cfg = c.read(appConfigProvider);
      final plans = cfg['treatmentPlans'] as Map?;
      expect(plans, isNotNull, reason: 'خطط العلاج يجب أن تنزل مع الإعدادات');
      final stages = plans![patientName] as List;
      expect(stages, hasLength(2));
      expect((stages.first as Map)['done'], true);
      expect(cfg['centerName'], 'مركز الأصل السحابي');

      // عدّادات الإسقاط قفزت (م17) — الواجهة تُعاد بناؤها بلا إعادة تشغيل.
      expect(c.read(configRevProvider), greaterThan(cfg0));
      expect(c.read(patientsRevProvider), greaterThan(pat0));
      expect(c.read(financeRevProvider), greaterThan(fin0));
    });
  });

  group('م18/2 — تعديل إعدادات محلي قبل أول مزامنة لا يحجب ولا يمسح', () {
    test('كتابة patientMedical محلياً (سلوك شاشة الإضافة) ثم مزامنة: الطرفان يُدمجان بنيوياً',
        () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      final repos = c.read(reposProvider);

      // الجهاز الجديد كتب معلومات طبية لمريض جديد قبل أول مزامنة —
      // ما تفعله add_record_screen حرفياً: set('app.config', {...cur, patientMedical}).
      repos.settings.set('app.config', {
        'patientMedical': {
          'زائر جديد': {'age': 30, 'gender': 'أنثى'},
        },
      });

      // دورتان: الأولى تدمج وتكتب المزيج قذراً، والثانية تدفعه للخادم.
      final r1 = await c.read(syncEngineProvider).syncNow();
      expect(r1.ok, isTrue);
      final r2 = await c.read(syncEngineProvider).syncNow();
      expect(r2.ok, isTrue);

      final cfg = c.read(appConfigProvider);
      // إعدادات الحساب نزلت رغم التعديل المحلي الأحدث ساعةً:
      expect(cfg['centerName'], 'مركز الأصل السحابي',
          reason: 'kept-local يجب ألا يحجب إعدادات الحساب كلها');
      final plans = cfg['treatmentPlans'] as Map?;
      expect(plans?[patientName], isNotNull,
          reason: 'خطط العلاج يجب ألا تُحجب بتعديل محلي لمفتاح آخر');
      // والتعديل المحلي لم يضِع (دمج بنيوي لا LWW بالقيمة الكاملة):
      final med = cfg['patientMedical'] as Map;
      expect((med['زائر جديد'] as Map)['age'], 30);
      expect((med[patientName] as Map?)?['age'], 40,
          reason: 'قيم الحساب القديمة تبقى جنباً إلى جنب مع الجديدة');

      // الخادم لم يُمسح: قيمته النهائية تجمع الطرفين معاً.
      final srv = server.rows['settings']!['app.config']!;
      final srvCfg = Map<String, Object?>.from(srv.payload['value'] as Map);
      expect(srvCfg['treatmentPlans'], isNotNull,
          reason: 'الدفع يجب ألا يستبدل إعدادات الحساب فيمسح خطط العلاج');
      // v30 — الإعدادات تُدفع **صفوفاً مستقلة**: الكتلة القديمة تبقى
      // أرشيفاً لم يُمس (فلا تُمسح خطط الحساب)، والتعديل الجديد يصل
      // الخادم بصفّه الخاص لكل ورقة.
      final srvLeafRows = server.rows['settings']!.keys
          .where((k) => k.startsWith('cfg:s:patientMedical'))
          .toList();
      expect(srvLeafRows, isNotEmpty,
          reason: 'ورقة المعلومات الطبية الجديدة وصلت الخادم بصفّها');
      expect(srvCfg['centerName'], 'مركز الأصل السحابي');
    });

    test('سجلات المعالجة نفسها تصل حتى مع إعدادات محلية قذرة (كيانات الصفوف لا تتأثر)',
        () async {
      final c = freshDevice();
      addTearDown(c.dispose);
      c.read(reposProvider).settings.set('app.config', {
        'patientMedical': {
          'زائر جديد': {'age': 30},
        },
      });
      final r = await c.read(syncEngineProvider).syncNow();
      expect(r.ok, isTrue);
      expect(c.read(reposProvider).records.getAll(), hasLength(1));
      expect(
          c
              .read(patientMapProvider)
              .containsKey('$patientName|عيادة الصفوة'),
          isTrue);
    });
  });
}
