/// م177 — نموذج إضافة حجزٍ بالدور (قرار المالك): يحل نهائياً محل مربع
/// الإضافة العلوي وزر + الصغير داخل اللوحة — **ورقةٌ منبثقة من الأسفل**
/// على الهاتف وحوارٌ متمركز على الكمبيوتر، بنفس سلوك «إضافة ومتابعة»
/// القائم حرفياً (quickAdd نفسها — لا مساس بطبقة البيانات والمزامنة).
///
/// سلسلة Enter (قرار المالك): الاسم ⇒ الهاتف ⇒ الملاحظات، وEnter الأخير
/// يحفظ — ويبقى النموذج مفتوحاً بحقولٍ مفرغة ومؤشرٍ على الاسم للمريض
/// التالي فوراً، مع عدّاد المضافين بالجلسة.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import 'queue_screen.dart' show queueViewProvider;

/// فتح نموذج الإضافة: ورقة سفلية (هاتف) أو حوار متمركز (كمبيوتر).
Future<void> showQueueAddSheet(
  BuildContext context, {
  String name = '',
  String phone = '',
  String notes = '',
}) {
  final form = QueueAddForm(name: name, phone: phone, notes: notes);
  if (isDesktopUi(context)) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: BrandColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: form,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: BrandColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      // رفع الورقة فوق لوحة المفاتيح.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: form,
    ),
  );
}

class QueueAddForm extends ConsumerStatefulWidget {
  const QueueAddForm(
      {super.key, this.name = '', this.phone = '', this.notes = ''});

  final String name;
  final String phone;
  final String notes;

  @override
  ConsumerState<QueueAddForm> createState() => _QueueAddFormState();
}

class _QueueAddFormState extends ConsumerState<QueueAddForm> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.name);
  late final TextEditingController _phoneCtl =
      TextEditingController(text: widget.phone);
  late final TextEditingController _notesCtl =
      TextEditingController(text: widget.notes);
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _notesFocus = FocusNode();
  String _status = 'new';
  int _added = 0;

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _notesCtl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1200)));

  /// الحفظ — quickAdd القائمة حرفياً؛ يبقى النموذج مفتوحاً للتالي.
  void _save() {
    if (_nameCtl.text.trim().isEmpty) {
      _snack('الرجاء إدخال الاسم');
      _nameFocus.requestFocus();
      return;
    }
    final added = ref.read(queueViewProvider.notifier).quickAdd(
          name: _nameCtl.text,
          phone: _phoneCtl.text,
          status: _status,
          notes: _notesCtl.text,
        );
    if (added != null) {
      setState(() => _added++);
      _snack('تمت الإضافة');
    }
    _nameCtl.clear();
    _phoneCtl.clear();
    _notesCtl.clear();
    _nameFocus.requestFocus();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: BrandColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: BrandColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: BrandColors.line),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(queueViewProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person_add_alt_1_rounded,
                  size: 18, color: BrandColors.goldDark),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'إضافة حجز بالدور${view.clinic == null ? '' : ' — ${view.clinic}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brand900),
                ),
              ),
              if (_added > 0)
                Container(
                  key: const Key('queue-add-count'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: BrandColors.green.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            BrandColors.green.withValues(alpha: .35)),
                  ),
                  child: Text('أُضيف $_added',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.green)),
                ),
            ]),
            const SizedBox(height: 12),
            // ── سلسلة Enter: الاسم ⇒ الهاتف ⇒ الملاحظات ⇒ حفظ ──
            TextField(
              key: const Key('queue-add-name'),
              controller: _nameCtl,
              focusNode: _nameFocus,
              autofocus: true,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
              decoration: _dec('اسم المريض'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('queue-add-phone'),
              controller: _phoneCtl,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _notesFocus.requestFocus(),
              decoration: _dec('الهاتف (اختياري)'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('queue-add-notes'),
              controller: _notesCtl,
              focusNode: _notesFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: _dec('ملاحظات (اختياري)'),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                key: const Key('queue-add-new'),
                label: const Text('جديد'),
                selected: _status == 'new',
                selectedColor: BrandColors.brand600,
                labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _status == 'new'
                        ? Colors.white
                        : BrandColors.ink),
                onSelected: (_) => setState(() => _status = 'new'),
              ),
              ChoiceChip(
                key: const Key('queue-add-review'),
                label: const Text('مراجعة'),
                selected: _status == 'review',
                selectedColor: BrandColors.brand600,
                labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _status == 'review'
                        ? Colors.white
                        : BrandColors.ink),
                onSelected: (_) => setState(() => _status = 'review'),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('queue-add-go'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.brand600,
                    padding: const EdgeInsets.symmetric(vertical: 11)),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('إضافة ومتابعة',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Enter ينقلك للحقل التالي — وآخر Enter يحفظ ويبقي '
                'النموذج مفتوحاً للمريض التالي.',
                style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
