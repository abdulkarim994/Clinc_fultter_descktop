/// اختبارات م79 — المرحلة الثانية: الخصوصية والامتثال.
///
///  محوران: **سجلّ تدقيق يجيب «من فعل ماذا»**، و**قفل خمول لا يُضيع عملاً**.
///  ولكل منهما اختبارٌ نظير يثبت أن الحارس لم يتحوّل إلى عائق — فقفلٌ يفقد
///  إدخال الطبيب، أو سجلٌّ يُسقط شاشة المريض، يُطفَأ في أسبوع.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/db/local_db.dart';
import 'package:dental_clinic_flutter/data/sync/audit_push.dart';
import 'package:dental_clinic_flutter/features/auth/idle_lock.dart';
import 'package:dental_clinic_flutter/features/patients/audit_trail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// ناقل تدقيق مزيّف — يسجّل ما وصله ويحاكي الفشل والتكرار.
class FakeAuditTransport implements AuditTransport {
  final batches = <List<Map<String, Object?>>>[];
  final seenIds = <String>{};
  bool fail = false;

  @override
  Future<int> pushAudit(List<Map<String, Object?>> events) async {
    if (fail) throw Exception('شبكة معطّلة');
    batches.add(List.of(events));
    // محاكاة `on conflict do nothing`: المكرّر لا يُدرَج.
    var inserted = 0;
    for (final e in events) {
      if (seenIds.add('${e['id']}')) inserted++;
    }
    return inserted;
  }
}

