/// م104 — قفل اليوم (قرار المالك بتصحيح): زرٌّ يقفل يوم دخلٍ بعينه بعد
/// تحذير، ويولّد تقرير PDF لطباعته/مشاركته، وتُحفظ حالة القفل بصفّ
/// إعدادات متزامنٍ لكل يوم — **بلا أي مسحٍ للبيانات**: جدول دخل اليوم
/// مشتقٌّ من التاريخ فيفرغ تلقائياً بمنتصف الليل، والسجلات والمالية
/// والكشوف تبقى محفوظة للأبد.
///
/// بعد القفل: أي حفظٍ يقع «يوم احتسابه» في يومٍ مقفولٍ يُنبَّه صاحبه
/// ويُسمح له بعد التأكيد (لا منعَ بات).
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart' show jsNow;
import '../../data/repositories/settings_repository.dart';

/// مفتاح صف قفل يومٍ واحد.
String dayCloseKey(String date) => 'dayclose:$date';

/// مخزن حالة القفل — صف إعدادات لكل يوم (يتزامن كبقية الإعدادات).
class DayCloseStore {
  const DayCloseStore(this.settings);

  final SettingsRepository settings;

  bool isClosed(String date) => settings.get(dayCloseKey(date)) is Map;

  Map<String, Object?>? info(String date) {
    final v = settings.get(dayCloseKey(date));
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  /// قفل اليوم مع لقطة إجمالياته (للمرجعية في سجل التدقيق والمزامنة).
  void close(String date, Map<String, Object?> snapshot) =>
      settings.set(dayCloseKey(date), {...snapshot, 'closedAt': jsNow()});

  /// إعادة فتح اليوم (تصحيح خطأ) — شاهد قبر ينتشر لكل الأجهزة.
  void reopen(String date) => settings.softDelete(dayCloseKey(date));
}

/// حارس الكتابة بعد القفل: يمرّ صامتاً إن لم يكن اليوم مقفولاً، وإلا
/// يعرض تحذيراً ويعيد true فقط عند تأكيد المتابعة.
Future<bool> confirmClosedDayWrite(
  BuildContext context,
  SettingsRepository settings,
  String incomeDay,
) async {
  if (incomeDay.isEmpty || !DayCloseStore(settings).isClosed(incomeDay)) {
    return true;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_rounded, size: 20, color: BrandColors.goldDark),
        const SizedBox(width: 8),
        const Expanded(
            child: Text('هذا اليوم مُقفل',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
      ]),
      content: Text(
        'يوم $incomeDay أُقفل وطُبع تقريره.\n'
        'هل تريد المتابعة والإضافة إليه رغم ذلك؟',
        style: const TextStyle(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('تراجع')),
        FilledButton(
            key: const Key('closed-day-continue'),
            style:
                FilledButton.styleFrom(backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('متابعة رغم القفل')),
      ],
    ),
  );
  return ok == true;
}
