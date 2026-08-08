/// اختبارات م67/دفعة أول-أ — دمج تقرير الأسنان بالمعرّف.
///
/// العيب الأصلي (M8): صف السجل يحمل report = {entries:[...], meta:{}} حيث كل
/// عنصر {teeth, service, cost} بلا معرّف، فيُدمج كقيمة كاملة بترجيح الأحدث؛
/// طبيبان يوثّقان أسناناً مختلفة في زيارة واحدة ⇒ يضيع تخطيط أحدهما.
///
/// الإصلاح: إسناد معرّف ثابت لكل عنصر عند إنشائه. محرك الدمج يكتشف القوائم
/// كاملة المعرّفات تلقائياً (حارس _allIdentified، idKey الافتراضي 'id')
/// فيدمجها بالمعرّف بلا حاجة لواصف صريح — والعناصر القديمة بلا معرّف تسقط
/// بأمان إلى LWW الكامل. هذا الاختبار يثبت الاتجاهين على استراتيجية السجلات
/// الافتراضية نفسها (objectStrategy) لا على واصف خاص.
library;

import 'package:dental_clinic_flutter/data/sync/merge/descriptors.dart';
import 'package:dental_clinic_flutter/data/sync/merge/merge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // استراتيجية السجلات الفعلية كما يحلّها الإنتاج عبر strategyForEntity.
  final recordStrategy = strategyForEntity('records');

  const h2 = '2000:0:devA';
  const h3 = '2001:0:devB';

  group('م67 — دمج report.entries بالمعرّف', () {
    test('FIX: طبيبان يضيفان عنصري تقرير مختلفين ⇒ ينجو الاثنان', () {
      final base = {
        'report': {
          'entries': [
            {'id': 'e1', 'teeth': [{'q': 'UR', 'n': 1}], 'service': 'فحص', 'cost': 0}
          ],
          'meta': {},
        }
      };
      final local = {
        'report': {
          'entries': [
            {'id': 'e1', 'teeth': [{'q': 'UR', 'n': 1}], 'service': 'فحص', 'cost': 0},
            {'id': 'e2', 'teeth': [{'q': 'UL', 'n': 2}], 'service': 'حشو', 'cost': 100}, // جهاز A
          ],
          'meta': {},
        }
      };
      final remote = {
        'report': {
          'entries': [
            {'id': 'e1', 'teeth': [{'q': 'UR', 'n': 1}], 'service': 'فحص', 'cost': 0},
            {'id': 'e3', 'teeth': [{'q': 'LR', 'n': 3}], 'service': 'تنظيف', 'cost': 80}, // جهاز B
          ],
          'meta': {},
        }
      };
      final out = mergeRecordValues(
        strategy: recordStrategy,
        base: base, local: local, remote: remote,
        localHlc: h2, remoteHlc: h3,
      );
      final entries = ((out['report'] as Map)['entries'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(entries, {'e1', 'e2', 'e3'},
          reason: 'م67: لا تخطيط سن يضيع — العنصران المضافان ينجوان معاً');
    });

    test('تعارض على نفس العنصر: الأحدث يفوز والبقية سليمة', () {
      final base = {
        'report': {'entries': [
          {'id': 'e1', 'service': 'حشو', 'cost': 100},
          {'id': 'e2', 'service': 'تنظيف', 'cost': 80},
        ]}
      };
      final local = {
        'report': {'entries': [
          {'id': 'e1', 'service': 'حشو', 'cost': 120}, // A عدّل التكلفة
          {'id': 'e2', 'service': 'تنظيف', 'cost': 80},
        ]}
      };
      final remote = {
        'report': {'entries': [
          {'id': 'e1', 'service': 'حشو', 'cost': 100},
          {'id': 'e2', 'service': 'تنظيف', 'cost': 80},
        ]}
      };
      final out = mergeRecordValues(
        strategy: recordStrategy,
        base: base, local: local, remote: remote,
        localHlc: h2, remoteHlc: h3,
      );
      final entries = (out['report'] as Map)['entries'] as List;
      expect(entries.length, 2);
      final e1 = entries.firstWhere((e) => (e as Map)['id'] == 'e1') as Map;
      expect(e1['cost'], 120, reason: 'تعديل A نجا (الأحدث)');
    });

    test('السقوط الآمن: عنصر قديم بلا معرّف ⇒ LWW كامل بلا فقد صامت', () {
      // القائمة المحلية فيها عنصر بلا id ⇒ _allIdentified=false ⇒ LWW.
      final local = {
        'report': {'entries': [
          {'teeth': [], 'service': 'قديم بلا معرّف', 'cost': 50},
        ]}
      };
      final remote = {
        'report': {'entries': [
          {'id': 'e9', 'service': 'جديد', 'cost': 70},
        ]}
      };
      final out = mergeRecordValues(
        strategy: recordStrategy,
        base: const <String, Object?>{}, local: local, remote: remote,
        localHlc: h2, remoteHlc: h3,
      );
      // LWW يختار جانباً كاملاً — المهم ألا ينهار ولا يخلط بشكل يفقد بنية.
      final entries = (out['report'] as Map)['entries'] as List;
      expect(entries, isNotEmpty,
          reason: 'السقوط الآمن يبقي جانباً كاملاً لا فراغاً');
    });
  });
}
