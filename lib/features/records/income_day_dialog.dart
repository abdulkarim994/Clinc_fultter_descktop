/// م101 — حوار «أين يُحسب الدخل؟» عند الحفظ بتاريخٍ غير اليوم.
///
/// المبدأ (قرار المالك): كل مبلغ يُحسب في **يوم واحد بالضبط** — لا ازدواج
/// بين دخل اليوم الحالي ودخل التاريخ المختار. الحوار يظهر فقط حين يختار
/// المستخدم تاريخاً غير اليوم، ويحدد «يوم الاحتساب» (incomeDate).
///
/// م103 — إعادة تصميم (طلب المالك): بطاقة قرب أسفل الشاشة فوق زر
/// «حفظ الزيارة»، نصٌّ أوضح، وخياران عريضان مكدسان يعرض كلٌّ منهما
/// تاريخه الفعلي مع وصفٍ صغير — والإلغاء نصيٌّ بالمنتصف.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart' show getCurrentDate;
import 'home_logic.dart' show kNoIncomeDay;

/// يعيد يوم الاحتساب: التاريخ نفسه إن كان اليوم (بلا حوار)، أو اختيار
/// المستخدم، أو null عند الإلغاء (فلا حفظ).
Future<String?> askIncomeDay(BuildContext context, String chosenDate) {
  final today = getCurrentDate();
  if (chosenDate.isEmpty || chosenDate == today) {
    return Future.value(chosenDate);
  }

  // خيار عريض: عنوان + وصف صغير، معبأ (الافتراضي) أو محدد.
  Widget option({
    required Key key,
    required String title,
    required String subtitle,
    required bool filled,
    required VoidCallback onTap,
  }) =>
      Material(
        color: filled ? BrandColors.brand600 : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: filled
              ? BorderSide.none
              : BorderSide(color: BrandColors.gold.withValues(alpha: .55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color:
                            filled ? Colors.white : BrandColors.goldDark)),
                const SizedBox(height: 2),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: filled
                            ? const Color.fromRGBO(255, 255, 255, .85)
                            : BrandColors.mut)),
              ],
            ),
          ),
        ),
      );

  return showDialog<String>(
    context: context,
    builder: (dctx) => Dialog(
      // م103 — قرب أسفل الشاشة (فوق زر «حفظ الزيارة» بمسافة مريحة).
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(14, 24, 14, 92),
      backgroundColor: BrandColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.event_note_rounded,
                  size: 20, color: BrandColors.goldDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text('أين يُحسب هذا الدخل؟',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'تاريخ الزيارة المختار ليس اليوم — يُحسب الدخل في يومٍ '
              'واحد فقط.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.5, color: BrandColors.mut),
            ),
            const SizedBox(height: 12),
            option(
              key: const Key('income-day-today'),
              title: 'في دخل هذا اليوم',
              subtitle: 'قبضتَ المال اليوم ($today) — يظهر في جدول اليوم',
              filled: true,
              onTap: () => Navigator.pop(dctx, today),
            ),
            const SizedBox(height: 8),
            option(
              key: const Key('income-day-doc'),
              title: 'في دخل اليوم المسجَّل',
              subtitle: 'يُحسب بتاريخ الزيارة ($chosenDate)',
              filled: false,
              onTap: () => Navigator.pop(dctx, chosenDate),
            ),
            const SizedBox(height: 8),
            // م105 — الخيار الثالث: في السجلات والمالية فقط.
            Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: BrandColors.line, width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('income-day-none'),
                onTap: () => Navigator.pop(dctx, kNoIncomeDay),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  child: Column(children: [
                    Text('في السجلات والمالية فقط',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.ink)),
                    const SizedBox(height: 2),
                    Text('لا يظهر في أي دخل يومي — يبقى في ملف المريض والمالية والكشوف',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10.5, color: BrandColors.mut)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontSize: 12.5, color: BrandColors.mut)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
