/// منتقي نوع الدفع للمصروف (كاش / تحويل). الافتراض كاش لأن أغلب شراء
/// المصروفات نقديّ. يُستعمل في نافذتَي سحب الراتب وبند المصروف.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PaymentPicker extends StatelessWidget {
  const PaymentPicker({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String v, IconData ic) {
      final on = value == v;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(v),
          avatar: Icon(ic,
              size: 16, color: on ? Colors.white : BrandColors.mut),
          selected: on,
          selectedColor: BrandColors.brand,
          labelStyle: TextStyle(
              color: on ? Colors.white : BrandColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5),
          onSelected: (_) => onChanged(v),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text('نوع الدفع:',
              style: TextStyle(fontSize: 12.5, color: BrandColors.mut)),
          const SizedBox(width: 8),
          chip('كاش', Icons.payments_rounded),
          chip('تحويل', Icons.swap_horiz_rounded),
        ],
      ),
    );
  }
}
