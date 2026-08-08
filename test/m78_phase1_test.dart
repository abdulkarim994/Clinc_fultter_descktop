/// اختبارات م78 — المرحلة الأولى: إصلاحات معزولة.
///
///  أثقل ما هنا هو **تجاوز المصادقة بمغلّف منحطّ**: ثغرة كانت قائمة في
///  الدالة نفسها التي يقدّمها دليل الأمن بوصفها إنجازه الأول. اختبار
///  الانحدار عليها ليس تكميلياً — هو الغرض من هذا الملف.
library;

import 'package:dental_clinic_flutter/core/app_build.dart';
import 'package:dental_clinic_flutter/features/auth/password_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────
  group('م78 — سدّ تجاوز المصادقة بمغلّف منحطّ', () {
    test('مغلّف بهاش فارغ يُرفض — كان يقبل أي كلمة مرور', () {
      // الآلية: keyLength = expected.length = 0 ⇒ لا تدور حلقة الاشتقاق،
      // فتُقارَن قائمتان فارغتان وتتساويان.
      const degenerate = r'pbkdf2$sha256$1$c2FsdA==$';

      expect(verifyPassword('أي-كلمة-مرور-عشوائية', degenerate), isFalse,
          reason: 'م78: هذا هو التجاوز بعينه');
      expect(verifyPassword('', degenerate), isFalse);
      expect(verifyPassword('x', degenerate), isFalse);
    });

    test('الهاش القصير المنحطّ يُرفض أيضاً — لا يكفي رفض الفارغ وحده', () {
      // أربعة بايتات: فضاء بحث 2^32 يُستنفد فوراً. الحدّ 16 بايتاً.
      const shortHash = r'pbkdf2$sha256$1$c2FsdA==$AAAAAA==';
      expect(verifyPassword('أي-كلمة', shortHash), isFalse);
    });

    test('الملح الفارغ يُرفض — بلا ملح تنكسر الحماية من الجداول المسبقة', () {
      const noSalt = r'pbkdf2$sha256$120000$$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      expect(verifyPassword('أي-كلمة', noSalt), isFalse);
    });

    test('المسار السليم لم يتأثّر — الحارس ليس حاجزاً', () {
      // تكرارات قليلة عمداً: الاختبار يفحص المنطق لا الكلفة الحسابية.
      final env = hashPassword('كلمة-سرّ-قوية-جداً', iterations: 120);

      expect(verifyPassword('كلمة-سرّ-قوية-جداً', env), isTrue,
          reason: 'الكلمة الصحيحة ما زالت تُقبل');
      expect(verifyPassword('كلمة-سرّ-قوية-جدا', env), isFalse,
          reason: 'حرف واحد ناقص يكفي للرفض');
      expect(verifyPassword('', env), isFalse);
    });

    test('الهاش القديم العاري ما زال يُقبل — الترحيل الشفّاف محفوظ', () {
      // sha256('secret') — الصيغة القديمة، 64 محرفاً hex.
      const legacy =
          '2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b';
      expect(isLegacyHash(legacy), isTrue);
      expect(verifyPassword('secret', legacy), isTrue,
          reason: 'م78 لم يكسر مسار الحسابات القديمة');
      expect(verifyPassword('wrong', legacy), isFalse);
      expect(needsRehash(legacy), isTrue);
    });

    test('المغلّفات المشوّهة كلها تُرفض بلا رمي', () {
      for (final bad in <String>[
        '',
        'garbage',
        r'pbkdf2$sha256$120000$c2FsdA==',              // أربعة أجزاء
        r'pbkdf2$sha512$120000$c2FsdA==$AAAA',         // خوارزمية مجهولة
        r'argon2$sha256$120000$c2FsdA==$AAAA',         // صيغة مجهولة
        r'pbkdf2$sha256$0$c2FsdA==$AAAA',              // صفر تكرار
        r'pbkdf2$sha256$-5$c2FsdA==$AAAA',             // تكرار سالب
        r'pbkdf2$sha256$abc$c2FsdA==$AAAA',            // تكرار غير رقمي
        r'pbkdf2$sha256$120000$!!!$AAAA',              // ملح غير base64
        r'pbkdf2$sha256$120000$c2FsdA==$!!!',          // هاش غير base64
      ]) {
        expect(() => verifyPassword('x', bad), returnsNormally,
            reason: 'لا يرمي على: $bad');
        expect(verifyPassword('x', bad), isFalse, reason: 'يُرفض: $bad');
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  group('م78 — بطاقة هوية البناء', () {
    test('رقم المرحلة لم يعد متجمّداً عند v35', () {
      expect(kAppStage, isNot('v35'),
          reason: 'م78: كان متأخّراً ثلاثاً وأربعين مرحلة');
      expect(kAppStage, matches(RegExp(r'^v\d+$')));
      expect(int.parse(kAppStage.substring(1)), greaterThanOrEqualTo(78));
    });

    test('التاريخ متّسق مع المرحلة والبطاقة تُبنى صحيحة', () {
      expect(kAppBuildDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(DateTime.parse(kAppBuildDate).isAfter(DateTime(2026, 7, 28)),
          isTrue, reason: 'أحدث من البناء السابق');
      expect(appBuildLabel, contains(kAppStage));
      expect(appBuildLabel, contains(kAppBuildDate));
    });
  });
}
