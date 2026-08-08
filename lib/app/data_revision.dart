/// م-إصلاح — نبض بيانات موحّد عابر للشاشات.
///
///  المشكلة (بلاغ المالك): تعديل دفعة/دين على المكتب يتأخر ظهوره في جدول
///  الرئيسية. السبب أن كل كاتبٍ كان ينبض مزوّد نسخةٍ **جزئياً** (الديون
///  تنبض financeRev فقط) بينما الرئيسية المكتبية تراقب patientsRev — فلا
///  تُعاد بناءً. الحل: دالةٌ واحدة تنبض **اتحاد** مزوّدات النسخة، يستدعيها
///  كل كاتبٍ ماليّ، فتُعاد كل شاشةٍ مفتوحةٍ في اللحظة نفسها مهما كان
///  المزوّد الذي تراقبه.
///
///  آمنةٌ تماماً: النبض الزائد لا يكسر شيئاً — الشاشة التي لا تراقب مزوّداً
///  معيناً تتجاهله؛ والشاشات الهاتفية كانت تنبض المجموعتين أصلاً فلا يتغير
///  سلوكها. لا تمسّ منطق الأعمال ولا المزامنة ولا قاعدة البيانات.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/expenses/expenses_screen.dart' show expensesRefreshProvider;
import '../features/finance/finance_screen.dart' show financeRevProvider;
import '../features/patients/patients_tab.dart' show patientsRevProvider;

/// ينبض كل مزوّدات نسخة البيانات دفعةً واحدة — فتُعاد بناء كل الشاشات
/// المرتبطة (الرئيسية، الإدخال اليومي، ملف المريض، الديون، الخزينة،
/// المالية، المصروفات) فوراً بعد أي كتابةٍ ماليّة.
///
/// نظير `projectionListeners` في providers.dart (نبض ما-بعد-السحب) لكن
/// للكتابة المحلية المباشرة.
void bumpDataRevision(WidgetRef ref) {
  ref.read(patientsRevProvider.notifier).state++;
  ref.read(financeRevProvider.notifier).state++;
  ref.read(expensesRefreshProvider.notifier).state++;
}
