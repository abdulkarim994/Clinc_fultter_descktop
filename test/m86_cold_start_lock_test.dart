/// اختبار م86 — القفل يصمد عبر إغلاق التطبيق وإعادة فتحه.
///
///  العيب الذي يحرسه (رصده المالك): قفلُ الخمول كان حالةَ ذاكرةٍ فقط
///  (`lockedProvider`)، فإغلاقُ التطبيق وإعادةُ فتحه يُصفّرها ويدخل مباشرةً
///  إلى الصدفة بجلسةٍ مستعادة **بلا كلمة مرور** — أي أن «الإغلاق» يتخطّى
///  القفل كلّه. الإصلاح: كلُّ إقلاعٍ بارد على جلسةٍ محفوظة يبدأ مقفلاً.
///
///  التحكّم: يُحاكى «الإغلاق وإعادة الفتح» ببذر حسابٍ ودخولٍ في حاوية
///  مستقلّة تُرمى، ثم تركيب `DentalApp` من جديد بنفس مجلد البيانات — فهي
///  جلسةٌ مستعادة لا دخولٌ صريح، تماماً كإقلاعٍ بارد.
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/features/auth/lock_prefs.dart'
    show setLockOnStart;
import 'package:dental_clinic_flutter/features/auth/onboarding_service.dart';
import 'package:dental_clinic_flutter/features/shell/app_shell.dart';
import 'package:dental_clinic_flutter/main.dart';
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('م86 — القفل يصمد عبر الإغلاق وإعادة الفتح', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('m86_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// يبذر حساباً مُعَدّاً كاملاً مع دخولٍ ناجح (يخزّن مُتحقِّق القفل
    /// والجلسة)، ثم يرمي الحاوية — فيصير أي تركيبٍ تالٍ «جلسةً مستعادة».
    Future<void> seedLoggedInAndSetup() async {
      final seed = ProviderContainer(
          overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
      await seed.read(authServiceProvider).register('doc@clinic.ly', 'secret12');
      // الدخول عبر وحدة التحكّم لا الخدمة مباشرةً: هي اللحظة التي يُخزَّن
      // فيها مُتحقِّق القفل (ownerUid يُضبَط ثم storeLockVerifier).
      await seed
          .read(authProvider.notifier)
          .login('doc@clinic.ly', 'secret12', true);
      final repos = seed.read(reposProvider);
      repos.settings.set('app.config', {
        'centerName': 'مركز الأمل',
        'clinics': ['العيادة أ'],
      });
      markSetupComplete(seed.read(localDbProvider), 'doc@clinic.ly');
      // م97 — القفل صار معطَّلاً افتراضاً؛ نفعّله صراحةً كي يحرس هذا
      // الاختبارُ صمودَ القفل عبر الإغلاق (مُتحقِّق كلمة المرور موجود).
      setLockOnStart(seed.read(localDbProvider), true);
      seed.dispose();
    }

    testWidgets('إعادة الفتح على جلسةٍ محفوظة ⇒ يبدأ مقفلاً', (tester) async {
      await seedLoggedInAndSetup();

      // «إعادة فتح» التطبيق: تركيبٌ جديد بنفس مجلد البيانات.
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // الصدفة مُركَّبة (الجلسة استُعيدت) لكن غطاء القفل فوقها.
      expect(find.byType(AppShellScreen), findsOneWidget,
          reason: 'م86: الشجرة تحت القفل حيّة — لا عمل يُفقد');
      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget,
          reason: 'م86: إعادة الفتح تبدأ مقفلة — لا دخول بلا كلمة مرور');
      expect(find.text('الجلسة مقفلة'), findsOneWidget);
      // وحقلُ كلمة المرور حاضرٌ (لا مجرّد خيار خروج) لأن المُتحقِّق مخزَّن.
      expect(find.byKey(const Key('idle-lock-field')), findsOneWidget);
    });

    testWidgets('الفتح بكلمة المرور الصحيحة يرفع القفل', (tester) async {
      await seedLoggedInAndSetup();
      await tester.pumpWidget(ProviderScope(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)],
        child: const DentalApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('idle-lock-title')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('idle-lock-field')), 'secret12');
      await tester.tap(find.byKey(const Key('idle-lock-unlock')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('idle-lock-title')), findsNothing,
          reason: 'م86: كلمة المرور الصحيحة ترفع القفل');
      expect(find.byType(AppShellScreen), findsOneWidget);
    });
  });
}