void main() {
  late Directory tmp;
  late LocalDb db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m79_');
    db = LocalDb.open(p.join(tmp.path, 'dental_clinic_offline.db'));
    db.setOwnerUid('user-A');
  });
  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م79/أ — سجلّ التدقيق يجيب «من فعل ماذا»', () {
    test('كل قيد يحمل الفاعل والجهاز — وهو ما كان غائباً كلياً', () {
      recordAudit(db,
          action: AuditAction.viewPatient,
          entity: 'patients',
          entityId: 'سالم');

      final rows = readAudit(db);
      expect(rows, hasLength(1));
      expect(rows.first['actor_uid'], 'user-A', reason: 'من');
      expect('${rows.first['device_id']}', isNotEmpty, reason: 'من أي جهاز');
      expect(rows.first['action'], AuditAction.viewPatient, reason: 'ماذا');
      expect(rows.first['entity_id'], 'سالم', reason: 'بأي سجلّ');
      expect((rows.first['at'] as num).toInt(), greaterThan(0), reason: 'متى');
    });

    test('الاطّلاع يُسجَّل — أكثر ما يُسأل عنه في تحقيق تسريب', () {
      for (final a in kLoggedReadActions) {
        recordAudit(db, action: a, entity: 'x', entityId: 'k');
      }
      final actions = {for (final r in readAudit(db)) r['action']};
      expect(actions, containsAll(kLoggedReadActions));
      expect(actions, contains(AuditAction.viewPatient));
      expect(actions, contains(AuditAction.viewXray));
      expect(actions, contains(AuditAction.exportPdf));
    });

    test('معرّف السجلّ يُحفظ صريحاً — إخفاؤه يُفرغ الميزة', () {
      // الاستثناء المقصود من قاعدة «لا بيانات مرضى في السجلّات»: سجلٌّ
      // يقول «اطّلع أحدٌ على مريضٍ ما» بلا تحديد عديم القيمة.
      recordAudit(db,
          action: AuditAction.viewPatient,
          entity: 'patients',
          entityId: 'مريم علي');
      expect(readAudit(db).first['entity_id'], 'مريم علي');
    });

    test('التفصيل الحرّ يُحجب — القاعدة تسري على ما لا يخدم التدقيق', () {
      recordAudit(db,
          action: AuditAction.editRecord,
          entity: 'records',
          entityId: 'r1',
          detail: {
            'note': 'المريض خالد يشكو ألماً',
            'count': 3,
            'flag': true,
          });

      final d = jsonDecode('${readAudit(db).first['detail']}') as Map;
      expect('${d['note']}', isNot(contains('خالد')),
          reason: 'النص الحرّ يُحجب');
      expect(d['count'], 3, reason: 'الأعداد تمرّ — مفيدة وغير شخصية');
      expect(d['flag'], true);
    });

    test('لا يرمي أبداً — سجلٌّ يُسقط شاشة المريض أسوأ من سجلٍّ ناقص', () {
      db.execute('DROP TABLE audit_events');
      expect(() => recordAudit(db, action: AuditAction.viewPatient),
          returnsNormally);
    });

    test('الترشيح بالكيان والمعرّف يعمل — سجلٌّ لا يُستعلَم لا قيمة له', () {
      recordAudit(db, action: 'a', entity: 'patients', entityId: 'p1');
      recordAudit(db, action: 'b', entity: 'patients', entityId: 'p2');
      recordAudit(db, action: 'c', entity: 'xrays', entityId: 'x1');

      expect(readAudit(db, entity: 'patients'), hasLength(2));
      expect(readAudit(db, entity: 'patients', entityId: 'p1'), hasLength(1));
      expect(readAudit(db, entity: 'xrays'), hasLength(1));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م79/ب — دفع السجلّ إلى الخادم', () {
    test('الدفع يرسل غير المدفوع ثم يعلّمه — ولا يحذفه', () async {
      for (var i = 0; i < 3; i++) {
        recordAudit(db, action: 'a$i', entity: 'e', entityId: '$i');
      }
      final t = FakeAuditTransport();
      final pusher = AuditPusher(db: db, transportOf: () => t);

      expect(unpushedAuditCount(db), 3);
      expect(await pusher.pushOnce(), 3);
      expect(unpushedAuditCount(db), 0);
      expect(readAudit(db), hasLength(3),
          reason: 'م79: القيد يبقى محلياً بعد دفعه — لا يُمحى');
    });

    test('الدفع عديم الأثر: إعادة الإرسال لا تُكرّر القيود', () async {
      recordAudit(db, action: 'a', entity: 'e', entityId: '1');
      final t = FakeAuditTransport();
      final pusher = AuditPusher(db: db, transportOf: () => t);

      expect(await pusher.pushOnce(), 1);
      // محاكاة انقطاع بين الإدراج والإقرار: أُعيد العلم إلى 0 يدوياً.
      db.execute('UPDATE audit_events SET pushed = 0');
      expect(await pusher.pushOnce(), 0,
          reason: 'الخادم يردّ صفراً — موجودة أصلاً لا مرفوضة');
      expect(t.seenIds, hasLength(1), reason: 'لم يتكرّر القيد');
      expect(unpushedAuditCount(db), 0, reason: 'وعُلّم مدفوعاً رغم الصفر');
    });

    test('فشل الشبكة يُبقي القيود غير مدفوعة للمحاولة التالية', () async {
      recordAudit(db, action: 'a', entity: 'e', entityId: '1');
      final t = FakeAuditTransport()..fail = true;
      final pusher = AuditPusher(db: db, transportOf: () => t);

      await expectLater(pusher.pushOnce(), throwsA(isA<Exception>()));
      expect(unpushedAuditCount(db), 1, reason: 'لم تُفقد ولم تُعلَّم');

      t.fail = false;
      expect(await pusher.pushOnce(), 1, reason: 'نجحت في المحاولة التالية');
    });

    test('الوضع المحلي: لا ناقل ⇒ تتراكم محلياً بلا فقد', () async {
      recordAudit(db, action: 'a', entity: 'e', entityId: '1');
      final pusher = AuditPusher(db: db, transportOf: () => null);

      expect(await pusher.pushOnce(), 0);
      expect(unpushedAuditCount(db), 1);
      expect(readAudit(db), hasLength(1),
          reason: 'السجلّ كامل محلياً — ينقصه حارس الخادم فقط');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م79/ج — قفل الخمول', () {
    test('المُتحقِّق يُخزَّن مغلَّفاً لا نصّاً صريحاً', () {
      storeLockVerifier(db, 'كلمة-سرّي-القوية');

      expect(hasLockVerifier(db), isTrue);
      final raw = db.queryFirst(
          "SELECT value FROM sync_meta WHERE key = 'auth.lock_verifier'");
      final stored = '${raw?['value']}';
      expect(stored, isNot(contains('كلمة-سرّي-القوية')),
          reason: 'م79: كلمة المرور لا تُخزَّن صريحة');
      expect(stored, startsWith('pbkdf2\$sha256\$'),
          reason: 'مغلّف PBKDF2 بملح — نفس صيغة الحسابات المحلية');
    });

    test('الفتح يقبل الصحيحة ويرفض غيرها — ويعمل بلا شبكة', () {
      storeLockVerifier(db, 'صحيحة');

      expect(verifyLock(db, 'صحيحة'), isTrue);
      expect(verifyLock(db, 'خاطئة'), isFalse);
      expect(verifyLock(db, ''), isFalse);
    });

    test('بلا مُتحقِّق مخزَّن لا يُفتح القفل بأي كلمة — لا باب تجاوز', () {
      expect(hasLockVerifier(db), isFalse);
      expect(verifyLock(db, 'أي-شيء'), isFalse);
      expect(verifyLock(db, ''), isFalse);
    });

    test('المسح يُبطل الفتح', () {
      storeLockVerifier(db, 'س');
      expect(verifyLock(db, 'س'), isTrue);
      clearLockVerifier(db);
      expect(hasLockVerifier(db), isFalse);
      expect(verifyLock(db, 'س'), isFalse);
    });

    test('حالة القفل تبدأ مفتوحة والمهلة الافتراضية معقولة', () {
      final c = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      addTearDown(c.dispose);

      expect(c.read(lockedProvider), isFalse, reason: 'لا يبدأ مقفلاً');
      final t = c.read(idleTimeoutProvider);
      expect(t, kIdleTimeout);
      expect(t.inMinutes, greaterThanOrEqualTo(5),
          reason: 'أقصر من ذلك يقاطع الطبيب أثناء الفحص');
      expect(t.inMinutes, lessThanOrEqualTo(15),
          reason: 'أطول من ذلك لا يحمي لوحاً متروكاً');
    });
  });
}
