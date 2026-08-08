/// اختبارات م25 — خدمة الشبكة الموحدة وبوابة المحرك (توأم network.service):
///   • «متصل» = وصلة قائمة **و**وصول مؤكد بالفاحص — أيهما سقط ⇒ غير متصل.
///   • الفحص دوري كل pingInterval ما دامت الوصلة قائمة، وانقطاع الوصلة
///     حاسم فوراً بلا فحص.
///   • محرك المزامنة أوفلاين يعيد حالة offline بلا أي نداء شبكة.
library;

import 'dart:async';
import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/data/net/network_status.dart';
import 'package:dental_clinic_flutter/data/sync/fake_server.dart';
import 'package:dental_clinic_flutter/data/sync/transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ناقل جاسوس: يعدّ النداءات ليثبت أن الأوفلاين لا يلمس الشبكة.
class SpyTransport implements SyncTransport {
  final inner = FakeSyncServer();
  int calls = 0;

  @override
  Future<List<ApplyAck>> applyChanges(List<WireOp> ops) {
    calls++;
    return inner.applyChanges(ops);
  }

  @override
  Future<PullPage> pullChanges({
    required int lower,
    int? pageTxid,
    required int pageSeq,
    int? upto,
    required int limit,
  }) {
    calls++;
    return inner.pullChanges(
        lower: lower,
        pageTxid: pageTxid,
        pageSeq: pageSeq,
        upto: upto,
        limit: limit);
  }
}

void main() {
  group('الوحدات — NetworkStatus', () {
    test('وصلة بلا وصول = غير متصل؛ الفحص الدوري يقلبها عند عودة الخادم',
        () {
      fakeAsync((async) {
        final link = StreamController<bool>(sync: true);
        var reachable = false;
        var probes = 0;
        final events = <bool>[];
        final net = NetworkStatus(
          linkStream: link.stream,
          probe: () async {
            probes++;
            return reachable;
          },
          pingInterval: const Duration(seconds: 15),
        );
        net.listeners.add(events.add);
        net.start();
        async.elapse(const Duration(milliseconds: 10));
        expect(net.online, isFalse, reason: 'الفاحص فاشل ⇒ غير متصل');

        // الخادم عاد — الفحص الدوري التالي يؤكد الوصول.
        reachable = true;
        async.elapse(const Duration(seconds: 15));
        expect(net.online, isTrue);
        expect(events.last, isTrue);
        expect(probes, greaterThanOrEqualTo(2));
        net.dispose();
      });
    });

    test('انقطاع الوصلة حاسم فوراً ويوقف الفحص؛ عودتها تعيد فحصاً فورياً',
        () {
      fakeAsync((async) {
        final link = StreamController<bool>(sync: true);
        var probes = 0;
        final net = NetworkStatus(
          linkStream: link.stream,
          probe: () async {
            probes++;
            return true;
          },
          pingInterval: const Duration(seconds: 15),
        );
        net.start();
        async.elapse(const Duration(milliseconds: 10));
        expect(net.online, isTrue);

        link.add(false); // الوصلة سقطت
        async.elapse(const Duration(milliseconds: 10));
        expect(net.online, isFalse, reason: 'حاسم بلا فحص');
        final probesAtDrop = probes;
        async.elapse(const Duration(minutes: 2));
        expect(probes, probesAtDrop, reason: 'لا فحص دوري بلا وصلة');

        link.add(true); // عادت
        async.elapse(const Duration(milliseconds: 10));
        expect(net.online, isTrue);
        expect(probes, probesAtDrop + 1, reason: 'فحص فوري عند العودة');
        net.dispose();
      });
    });

    test('المستمعون يُنادَون عند التغيّر فقط (لا وميض عبثي)', () {
      fakeAsync((async) {
        final link = StreamController<bool>(sync: true);
        final events = <bool>[];
        final net = NetworkStatus(
          linkStream: link.stream,
          probe: () async => true,
          pingInterval: const Duration(seconds: 15),
        );
        net.listeners.add(events.add);
        net.start();
        async.elapse(const Duration(seconds: 46)); // فحص أولي + 3 دورية
        expect(events, [true], reason: 'الحالة لم تتغير ⇒ نداء واحد');
        net.dispose();
      });
    });
  });

  group('التكامل — بوابة المحرك والهيدر', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('m25_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('أوفلاين: syncNow يعيد offline بلا أي نداء شبكة؛ والعودة تستأنف',
        () async {
      final spy = SpyTransport();
      final c = ProviderContainer(overrides: [
        dbDirProvider.overrideWithValue(tmp.path),
        transportProvider.overrideWithValue(spy),
      ]);
      addTearDown(c.dispose);

      c.read(onlineProvider.notifier).state = false;
      final engine = c.read(syncEngineProvider);
      final r = await engine.syncNow();
      expect(r.status, 'offline');
      expect(spy.calls, 0, reason: 'أوفلاين ⇒ لا يلمس الناقل إطلاقاً');

      c.read(onlineProvider.notifier).state = true;
      final r2 = await engine.syncNow();
      expect(r2.ok, isTrue);
      expect(spy.calls, greaterThan(0));
    });
  });
}
