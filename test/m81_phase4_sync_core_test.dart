/// اختبارات م81 — المرحلة الرابعة: قلب المزامنة.
///
///  أخطر تعديل في الخطة كلها. الاختبار المحوري هنا هو **التبادلية**: نفس
///  العمليات بترتيبَي وصول مختلفين يجب أن تُنتج الحالة نفسها. وقبل م81
///  كانت تُنتج حالتين — وتختفي قيمة أحدث بلا أثر.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/repositories/repositories.dart';
import 'package:dental_clinic_flutter/data/sync/conflict_notice.dart';
import 'package:dental_clinic_flutter/data/sync/merge/merge_engine.dart'
    show defaultIsNewer;
import 'package:dental_clinic_flutter/data/sync/merge/field_merge.dart';
import 'package:dental_clinic_flutter/data/sync/merge/row_fmeta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m81_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // ══════════════════════════════════════════════════════════════════════
  group('م81/أ — ساعات الحقول: الدمج صار تبادلياً', () {
    /// ساعات مرتّبة صراحةً — لا اعتماد على توقيت التنفيذ.
    String hlc(int ms, [String dev = 'devA']) => '$ms:0:$dev';

    Map<String, Object?> rowWith(
      Map<String, Object?> domain, {
      required String rowHlc,
      Map<String, String> fmeta = const {},
    }) =>
        {
          'id': 'r1',
          ...domain,
          if (fmeta.isNotEmpty) '_fmeta': fmeta,
          '_hlc': rowHlc,
          '_deleted': 0,
        };

    test('الحقل يُحسم بساعته لا بساعة الصف', () {
      // محلي: غيّر `notes` بساعة حديثة. بعيد: غيّر `amount` بساعة أحدث
      // على مستوى **الصف**. بلا ساعات الحقول يفوز البعيد بكل شيء فتضيع
      // الملاحظة؛ ومعها يفوز كلٌّ بحقله.
      final plan = planFieldMerge(
        entity: 'records',
        local: rowWith(
          {'amount': 100, 'notes': 'ملاحظة محلية'},
          rowHlc: hlc(1000),
          fmeta: {'notes': hlc(1000)},
        ),
        remote: rowWith(
          {'amount': 250, 'notes': 'قديمة'},
          rowHlc: hlc(2000, 'devB'),
          fmeta: {'amount': hlc(2000, 'devB')},
        ),
        shadow: {'amount': 100, 'notes': 'قديمة'},
        isNewer: defaultIsNewer,
        tick: (_) => hlc(3000),
        deviceId: 'devA',
      );

      expect(plan.status, 'merged');
      expect(plan.row!['amount'], 250, reason: 'م81: البعيد يفوز بحقله');
      expect(plan.row!['notes'], 'ملاحظة محلية',
          reason: 'م81: والمحلي يفوز بحقله — لا يبتلع أحدهما الآخر');
    });

    test('التبادلية: ترتيبا وصول مختلفان ⇒ الحالة نفسها', () {
      // العمليات: A غيّر notes، وB غيّر amount. نجرّب الترتيبين.
      final base = {'amount': 100, 'notes': 'أصل'};
      final aRow = rowWith({'amount': 100, 'notes': 'من A'},
          rowHlc: hlc(1000, 'A'), fmeta: {'notes': hlc(1000, 'A')});
      final bRow = rowWith({'amount': 500, 'notes': 'أصل'},
          rowHlc: hlc(1500, 'B'), fmeta: {'amount': hlc(1500, 'B')});

      // الترتيب الأول: المحلي A، والوارد B.
      final ab = planFieldMerge(
        entity: 'records', local: aRow, remote: bRow, shadow: base,
        isNewer: defaultIsNewer, tick: (_) => hlc(9000), deviceId: 'A',
      );
      // الترتيب الثاني: المحلي B، والوارد A.
      final ba = planFieldMerge(
        entity: 'records', local: bRow, remote: aRow, shadow: base,
        isNewer: defaultIsNewer, tick: (_) => hlc(9000), deviceId: 'B',
      );

      expect(ab.row!['amount'], ba.row!['amount'],
          reason: 'م81: **جوهر الإصلاح** — الترتيب لا يغيّر النتيجة');
      expect(ab.row!['notes'], ba.row!['notes']);
      expect(ab.row!['amount'], 500);
      expect(ab.row!['notes'], 'من A');
    });

    test('الخريطة تُحمَل مع الناتج فلا تُفقد الختمات عند أول مزج', () {
      final plan = planFieldMerge(
        entity: 'records',
        local: rowWith({'amount': 100, 'notes': 'م'},
            rowHlc: hlc(1000), fmeta: {'notes': hlc(1000)}),
        remote: rowWith({'amount': 250, 'notes': 'ق'},
            rowHlc: hlc(2000, 'B'), fmeta: {'amount': hlc(2000, 'B')}),
        shadow: {'amount': 100, 'notes': 'ق'},
        isNewer: defaultIsNewer, tick: (_) => hlc(3000), deviceId: 'A',
      );
      final meta = readRowFMeta(plan.row);
      expect(meta['notes'], hlc(1000));
      expect(meta['amount'], hlc(2000, 'B'),
          reason: 'م81: بلا الحمل يعود الصف لحسمٍ بساعة الصف');
    });

    test('التوافق الرجعي: صفّ بلا ساعات يسلك المسار القديم حرفياً', () {
      // لا `_fmeta` على أي جانب ⇒ leafDecision صفر ⇒ حسمٌ بساعة الصف.
      final plan = planFieldMerge(
        entity: 'records',
        local: rowWith({'amount': 100}, rowHlc: hlc(1000)),
        remote: rowWith({'amount': 250}, rowHlc: hlc(2000, 'B')),
        shadow: {'amount': 50},
        isNewer: defaultIsNewer, tick: (_) => hlc(3000), deviceId: 'A',
      );
      expect(plan.row!['amount'], 250,
          reason: 'الأحدث بساعة الصف يفوز — السلوك القديم بلا تغيير');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م81/ب — الختم عند الكتابة', () {
    test('الحقل المتغيّر وحده يُختَم — لا اختلاق ملكية', () {
      final prev = {'amount': 100, 'notes': 'أصل', 'service': 'حشو'};
      final next = {'amount': 250, 'notes': 'أصل', 'service': 'حشو'};
      final out = stampRowFields(prev, next, '5000:0:A');
      final meta = readRowFMeta(out);

      expect(meta.keys, contains('amount'));
      expect(meta.keys, isNot(contains('notes')),
          reason: 'م81: قيمةٌ لم تتغيّر لا تُختَم — وإلا فاز جهاز بحقل لم يمسّه');
      expect(meta.keys, isNot(contains('service')));
    });

    test('الحقول غير المدرَجة لا تُختَم — الحمولة لا تُضخَّم', () {
      final out = stampRowFields(
          {'remaining': 1}, {'remaining': 99, '_activityAt': 5}, '1:0:A');
      expect(readRowFMeta(out), isEmpty,
          reason: 'المشتقّات تُعاد حسابها بعد الدمج على كل حال');
    });

    test('بلا تغيّر ⇒ الصف يُعاد كما هو بلا حقل زائد', () {
      final same = {'amount': 100};
      expect(identical(stampRowFields({'amount': 100}, same, '1:0:A'), same),
          isTrue);
    });

    test('الختمات السابقة تُحفَظ ولا تُدهَس', () {
      var row = stampRowFields({'amount': 1}, {'amount': 2}, '1000:0:A');
      row = stampRowFields({'amount': 2, ...row}, {...row, 'notes': 'ج'},
          '2000:0:A');
      final meta = readRowFMeta(row);
      expect(meta['amount'], '1000:0:A', reason: 'الختمة الأقدم باقية');
      expect(meta['notes'], '2000:0:A');
    });

    test('منفذ الكتابة يختم فعلاً — التكامل لا الوحدة', () {
      final db = LocalDb.open(p.join(tmp.path, 'w.db'));
      addTearDown(db.close);
      final repos = Repositories(db);

      repos.records.upsertLocal(
          {'id': 'r1', 'name': 'سالم', 'amount': 100, 'service': 'حشو'});
      repos.records.upsertLocal(
          {'id': 'r1', 'name': 'سالم', 'amount': 250, 'service': 'حشو'});

      final meta = readRowFMeta(repos.records.getById('r1'));
      expect(meta.keys, contains('amount'),
          reason: 'م81: المبلغ تغيّر فخُتم');
      expect(meta['amount'], isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م81/ج — إظهار التعارضات الجوهرية', () {
    LocalDb boot() {
      final db = LocalDb.open(p.join(tmp.path, 'c.db'));
      addTearDown(db.close);
      return db;
    }

    void seedConflict(LocalDb db, String local, String remote) {
      db.execute(
        'INSERT INTO conflict_log (entity, entity_id, local_json, remote_json, '
        "resolved_to, created_at) VALUES ('records','r1',?,?,'remote',datetime('now'))",
        [local, remote],
      );
    }

    test('تعارض مالي يظهر مع الحقل الذي اختلف', () {
      final db = boot();
      seedConflict(db, '{"amount":500,"notes":"ن"}', '{"amount":300,"notes":"ن"}');

      final list = materialConflicts(db);
      expect(list, hasLength(1));
      expect(list.single.fields, ['amount']);
      expect(list.single.entityId, 'r1');
    });

    test('التعارض غير الجوهري لا يظهر — الضجيج يُبطل الميزة', () {
      final db = boot();
      // اختلاف في حقول مشتقّة/تقنية فقط.
      seedConflict(db, '{"amount":500,"_mod":1,"remaining":9}',
          '{"amount":500,"_mod":2,"remaining":7}');
      expect(materialConflicts(db), isEmpty,
          reason: 'م81: إشعارٌ عند كل تعارض يُدرَّب المستخدم على تجاهله');
    });

    test('الملاحظة السريرية جوهرية كالمال', () {
      final db = boot();
      seedConflict(db, '{"notes":"حساسية بنسلين"}', '{"notes":""}');
      expect(materialConflicts(db).single.fields, ['notes']);
    });

    test('التعليم مقروءاً يُخفيه ولا يحذف الطرف المهمَل', () {
      final db = boot();
      seedConflict(db, '{"amount":500}', '{"amount":300}');
      final before = materialConflicts(db);
      expect(before, hasLength(1));

      markConflictsSeen(db, [before.single.id]);
      expect(materialConflicts(db), isEmpty, reason: 'اختفى من الإشعارات');
      expect(db.query('SELECT * FROM conflict_log'), hasLength(1),
          reason: 'م81: الطرف المهمَل يبقى قابلاً للاسترجاع — لا حذف');
    });

    test('العدّاد يطابق القائمة', () {
      final db = boot();
      seedConflict(db, '{"amount":1}', '{"amount":2}');
      seedConflict(db, '{"notes":"أ"}', '{"notes":"ب"}');
      seedConflict(db, '{"_mod":1}', '{"_mod":2}'); // غير جوهري
      expect(materialConflictCount(db), 2);
    });

    test('الحمولة المشوّهة لا تُسقط شيئاً', () {
      final db = boot();
      seedConflict(db, 'ليس JSON', '{"amount":1}');
      expect(() => materialConflicts(db), returnsNormally);
      expect(materialConflicts(db), isEmpty);
    });
  });
}
