/// «معلومات مختصرة» — عرض وتعديل ملاحظة الزيارة/الدفعة (قرار المالك).
///
///  الملاحظة تعيش على صف السجل نفسه (record.notes / prosthetic.notes)
///  فهي معزولة بنيوياً: مرتبطة بمعرّف الصف الفريد لا باسم المريض، لا
///  تظهر إلا في سياق صفها، وتعبر المزامنة داخل حمولة الصف تلقائياً.
///
///  المنافذ: قائمة كباب صف السجل في ملف المريض (هاتف)، قائمة الضغط
///  المطول في الإدخال اليومي (هاتف)، وقائمة السياق بجدول المكتب.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../app/data_revision.dart' show bumpDataRevision;
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../staff/staff_gate.dart' show staffAllowed;

/// يفتح نافذة المعلومات المختصرة لصفٍّ (سجل أو تركيبة).
///
/// [kind]: r/dp ⇒ مستودع السجلات، p ⇒ التركيبات. التعديل يتطلب صلاحية
/// records.edit — بدونها النافذة للعرض فقط.
Future<void> showQuickInfoDialog(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  required String id,
  required String patientName,
}) async {
  final repos = ref.read(reposProvider);
  final isPros = kind == 'p';
  final row =
      isPros ? repos.prosthetics.getById(id) : repos.records.getById(id);
  if (row == null) return;
  final raw = '${row['notes'] ?? ''}'.trim();
  final current = raw == 'null' ? '' : raw;
  final canEdit = staffAllowed('records.edit');

  final next = await showDialog<String>(
    context: context,
    builder: (ctx) => _QuickInfoDialog(
      patientName: patientName,
      initial: current,
      canEdit: canEdit,
    ),
  );

  if (next == null) return; // إغلاق بلا حفظ
  final txt = next.trim();
  if (txt == current) return;
  final val = txt.isEmpty ? null : txt;

  // م-إصلاح المزامنة (بلاغ المالك «الملخص يختلف بين الأجهزة»): كان الحفظ
  // يمرّ عبر .update الذي لا يختم dirty ⇒ لا يُدفع أبداً، فيراه الجهاز
  // الكاتب وحده. updateLocal يختم dirty+HLC ويدخل الطابور فعلاً.
  //
  // وتوحيد مصدر الحقيقة: ملاحظة الزيارة تُكتب على **كل** نسخها المرتبطة
  // (الصف الظاهر + الدين المرتبط + صف الأصل حين يكون الظاهر دفعةً) فتتطابق
  // كل الشاشات — دون المساس بملاحظة الدين المستقلة (تُحرَّر من شاشات الدين).
  final writes = <({String table, String rowId})>[
    (table: isPros ? 'p' : 'r', rowId: id),
  ];

  final row0 = row; // الصف الظاهر (قُرئ أعلاه)
  // الدين المرتبط: عبر debtId على الصف، أو دينٌ recordId/prostheticId=id.
  String linkedDebtId = '${row0['debtId'] ?? ''}'.trim();
  if (linkedDebtId.isEmpty || linkedDebtId == 'null') {
    for (final d in repos.debts.getAll()) {
      final rid = '${d['recordId'] ?? ''}';
      final pid = '${d['prostheticId'] ?? ''}';
      if (rid == id || pid == id) {
        linkedDebtId = '${d['id']}';
        // صف الأصل المخفي (حين الظاهر دفعة أولى): اكتب عليه أيضاً.
        final srcId = pid.isNotEmpty && pid != 'null' ? pid : rid;
        if (srcId.isNotEmpty && srcId != id) {
          writes.add((
            table: pid.isNotEmpty && pid != 'null' ? 'p' : 'r',
            rowId: srcId,
          ));
        }
        break;
      }
    }
  }
  if (linkedDebtId.isNotEmpty && linkedDebtId != 'null') {
    writes.add((table: 'd', rowId: linkedDebtId));
  }

  for (final w in writes) {
    switch (w.table) {
      case 'p':
        repos.prosthetics.updateLocal(w.rowId, {'notes': val});
      case 'd':
        repos.debts.updateLocal(w.rowId, {'notes': val});
      case _:
        repos.records.updateLocal(w.rowId, {'notes': val});
    }
  }

  recordAudit(repos.db,
      action: 'record.note',
      entity: isPros ? 'prosthetic' : 'record',
      entityId: id,
      detail: {'name': patientName, 'len': txt.length});
  // نبض موحّد: تظهر فوراً في كل شاشة مرتبطة بلا انتظار إعادة بناء.
  bumpDataRevision(ref);
}

class _QuickInfoDialog extends StatefulWidget {
  const _QuickInfoDialog({
    required this.patientName,
    required this.initial,
    required this.canEdit,
  });

  final String patientName;
  final String initial;
  final bool canEdit;

  @override
  State<_QuickInfoDialog> createState() => _QuickInfoDialogState();
}

class _QuickInfoDialogState extends State<_QuickInfoDialog> {
  late final TextEditingController ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        key: const Key('quick-info-dialog'),
        backgroundColor: BrandColors.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.sticky_note_2_rounded,
                size: 20, color: BrandColors.goldDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'معلومات مختصرة — ${widget.patientName}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: BrandColors.brandText,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ملاحظة مرتبطة بهذه الزيارة/الدفعة وحدها — لا تظهر في أي '
                'مكان آخر.',
                style: TextStyle(
                    fontSize: 11, height: 1.5, color: BrandColors.mut),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('quick-info-field'),
                controller: ctl,
                enabled: widget.canEdit,
                maxLines: 4,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: widget.canEdit
                      ? 'اكتب المعلومات المختصرة…'
                      : 'لا صلاحية تعديل — عرض فقط',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          if (widget.canEdit)
            FilledButton.icon(
              key: const Key('quick-info-save'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.brand600,
              ),
              onPressed: () => Navigator.of(context).pop(ctl.text),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('حفظ'),
            ),
        ],
      ),
    );
  }
}
