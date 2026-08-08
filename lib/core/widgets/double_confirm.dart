/// التأكيد المزدوج مع العداد — توأم DoubleConfirm.vue حرفياً:
/// أيقونة حذف، عنوان، رسالة، تحذير «لا يمكن التراجع»، زر «تأكيد الحذف»
/// لا يعمل إلا بعد انتهاء العداد («يمكنك التأكيد بعد N ثوانٍ...»).
///
/// [confirmDelete] هي البوابة العامة: تقرأ dcConfirm من config —
/// النوع المطفأ ({type}On == false) يمرّ بلا نافذة (سلوك الأصل).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/js_compat.dart';

/// يقرأ إعداد dcConfirm لنوع (rec/debt/pat/appt) ويعرض النافذة إن كان
/// مفعّلاً. يعيد true عند التأكيد (أو عندما يكون التأكيد مطفأً).
Future<bool> confirmDelete(
  BuildContext context, {
  required Map<String, Object?> config,
  required String type,
  String title = 'تأكيد الحذف',
  String msg = '',
}) async {
  final dcV = config['dcConfirm'];
  final dc = dcV is Map ? dcV : const {};
  if (dc['${type}On'] == false) return true;
  final dur = jsNumOr0(jsOr(dc['${type}Dur'], 3)).toInt();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => DoubleConfirmDialog(title: title, msg: msg, duration: dur),
  );
  return ok == true;
}

class DoubleConfirmDialog extends StatefulWidget {
  const DoubleConfirmDialog({
    super.key,
    this.title = 'تأكيد الحذف',
    this.msg = '',
    this.duration = 3,
  });

  final String title;
  final String msg;
  final int duration;

  @override
  State<DoubleConfirmDialog> createState() => _DoubleConfirmDialogState();
}

class _DoubleConfirmDialogState extends State<DoubleConfirmDialog> {
  late int countdown;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    countdown = widget.duration < 0 ? 0 : widget.duration;
    if (countdown > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => countdown--);
        if (countdown <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = countdown <= 0;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: BrandColors.red.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFF87171), size: 28),
          ),
          const SizedBox(height: 10),
          Text(widget.title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          if (widget.msg.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(widget.msg,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: BrandColors.mut)),
          ],
          const SizedBox(height: 8),
          const Text('⚠️ هذا الإجراء لا يمكن التراجع عنه!',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF87171))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('dc-cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('dc-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: ready
                      ? BrandColors.red
                      : BrandColors.red.withValues(alpha: .35),
                ),
                onPressed:
                    ready ? () => Navigator.pop(context, true) : () {},
                child: const Text('تأكيد الحذف'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 16,
            child: countdown > 0
                ? Text('يمكنك التأكيد بعد $countdown ثوانٍ...',
                    key: const Key('dc-countdown'),
                    style: TextStyle(
                        fontSize: 11, color: BrandColors.mut2))
                : null,
          ),
        ],
      ),
    );
  }
}
