/// اختبارات م77/ب — حدّ الأخطاء العام وسجلّه المحلي.
///
///  البند الأخطر هنا ليس أن السجلّ يعمل، بل **أنه لا يسرّب**. المشروع
///  يحافظ على صفر تسريب لبيانات المرضى في السجلّات (تحقّقنا: صفر `print`
///  في 39 ألف سطر)، وإدخال قناة كتابة جديدة يجب ألّا يكسر ذلك. لذلك
///  معظم ما يلي اختبارات حجب لا اختبارات وظيفة.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/core/error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('m77b_');
    errorsThisRun = 0;
    lastErrorType = null;
  });
  tearDown(() {
    disposeErrorLog();
    tmp.deleteSync(recursive: true);
  });

  String logText() {
    final f = errorLogFile(tmp.path)!;
    return f.existsSync() ? f.readAsStringSync() : '';
  }

  // ──────────────────────────────────────────────────────────────────────
  group('م77 — الحجب: لا بيانات مرضى في السجلّ', () {
    test('الاسم العربي في رسالة الاستثناء يُحجب', () {
      initErrorLog(tmp.path);
      recordError(
          ArgumentError('تعذّر حفظ سجل المريض مريم علي أحمد'), StackTrace.current,
          context: 'test');

      final t = logText();
      expect(t, isNot(contains('مريم')));
      expect(t, isNot(contains('علي')));
      expect(t, contains('<text>'), reason: 'حُجب المقطع العربي');
      expect(t, contains('ArgumentError'),
          reason: 'النوع التقني يبقى — وهو المفيد تشخيصياً');
    });

    test('الهاتف والمعرّفات الطويلة تُحجب', () {
      initErrorLog(tmp.path);
      recordError(
          StateError('failed for patient_id=0912345678 row 1785433518229'),
          null);

      final t = logText();
      expect(t, isNot(contains('0912345678')));
      expect(t, isNot(contains('1785433518229')));
      expect(t, contains('<num>'));
    });

    test('البريد يُحجب', () {
      initErrorLog(tmp.path);
      recordError(Exception('auth failed for dr.salem@clinic.ly'), null);
      final t = logText();
      expect(t, isNot(contains('dr.salem@clinic.ly')));
      expect(t, contains('<email>'));
    });

    test('المصطلح التقني الإنجليزي ينجو — الحجب ليس مسحاً شاملاً', () {
      initErrorLog(tmp.path);
      recordError(StateError('database is locked'), null,
          context: 'add_record:_save');
      final t = logText();
      expect(t, contains('database is locked'),
          reason: 'لولا ذلك لصار السجلّ عديم القيمة');
      expect(t, contains('add_record:_save'));
    });

    test('redactPhi دالة نقية قابلة للفحص المباشر', () {
      expect(redactPhi('SqliteException: no such column: خالد'),
          isNot(contains('خالد')));
      expect(redactPhi('SqliteException: no such column'),
          'SqliteException: no such column');
      expect(redactPhi(''), '');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('م77 — متانة السجلّ', () {
    test('لا يرمي أبداً حتى بلا تهيئة — سجلٌّ يُسقط التطبيق أسوأ من لا سجلّ',
        () {
      disposeErrorLog();
      expect(() => recordError(Exception('boom'), StackTrace.current),
          returnsNormally);
      expect(errorsThisRun, 1, reason: 'العدّ يعمل حتى بلا وجهة كتابة');
      // `Exception('x').runtimeType` هو `_Exception` لا `Exception`:
      // المُنشئ يُرجع نسخةً من صنف تنفيذ خاص. المطابقة الحرفية على
      // «Exception» كانت خطأً في التوقّع لا في السلوك — والنوع المسجَّل
      // يبقى مفيداً تشخيصياً على كل حال.
      expect(lastErrorType, contains('Exception'));
    });

    test('لا يرمي على مسار غير قابل للكتابة', () {
      initErrorLog(p.join(tmp.path, 'لا', 'يوجد', 'مسار'));
      expect(() => recordError(Exception('boom'), null), returnsNormally);
    });

    test('الحجم مُقيَّد: يُقصّ الأقدم ويبقى الأحدث', () {
      initErrorLog(tmp.path);
      for (var i = 0; i < 400; i++) {
        recordError(StateError('error number $i padding-padding-padding'),
            StackTrace.current);
      }
      final f = errorLogFile(tmp.path)!;
      expect(f.lengthSync(), lessThanOrEqualTo(kErrorLogMaxBytes * 2),
          reason: 'لا ينمو بلا حدّ على جهاز عيادة');

      final t = logText();
      expect(t, contains('error number 399'),
          reason: 'الأحدث محفوظ — وهو المطلوب عند التشخيص');
      expect(t, isNot(contains('error number 0 ')),
          reason: 'الأقدم قُصّ');
    });

    test('القصّ يبدأ من حدّ سجلّ كامل لا من منتصف قيد', () {
      initErrorLog(tmp.path);
      for (var i = 0; i < 400; i++) {
        recordError(StateError('padded error $i ${'x' * 60}'), null);
      }
      final t = logText();
      expect(t.trimLeft().startsWith('──'), isTrue,
          reason: 'لا نصف قيد في رأس الملف');
    });

    test('العدّاد ونوع آخر عطل يعكسان الواقع', () {
      initErrorLog(tmp.path);
      recordError(Exception('a'), null);
      recordError(StateError('b'), null);
      // `ArgumentError` و`StateError` أصناف عامة، فأسماؤها تُطابَق حرفياً
      // (بخلاف `Exception` — انظر الاختبار أعلاه).
      recordError(ArgumentError('c'), null);
      expect(errorsThisRun, 3);
      expect(lastErrorType, 'ArgumentError');
    });

    test('أثر المكدس يُسجَّل مقصوصاً — وهو آمن لأنه بلا قيم', () {
      initErrorLog(tmp.path);
      recordError(StateError('x'), StackTrace.current);
      final t = logText();
      expect(t, contains('m77b_error_boundary_test'),
          reason: 'الأثر يحمل أسماء ملفات ودوال — لا بيانات');
      final stackLines =
          t.split('\n').where((l) => l.startsWith('  ')).length;
      expect(stackLines, lessThanOrEqualTo(kStackLines));
    });
  });
}
