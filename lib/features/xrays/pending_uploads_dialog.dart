/// نافذة «صور بانتظار الرفع» — التوأم الحرفي لـ PendingUploadsPopup.vue:
///   • العنوان بعدّاد + زر إغلاق.
///   • «رفع الكل» بشريط تقدم رقمي (i/N) و«حذف الكل» (بتأكيد).
///   • لكل عنصر: مصغرة (أو أيقونة بديلة) + اسم المريض + اسم الملف +
///     التاريخ + زرا رفع/حذف فرديان.
///   • حالة فارغة «لا توجد صور معلقة».
/// الرفع الفردي عبر reconcileOne (آمن التزامن بتصميمه: إعادة قراءة الحالة
/// + حجز المفتاح) والكلي يمر عليه عنصراً-عنصراً لتغذية شريط التقدم —
/// نبضة xrayVersion بعد كل عملية تحدّث الأيقونة والقوائم حيّاً.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import 'xray_store.dart' show dataUrlBytes;

Future<void> showPendingUploadsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const PendingUploadsDialog(),
    );

class PendingUploadsDialog extends ConsumerStatefulWidget {
  const PendingUploadsDialog({super.key});

  @override
  ConsumerState<PendingUploadsDialog> createState() =>
      _PendingUploadsDialogState();
}

class _PendingUploadsDialogState
    extends ConsumerState<PendingUploadsDialog> {
  bool _syncing = false;
  int _done = 0;
  int _total = 0;

  List<Map<String, Object?>> _items() =>
      ref.read(reposProvider).xrays.getPendingUploads();

  void _bump() => ref.read(xrayVersionProvider.notifier).state++;

  /// رفع عنصر واحد — reconcileOne؛ يتطلب وضع السحابة (خط أنابيب حي).
  Future<bool> _uploadOne(Map<String, Object?> row) async {
    final pipeline = ref.read(xrayPipelineProvider);
    if (pipeline == null) return false;
    try {
      return await pipeline.reconcileOne(row);
    } catch (_) {
      return false;
    } finally {
      _bump();
    }
  }

  /// «رفع الكل» — عنصراً-عنصراً لتغذية شريط التقدم (i/N) كما في الأصل.
  Future<void> _syncAll() async {
    final items = _items();
    if (items.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _done = 0;
      _total = items.length;
    });
    var ok = 0;
    for (final row in items) {
      if (!mounted) return;
      if (await _uploadOne(row)) ok++;
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _syncing = false);
    final kept = _total - ok;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(kept == 0
            ? 'رُفعت $ok ${ok == 1 ? 'صورة' : 'صور'} بنجاح'
            : 'رُفعت $ok وبقيت $kept — سيعاد تلقائياً')));
  }

  /// حذف معلّقة واحدة: الصورة لم تُرفع بعد ⇒ حذف الصف والملفات المحلية
  /// فقط (لا حذف سحابياً) — توأم removeSinglePending.
  void _deleteOne(String id) {
    final store = ref.read(xrayStoreProvider);
    store.deleteXray(id);
    _bump();
  }

  Future<void> _deleteAll() async {
    final items = _items();
    if (items.isEmpty || _syncing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف كل الصور المعلقة؟'),
        content: Text(
            '${items.length} ${items.length == 1 ? 'صورة' : 'صور'} لم تُرفع بعد — الحذف نهائي من هذا الجهاز.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('pu-delete-all-confirm'),
              style:
                  FilledButton.styleFrom(backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف الكل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final row in _items()) {
      ref.read(xrayStoreProvider).deleteXray('${row['id']}');
    }
    _bump();
  }

  String _fmtDate(Object? createdAt) {
    final d = DateTime.tryParse('${createdAt ?? ''}');
    if (d == null) return '';
    String n2(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${n2(d.month)}/${n2(d.day)} ${n2(d.hour)}:${n2(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(xrayVersionProvider); // القائمة والحالة تتحدثان حيّاً
    final items = _items();
    final cloud = ref.watch(xrayPipelineProvider) != null;

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 40),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── العنوان بعدّاد + إغلاق ──
              Row(children: [
                const Icon(Icons.cloud_upload_rounded,
                    size: 20, color: Color(0xFFB8860B)),
                const SizedBox(width: 8),
                const Text('صور بانتظار الرفع',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D6),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${items.length}',
                      key: const Key('pu-count'),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A6508))),
                ),
                const Spacer(),
                IconButton(
                    key: const Key('pu-close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20)),
              ]),

              // ── أزرار الإجراءات ──
              if (items.isNotEmpty) ...[
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('pu-sync-all'),
                      onPressed:
                          (!cloud || _syncing) ? null : _syncAll,
                      icon: _syncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('رفع الكل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('pu-delete-all'),
                      onPressed: _syncing ? null : _deleteAll,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: BrandColors.red),
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 16),
                      label: const Text('حذف الكل'),
                    ),
                  ),
                ]),
                if (!cloud)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'الرفع يتطلب الاتصال السحابي (الإعدادات ← الاتصال السحابي)',
                        style: TextStyle(
                            fontSize: 11.5, color: BrandColors.mut2)),
                  ),
                // ── شريط التقدم (i/N) ──
                if (_syncing) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                        value: _total == 0 ? 0 : _done / _total,
                        minHeight: 6),
                  ),
                  const SizedBox(height: 4),
                  Text('جارٍ الرفع $_done/$_total…',
                      key: const Key('pu-progress'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                ],
                const SizedBox(height: 10),
              ],

              // ── القائمة / الحالة الفارغة ──
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  size: 38,
                                  color: const Color(0xFFB8860B)
                                      .withValues(alpha: .3)),
                              const SizedBox(height: 8),
                              Text('لا توجد صور معلقة',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: BrandColors.mut2)),
                            ]),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, i) {
                          final row = items[i];
                          final id = '${row['id']}';
                          final thumb =
                              dataUrlBytes(row['thumbnail_data']);
                          return Container(
                            key: Key('pu-item-$i'),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: BrandColors.surface2,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: BrandColors.line),
                            ),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: thumb != null
                                    ? Image.memory(thumb,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true)
                                    : Container(
                                        width: 44,
                                        height: 44,
                                        color: const Color(0xFFFFF1D6),
                                        child: const Icon(
                                            Icons.image_outlined,
                                            size: 20,
                                            color: Color(0xFFB8860B))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${row['patient_name'] ?? ''}'
                                                .trim()
                                                .isEmpty
                                            ? 'مريض'
                                            : '${row['patient_name']}',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight:
                                                FontWeight.w800)),
                                    Text(id.split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: BrandColors.mut2)),
                                    if (_fmtDate(row['created_at'])
                                        .isNotEmpty)
                                      Text(_fmtDate(row['created_at']),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: BrandColors.mut2)),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: Key('pu-item-sync-$i'),
                                tooltip: 'رفع',
                                onPressed: (!cloud || _syncing)
                                    ? null
                                    : () => _uploadOne(row),
                                icon: const Icon(Icons.sync_rounded,
                                    size: 18,
                                    color: Color(0xFF16A34A)),
                              ),
                              IconButton(
                                key: Key('pu-item-del-$i'),
                                tooltip: 'حذف',
                                onPressed: _syncing
                                    ? null
                                    : () => _deleteOne(id),
                                icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: BrandColors.red),
                              ),
                            ]),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
