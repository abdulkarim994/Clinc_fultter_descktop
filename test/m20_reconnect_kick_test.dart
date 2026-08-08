/// اختبارات م20 — محفّز إعادة الاتصال (توأم onNetworkChange بتوهين ثانيتين):
/// عودة الشبكة تركل مرة واحدة بعد استقرار المهلة؛ التذبذب يجدد المهلة؛
/// التكرار على نفس الحالة يُهمل؛ الانقطاع يلغي الركلة المعلقة.
library;

import 'package:dental_clinic_flutter/data/net/reconnect_kick.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('عودة الاتصال تركل مرة واحدة بعد مهلة التوهين', () {
    fakeAsync((async) {
      var kicks = 0;
      final rk = ReconnectKick(() => kicks++, debounceMs: 2000);
      rk.onEvent(false); // إقلاع أوفلاين
      rk.onEvent(true); // عاد الاتصال
      async.elapse(const Duration(milliseconds: 1999));
      expect(kicks, 0); // المهلة لم تستقر بعد
      async.elapse(const Duration(milliseconds: 1));
      expect(kicks, 1);
      // تكرار «متصل» لا يركل ثانية.
      rk.onEvent(true);
      async.elapse(const Duration(seconds: 5));
      expect(kicks, 1);
      rk.dispose();
    });
  });

  test('التذبذب يجدد المهلة والانقطاع يلغي الركلة المعلقة', () {
    fakeAsync((async) {
      var kicks = 0;
      final rk = ReconnectKick(() => kicks++, debounceMs: 2000);
      rk.onEvent(true);
      async.elapse(const Duration(milliseconds: 1500));
      rk.onEvent(false); // انقطع قبل استقرار المهلة — يلغي
      async.elapse(const Duration(seconds: 5));
      expect(kicks, 0);
      rk.onEvent(true); // عاد ثم استقر
      async.elapse(const Duration(milliseconds: 2000));
      expect(kicks, 1);
      rk.dispose();
    });
  });

  test('dispose يلغي أي ركلة معلقة', () {
    fakeAsync((async) {
      var kicks = 0;
      final rk = ReconnectKick(() => kicks++, debounceMs: 2000);
      rk.onEvent(true);
      rk.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(kicks, 0);
    });
  });
}
