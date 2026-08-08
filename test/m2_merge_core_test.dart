/// اختبارات ثوابت نواة الدمج (م2أ) — كل عقد موثق في وحدات merge/* الأصلية
/// يتحول هنا إلى تأكيد قابل للتنفيذ:
///   • الدمج الثلاثي الحقلي (مشكلة رقم 2: تعديلان على حقلين مختلفين ينجوان معاً)
///   • مصفوفات الأقساط بالمعرف + شواهد الحذف المضادة للانبعاث
///   • إعادة اشتقاق المجاميع المالية بعد الدمج (لا ضياع لأي دفعة)
///   • دمج app.config البنيوي (عيادة جديدة + عملة جديدة تنجوان معاً)
///   • ضغط الشواهد الآمن بأفق الخادم
///   • مقارن الترتيب المقاوم لانحراف ساعة الجهاز
library;

import 'package:dental_clinic_flutter/data/sync/hlc_order.dart' hide SyncRow;
import 'package:dental_clinic_flutter/data/sync/merge/config_merge.dart';
import 'package:dental_clinic_flutter/data/sync/merge/field_merge.dart';
import 'package:dental_clinic_flutter/data/sync/merge/merge_engine.dart';
import 'package:dental_clinic_flutter/data/sync/merge/recompute.dart';
import 'package:dental_clinic_flutter/data/sync/merge/tombstones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // HLCs: t1 < t2 < t3 (device suffix breaks ties deterministically)
  const h1 = '1000:0:devA';
  const h2 = '2000:0:devB';
  const h3 = '3000:0:devA';

  group('mergeEngine — scalar 3-way', () {
    test('both sides equal → value; single-side change → that side wins', () {
      Map<String, Object?> m(Object? b, Object? l, Object? r,
              {String lh = h2, String rh = h1}) =>
          mergeRecordValues(
            base: b == null ? missing : {'x': b},
            local: {'x': l},
            remote: {'x': r},
            localHlc: lh,
            remoteHlc: rh,
          );

      expect(m('a', 'b', 'b')['x'], 'b'); // agreement
      expect(m('a', 'a', 'r')['x'], 'r'); // only remote changed
      expect(m('a', 'l', 'a')['x'], 'l'); // only local changed
      // both diverged → LWW by row HLC (remote newer here)
      expect(m('a', 'l', 'r', lh: h1, rh: h2)['x'], 'r');
      // both diverged, local newer → local
      expect(m('a', 'l', 'r', lh: h3, rh: h2)['x'], 'l');
    });

    test('tie prefers local (background pull never clobbers an equal clock)',
        () {
      final out = mergeRecordValues(
        local: {'x': 'l'},
        remote: {'x': 'r'},
        localHlc: h2,
        remoteHlc: h2,
      );
      expect(out['x'], 'l');
    });

    test('Problem #2: different fields edited on two devices BOTH survive', () {
      final base = {'name': 'أحمد', 'phone': '091', 'notes': ''};
      final local = {'name': 'أحمد الطيب', 'phone': '091', 'notes': ''};
      final remote = {'name': 'أحمد', 'phone': '092', 'notes': ''};
      final out = mergeRecordValues(
        base: base,
        local: local,
        remote: remote,
        localHlc: h2,
        remoteHlc: h3,
      );
      expect(out['name'], 'أحمد الطيب'); // local edit kept
      expect(out['phone'], '092'); // remote edit kept
    });
  });

  group('mergeEngine — set (clinics / services)', () {
    test('union with 3-way removal awareness + deterministic order', () {
      final out = mergeRecordValues(
        strategy: objectStrategy({'clinics': const MergeStrategy(kind: 'set')}),
        base: {
          'clinics': ['ع1', 'ع2']
        },
        local: {
          'clinics': ['ع1', 'ع2', 'ع3'] // local added ع3
        },
        remote: {
          'clinics': ['ع1'] // remote removed ع2
        },
        localHlc: h2,
        remoteHlc: h3,
      );
      final clinics = out['clinics'] as List;
      expect(clinics, containsAll(['ع1', 'ع3'])); // add survived
      expect(clinics, isNot(contains('ع2'))); // removal honored
    });
  });

  group('mergeEngine — arrayById (installments)', () {
    MergeStrategy debts() => objectStrategy(
        {'installments': arrayByIdStrategy(idKey: 'id')});

    test('two devices each record a payment → BOTH payments survive', () {
      final base = {
        'installments': [
          {'id': 'i1', 'amount': 100}
        ]
      };
      final local = {
        'installments': [
          {'id': 'i1', 'amount': 100},
          {'id': 'i2', 'amount': 50}, // paid on device A
        ]
      };
      final remote = {
        'installments': [
          {'id': 'i1', 'amount': 100},
          {'id': 'i3', 'amount': 75}, // paid on device B
        ]
      };
      final out = mergeRecordValues(
        strategy: debts(),
        base: base,
        local: local,
        remote: remote,
        localHlc: h2,
        remoteHlc: h3,
      );
      final ids = (out['installments'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(ids, {'i1', 'i2', 'i3'}); // no payment lost — the core promise
    });

    test('delete beats concurrent edit → durable canonical tombstone', () {
      final base = {
        'installments': [
          {'id': 'i1', 'amount': 100}
        ]
      };
      final local = {
        'installments': <Object?>[] // device A deleted i1 (physical removal)
      };
      final remote = {
        'installments': [
          {'id': 'i1', 'amount': 999} // device B edited i1 concurrently
        ]
      };
      final out = mergeRecordValues(
        strategy: debts(),
        base: base,
        local: local,
        remote: remote,
        localHlc: h2,
        remoteHlc: h3, // remote even NEWER — delete still wins
      );
      final items = out['installments'] as List;
      expect(items.length, 1);
      expect(items.single, {'id': 'i1', '_deleted': 1}); // canonical marker
      // and the user-visible view hides it:
      expect(activeItems(items), isEmpty);
    });

    test('re-add after delete cannot resurrect (stale replica safety)', () {
      final base = {
        'installments': [
          {'id': 'i1', 'amount': 100, '_deleted': 1} // already tombstoned
        ]
      };
      final local = base;
      final remote = {
        'installments': [
          {'id': 'i1', 'amount': 100} // stale replica still has it active
        ]
      };
      final out = mergeRecordValues(
        strategy: debts(),
        base: base,
        local: local,
        remote: remote,
        localHlc: h1,
        remoteHlc: h3,
      );
      final items = out['installments'] as List;
      expect((items.single as Map)['_deleted'], 1); // stays dead
    });
  });

  group('mergeEngine — atomic subtree (waTemplates)', () {
    test('opaque LWW with 3-way shortcuts', () {
      final strat = objectStrategy({'waTemplates': const MergeStrategy(kind: 'atomic')});
      // only local changed → local wins regardless of HLC
      final out = mergeRecordValues(
        strategy: strat,
        base: {
          'waTemplates': [{'t': 'a'}]
        },
        local: {
          'waTemplates': [{'t': 'edited'}]
        },
        remote: {
          'waTemplates': [{'t': 'a'}]
        },
        localHlc: h1,
        remoteHlc: h3,
      );
      expect((out['waTemplates'] as List).single, {'t': 'edited'});
    });
  });

  group('recompute — torn financial aggregates heal after merge', () {
    test('debts: paidAmount/remaining/status re-derived from installments', () {
      final merged = {
        'total': 300,
        'paidAmount': 100, // stale aggregate (one side only)
        'remaining': 200,
        'status': 'partial',
        'installments': [
          {'id': 'i1', 'amount': 100},
          {'id': 'i2', 'amount': 50},
          {'id': 'i3', 'amount': 75},
          {'id': 'dead', 'amount': 999, '_deleted': 1}, // excluded
        ],
      };
      final out = recomputeDebts(merged);
      expect(out['paidAmount'], 225); // 100+50+75 — no payment lost
      expect(out['remaining'], 75);
      expect(out['status'], 'partial');
    });

    test('debts: settle thresholds mirror the UI exactly (0.01)', () {
      final out = recomputeDebts({
        'total': 100,
        'installments': [
          {'id': 'i1', 'amount': 99.995}, // remaining 0.005 <= 0.01
        ],
      });
      expect(out['status'], 'paid');
      expect(out['remaining'], 0);
    });

    test('debts: idempotent — consistent row returns the SAME reference', () {
      final consistent = {
        'total': 100,
        'paidAmount': 40.0,
        'remaining': 60.0,
        'status': 'partial',
        'installments': [
          {'id': 'i1', 'amount': 40}
        ],
      };
      expect(identical(recomputeDebts(consistent), consistent), isTrue);
    });

    test('prosthetic debts: labPaid clamps to labValue', () {
      final out = recomputeDebts({
        'type': 'prosthetic',
        'total': 500,
        'labValue': 200,
        'installments': [
          {'id': 'i1', 'amount': 350}
        ],
      });
      expect(out['labPaid'], 200); // min(labValue, paid)
      expect(out['status'], 'partial');
    });

    test('prosthetics: shares derive from frozen snapshot; legacy untouched',
        () {
      final out = recomputeProsthetics({
        'total': 500,
        'labValue': 200,
        'doctorShare': 0, // torn
        'clinicShare': 0,
        '_rateSnapshot': {'doctorPct': 40},
      });
      expect(out['doctorShare'], 120); // (500-200)*0.4
      expect(out['clinicShare'], 180);

      final legacy = {'total': 500, 'labValue': 200, 'doctorShare': 7};
      expect(identical(recomputeProsthetics(legacy), legacy), isTrue);
    });
  });

  group('fieldMerge planner', () {
    SyncRow remoteRow(Map<String, Object?> domain,
            {String hlc = h2, int deleted = 0, int seq = 10}) =>
        {
          'id': 'r1',
          ...domain,
          '_hlc': hlc,
          '_deleted': deleted,
          '_origin': 'devB',
          'server_seq': seq,
        };

    test('no local row → inserted verbatim, clean, baseline = server domain',
        () {
      final plan = planFieldMerge(
        entity: 'records',
        local: null,
        remote: remoteRow({'service': 'حشو', 'amount': 100}),
      );
      expect(plan.status, 'inserted');
      expect(plan.needsPush, isFalse);
      expect(plan.row!['_dirty'], 0);
      expect(plan.row!['service'], 'حشو');
      expect((plan.baseline as Map)['amount'], 100);
    });

    test('remote tombstone with newer HLC wins; baseline cleared', () {
      final plan = planFieldMerge(
        entity: 'records',
        local: {'id': 'r1', 'service': 'x', '_hlc': h1, '_deleted': 0, '_dirty': 0},
        remote: remoteRow({'service': 'x'}, hlc: h2, deleted: 1),
      );
      expect(plan.status, 'updated');
      expect(plan.row!['_deleted'], 1);
      expect(plan.baseline, isNull); // clear the shadow
    });

    test('local dirty delete newer than remote → kept-local, shadow untouched',
        () {
      final plan = planFieldMerge(
        entity: 'records',
        local: {'id': 'r1', 'service': 'x', '_hlc': h3, '_deleted': 1, '_dirty': 1},
        remote: remoteRow({'service': 'y'}, hlc: h2),
      );
      expect(plan.status, 'kept-local');
      expect(plan.row, isNull);
      expect(identical(plan.baseline, missing), isTrue); // leave untouched
    });

    test('remote-only change → accept server (updated), no push', () {
      final plan = planFieldMerge(
        entity: 'records',
        shadow: {'id': 'r1', 'service': 'حشو', 'amount': 100},
        local: {
          'id': 'r1', 'service': 'حشو', 'amount': 100,
          '_hlc': h1, '_deleted': 0, '_dirty': 0,
        },
        remote: remoteRow({'id': 'r1', 'service': 'حشو', 'amount': 150}, hlc: h2),
      );
      expect(plan.status, 'updated');
      expect(plan.row!['amount'], 150);
      expect(plan.needsPush, isFalse);
    });

    test('genuine blend → merged row, fresh newer HLC, dirty + needsPush', () {
      var ticked = 0;
      final plan = planFieldMerge(
        entity: 'records',
        shadow: {'id': 'r1', 'service': 'حشو', 'amount': 100, 'notes': ''},
        local: {
          'id': 'r1', 'service': 'حشو', 'amount': 100, 'notes': 'ملاحظة',
          '_hlc': h2, '_deleted': 0, '_dirty': 1,
        },
        remote: remoteRow(
            {'id': 'r1', 'service': 'حشو', 'amount': 150, 'notes': ''},
            hlc: h3),
        tick: (dev) {
          ticked++;
          return '9000:0:$dev';
        },
        deviceId: 'devA',
      );
      expect(plan.status, 'merged');
      expect(plan.needsPush, isTrue);
      expect(ticked, 1);
      expect(plan.row!['amount'], 150); // remote's edit
      expect(plan.row!['notes'], 'ملاحظة'); // local's edit — both survive
      expect(plan.row!['_dirty'], 1);
      expect(plan.row!['_hlc'], '9000:0:devA');
      expect(plan.row!['server_seq'], 10);
    });

    test('debts blend triggers recompute so aggregates match installments', () {
      final shadow = {
        'id': 'd1', 'total': 300, 'paidAmount': 100, 'remaining': 200,
        'status': 'partial',
        'installments': [
          {'id': 'i1', 'amount': 100}
        ],
      };
      final local = {
        ...shadow,
        'installments': [
          {'id': 'i1', 'amount': 100},
          {'id': 'i2', 'amount': 50},
        ],
        'paidAmount': 150, 'remaining': 150,
        '_hlc': h2, '_deleted': 0, '_dirty': 1,
      };
      final remote = {
        'id': 'd1', 'total': 300,
        'installments': [
          {'id': 'i1', 'amount': 100},
          {'id': 'i3', 'amount': 75},
        ],
        'paidAmount': 175, 'remaining': 125, 'status': 'partial',
        '_hlc': h3, '_deleted': 0, '_origin': 'devB', 'server_seq': 11,
      };
      final plan = planFieldMerge(
        entity: 'debts',
        shadow: shadow,
        local: local,
        remote: remote,
        tick: (d) => '9000:0:devA',
        deviceId: 'devA',
      );
      expect(plan.status, 'merged');
      final row = plan.row!;
      final ids =
          (row['installments'] as List).map((e) => (e as Map)['id']).toSet();
      expect(ids, {'i1', 'i2', 'i3'});
      expect(row['paidAmount'], 225); // recomputed — NOT either stale aggregate
      expect(row['remaining'], 75);
      expect(row['status'], 'partial');
    });

    test('legacyDecision mirrors the old row-LWW for verify/dual-run', () {
      final res = legacyDecision(
        {'id': 'r1', 'a': 1, '_hlc': h3, '_dirty': 1},
        {'id': 'r1', 'a': 2, '_hlc': h2},
      );
      expect(res.status, 'kept-local');
      expect(res.domain['a'], 1);
    });
  });

  group('configMerge — app.config structural convergence', () {
    test('device A adds a clinic while device B changes currency → both kept',
        () {
      final base = {
        'clinics': ['ع1'],
        'currency': 'د.ل',
      };
      final local = {
        'clinics': ['ع1', 'ع2'], // A added a clinic
        'currency': 'د.ل',
      };
      final remote = {
        'clinics': ['ع1'],
        'currency': 'USD', // B changed the currency
      };
      final plan = planConfigMerge(
        local: local,
        remote: remote,
        base: base,
        localHlc: h2,
        remoteHlc: h3,
        tick: (d) => '9000:0:devA',
        deviceId: 'devA',
      );
      expect(plan.status, 'merged');
      expect(plan.needsPush, isTrue);
      expect(plan.hlc, '9000:0:devA');
      expect(plan.value['currency'], 'USD');
      expect(plan.value['clinics'], containsAll(['ع1', 'ع2']));
    });

    test('remote-only change → updated; local-only → kept-local', () {
      final base = {'currency': 'د.ل'};
      final acceptServer = planConfigMerge(
        local: base,
        remote: {'currency': 'USD'},
        base: base,
        localHlc: h1,
        remoteHlc: h2,
      );
      expect(acceptServer.status, 'updated');
      expect(acceptServer.value['currency'], 'USD');

      final keepLocal = planConfigMerge(
        local: {'currency': 'EUR'},
        remote: base,
        base: base,
        localHlc: h2,
        remoteHlc: h1,
      );
      expect(keepLocal.status, 'kept-local');
      expect(keepLocal.value['currency'], 'EUR');
      expect(keepLocal.baseline['currency'], 'د.ل'); // shadow advances
    });

    test('decodeConfigValue tolerates raw JSON strings and garbage', () {
      expect(decodeConfigValue('{"a":1}'), {'a': 1});
      expect(decodeConfigValue('not json'), isEmpty);
      expect(decodeConfigValue(null), isEmpty);
    });
  });

  group('tombstone lifecycle — stamping + safe compaction', () {
    final domain = {
      'installments': [
        {'id': 'live', 'amount': 10},
        {'id': 'dead1', '_deleted': 1}, // unstamped
        {'id': 'dead2', '_deleted': 1, '_seq': 5},
        {'id': 'dead3', '_deleted': 1, '_seq': 50},
      ],
    };

    test('stampTombstoneSeqs stamps only unstamped markers (idempotent)', () {
      final stamped = stampTombstoneSeqs('debts', domain, 42) as Map;
      final items = (stamped['installments'] as List).cast<Map>();
      Map byId(String id) => items.firstWhere((e) => e['id'] == id);
      expect(byId('dead1')['_seq'], 42); // newly stamped
      expect(byId('dead2')['_seq'], 5); // never overwritten
      expect(byId('live').containsKey('_seq'), isFalse); // active untouched
    });

    test('compaction prunes ONLY stamped tombstones at/below the horizon', () {
      final compacted = compactRowDomain('debts', domain, 10) as Map;
      final ids = (compacted['installments'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(ids, {'live', 'dead1', 'dead3'}); // dead2 (seq 5 ≤ 10) pruned
      // dead1 unstamped (∞) kept; dead3 seq 50 > 10 kept — fail-safe.
    });

    test('horizon 0 → SAME reference, nothing pruned (server-less fail-safe)',
        () {
      expect(identical(compactRowDomain('debts', domain, 0), domain), isTrue);
    });
  });

  group('hlcOrder — clock-skew-proof read ordering', () {
    test('a skewed-forward _mod can no longer beat a newer HLC edit', () {
      final genuinelyNewer = {
        '_hlc': '2000:0:devA',
        '_mod': 2000, // honest clock
      };
      final skewed = {
        '_hlc': '1000:0:devB',
        '_mod': 99999999, // wall clock years ahead
      };
      expect(compareRows(genuinelyNewer, skewed), greaterThan(0));
      expect(shouldReplace(genuinelyNewer, skewed), isTrue);
      expect(shouldReplace(skewed, genuinelyNewer), isFalse);
    });

    test('legacy rows fall back to _mod / updated_at millis', () {
      expect(
        compareRows({'_mod': 2000}, {'_mod': 1000}),
        greaterThan(0),
      );
      expect(
        compareRows(
          {'updated_at': '2026-07-26T10:00:00.000Z'},
          {'updated_at': '2026-07-25T10:00:00.000Z'},
        ),
        greaterThan(0),
      );
    });

    test('equal millis: the HLC-carrying row wins (stable tiebreak)', () {
      expect(
        compareRows({'_hlc': '1000:0:d', '_mod': 999}, {'_mod': 1000}),
        greaterThan(0),
      );
    });

    test('shouldReplace keeps >= semantics (later-seen equal row wins)', () {
      final a = {'_hlc': '1000:0:d'};
      expect(shouldReplace(a, {'_hlc': '1000:0:d'}), isTrue);
      expect(shouldReplace(a, null), isTrue);
    });
  });
}
