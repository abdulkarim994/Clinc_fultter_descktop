/// اختبارات ثوابت التطبيع العربي — أول اختبارات التكافؤ المنقولة.
///
/// أهم ما فيها: مجموعة «التوائم» — تنفيذ تعبير SQL المولّد على محرك SQLite
/// حقيقي ومقارنته حرفياً بناتج دالة Dart، وهو نفس العقد الذي تحرسه اختبارات
/// المشروع الأصلي بين JS و SQL.
library;

import 'package:dental_clinic_flutter/core/utils/ar_normalize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';


void main() {

  group('arNorm — Dart twin of arNormJs()', () {
    test('folds hamza forms, strips tashkeel, trims and lowercases', () {
      expect(arNorm('أَحْمَد'), 'احمد');
      expect(arNorm('إِبْراهيم'), 'ابراهيم');
      expect(arNorm('آمنة'), 'امنه');
      expect(arNorm('فاطمة'), 'فاطمه');
      expect(arNorm('مصطفى'), 'مصطفي');
      expect(arNorm('مُؤمِن'), 'مومن');
      expect(arNorm('هيئة'), 'هييه');
      expect(arNorm('  عَلِيّ  '), 'علي');
      expect(arNorm('ABC Xy'), 'abc xy');
    });

    test('empty / null inputs', () {
      expect(arNorm(null), '');
      expect(arNorm(''), '');
    });
  });

  group('normPhone — port of utils/search.js', () {
    test('canonicalises realistic Libyan phone formats', () {
      expect(normPhone('+218 91-234 5678'), '912345678');
      expect(normPhone('00218912345678'), '912345678');
      expect(normPhone('0912345678'), '912345678');
      expect(normPhone('٠٩١٢٣٤٥٦٧٨'), '912345678');
      expect(normPhone('۰۹۱۲۳۴۵۶۷۸'), '912345678'); // Persian digits
      expect(normPhone('(091) 234.567/8'), '912345678');
      expect(normPhone('218912345678'), '912345678');
    });

    test('empty / non-digit inputs', () {
      expect(normPhone(null), '');
      expect(normPhone(''), '');
      expect(normPhone('abc'), '');
    });
  });

  group('SQL twins agree with Dart on a real SQLite engine', () {
    late Database db;

    setUp(() => db = sqlite3.openInMemory());
    tearDown(() => db.close());

    const names = [
      'أَحْمَد إِبْراهيم',
      'فاطمة الزّهراء',
      'مصطفى',
      'مُؤمِن آل هُدى',
      'إسْراء عبد الرّحمن',
      'آمنة بنت وهب',
      'هيئة التّمريض',
      '  خالِد المهديّ  ',
    ];

    test('arNormSql(literal) == arNorm(value)', () {
      for (final s in names) {
        final v =
            db.select("SELECT ${arNormSql("'$s'")} AS v").first['v'] as String;
        expect(v, arNorm(s), reason: 'divergence for "$s"');
      }
    });

    const phones = [
      '+218 91-234 5678',
      '00218912345678',
      '0912345678',
      '٠٩١٢٣٤٥٦٧٨',
      '(091) 234.567/8',
      '218912345678',
      '91 234 56 78',
    ];

    test('arNormPhoneSql(literal) == normPhone(value)', () {
      for (final s in phones) {
        final v = db
            .select("SELECT ${arNormPhoneSql("'$s'")} AS v")
            .first['v'] as String;
        expect(v, normPhone(s), reason: 'divergence for "$s"');
      }
    });
  });
}
