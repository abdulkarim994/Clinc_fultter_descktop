/// اختبارات م82 — المرحلة الخامسة: الهيكلة.
///
///  محورها **قاعدة معمارية مفروضة بالاختبار** لا بالنيّة. دورةُ الاعتماد
///  التي كُسرت اليوم تعود غداً بسطر استيراد واحد إن لم يمنعها شيء — وهذا
///  ما يجعل الاختبار هنا أهمّ من التعديل نفسه.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/core/auth/auth_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════
  group('م82/أ — اتجاه الاعتماد مفروضٌ لا موصوف', () {
    /// ملفات طبقة البيانات — تُقرأ من القرص لا تُستنتج.
    List<File> dataLayerFiles() {
      final dir = Directory('lib/data');
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    test('لا ملف في data يستورد من features — الدورة لا تعود', () {
      final offenders = <String>[];
      for (final f in dataLayerFiles()) {
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (!t.startsWith('import ') && !t.startsWith('export ')) continue;
          if (t.contains('features/')) {
            offenders.add('${f.path}  ←  $t');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'م82: طبقة البيانات لا تستورد صعوداً.\n'
              'ضع العقد المشترك في core/ ونفّذه في المكانين.\n'
              '${offenders.join('\n')}');
    });

    test('core لا يستورد من data ولا من features — الطبقة المحايدة', () {
      final dir = Directory('lib/core');
      final offenders = <String>[];
      for (final f in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final line in f.readAsLinesSync()) {
          final t = line.trim();
          if (!t.startsWith('import ') && !t.startsWith('export ')) continue;
          if (t.contains('/data/') ||
              t.contains('data/') && t.contains('..') ||
              t.contains('features/')) {
            offenders.add('${f.path}  ←  $t');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'م82: core محايدة — تستورد منها الطبقتان ولا تستورد '
              'من أيّهما.\n${offenders.join('\n')}');
    });

    test('عقود المصادقة تعيش في core وتعمل مستقلّةً', () {
      // الدليل العملي على الاستقلال: تُستدعى هنا بلا استيراد data ولا
      // features في هذا الملف.
      expect(validateCredentials('', 'x'), isNotNull);
      expect(validateCredentials('a@b.co', 'قصيرة'), isNotNull,
          reason: 'أقل من ثمانية محارف');
      expect(validateCredentials('a@b.co', 'كلمة-مرور-طويلة'), isNull);

      const u = AuthUser(uid: 'u1', email: 'a@b.co');
      expect(u.uid, 'u1');
      expect(u.email, 'a@b.co');
    });

    test('المسار القديم ما زال يعمل — إعادة التصدير تحفظ التوافق', () {
      // `features/auth/auth_service.dart` يعيد تصدير العقود، فكل مستورد
      // قائم يعمل بلا تعديل سطر واحد. يُفحص بالمصدر لا بالاستيراد كي
      // يبقى هذا الملف خالياً من اعتماد الميزات.
      final src = File('lib/features/auth/auth_service.dart').readAsStringSync();
      expect(src, contains("export '../../core/auth/auth_contracts.dart'"));
      expect(src, contains('AuthService'));
      expect(src, contains('AuthUser'));
      expect(src, contains('validateCredentials'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م82/ب — الأقسام غير المعروضة لا تُبنى', () {
    // م92 — تفكّكت الإعدادات من أكورديونٍ إلى «قائمة رئيسية ← صفحة قسم»،
    // وثابت م82 (لا عملَ مهدوراً على أقسامٍ لا تُعرض) بقي بصيغة أقوى:
    // القائمة الرئيسية لا تبني جسمَ قسمٍ واحد، وصفحة القسم تبني جسمها
    // وحده. يحرسه الشكلُ النصي نفسه الذي كانت تحرسه هذه المجموعة.
    test('سجلّ الأقسام يخزّن دوالَّ لا ودجات جاهزة', () {
      final src =
          File('lib/features/settings/settings_screen.dart').readAsStringSync();

      expect(src, contains('Widget Function(JMap) body'),
          reason: 'م82/م92: التوقيع يخزّن دالة — لا ودجة مبنية');
      expect(src, contains('children: [section.body(cfg)]'),
          reason: 'وتُستدعى في فرع صفحة القسم وحده');

      // ولا موضعَ في السجلّ يستدعي جسماً استدعاءً جاهزاً.
      final eager =
          RegExp(r'body: _\w+Body\(').allMatches(src).length;
      expect(eager, 0,
          reason: 'م82/م92: السجلّ إحالاتُ دوال (tear-offs) حصراً');
    });

    test('عدد إحالات الأجسام في السجلّ يطابق عدد الأقسام', () {
      final src =
          File('lib/features/settings/settings_screen.dart').readAsStringSync();
      final lazy = RegExp(r'body: _\w+Body,').allMatches(src).length;
      expect(lazy, greaterThanOrEqualTo(9),
          reason: 'كانت تُبنى كلها في كل إعادة رسم قبل م82');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('م82/ج — مفاتيح قائمة السجلات', () {
    test('كل بطاقة سجلّ تحمل مفتاحاً ثابتاً بمعرّفها', () {
      final src = File('lib/features/patients/patient_profile_screen.dart')
          .readAsStringSync();
      expect(src, contains("ValueKey('rec-"),
          reason: 'م82: بلا مفتاح تُستبدل الشجرة الفرعية بدل تحريكها');
      expect(src, contains('KeyedSubtree'));
    });
  });
}
