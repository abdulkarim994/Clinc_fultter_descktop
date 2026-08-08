/// قسم صور الأشعة في ملف المريض — توأم قسم الأشعة في PatientProfile.vue:
/// غلاف بلون العلامة الشفاف، ترويسة «⊕ صور الأشعة (N)» مع مبدّل نمط توأم
/// (زران أيقونيان والفعّال أخضر بأيقونة بيضاء)، شبكة مصغرات 52×52 بثلاث
/// حالات (سبينر استرجاع من R2 / فشل أحمر بصورة مكسورة / الصورة)، تحديد
/// متعدد بالضغط المطوّل 500ms (شريط أحمر «N محددة» + حذف/إلغاء + مربعات ✓)،
/// عرض تفصيلي بصفوف خضراء شفافة (اسم + تاريخ عربي + شارة «مرفوعة»/«بانتظار
/// الرفع» + أزرار مربعة للتسمية والحذف + تسمية سطرية يحفظها Enter)، وزر
/// رفع بحد متقطع «إرفاق صور أشعة» يتحول أثناء الرفع إلى «جاري التحميل...».
/// الأونلاين: مصغرة غائبة تُسترجَع من R2 في الخلفية (والفشل يعلَّم أحمر
/// وتُمنح فرصة جديدة عند عودة الاتصال)، والرفع المتصل يصرَّف فوراً برسالة
/// «تم رفع صور الأشعة بنجاح» مقابل «تم حفظ الصور — سيتم رفعها تلقائياً عند
/// الاتصال» (دلالات anyQueued حرفياً). عزل العيادة (المرحلة H): الوسم دائم
/// والترشيح خلف علم CLINIC_XRAY_ISOLATION (القديمة غير الموسومة تظهر دائماً).
library;

import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import '../../core/theme/app_theme.dart';
import '../../data/sync/db_sync.dart' show getMetaValue;
import '../patients/audit_trail.dart' show AuditAction, recordAudit;
import 'storage_meter.dart' show StorageMeter, humanBytesAr;
import 'xray_pipeline.dart'
    show enqueuePendingDelete, filterDeletedKeys, markXrayDeleted;
import 'xray_store.dart';
import 'xray_viewer.dart';
import '../staff/staff_gate.dart' show gateStaff;

typedef XrayPick = Future<List<(String, Uint8List)>> Function();

/// منتقي «الملفات» الافتراضي — file_selector (منتقي مستندات النظام؛ لا
/// يحتاج إذناً)؛ الاختبارات تستبدله.
Future<List<(String, Uint8List)>> defaultXrayPick() async {
  const group = XTypeGroup(
    label: 'صور',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
  );
  final files = await openFiles(acceptedTypeGroups: [group]);
  return [for (final f in files) (f.name, await f.readAsBytes())];
}

final xrayFilePickProvider = Provider<XrayPick>((ref) => defaultXrayPick);

/// م39 — منتقي «المعرض»: منتقي صور النظام باختيار متعدد (image_picker).
/// أندرويد 13+ عبر إذن قراءة الصور والأقدم عبر قراءة التخزين (المانيفست)
/// — النظام يتولى نافذة الإذن؛ الرفض يعيد قائمة فارغة بهدوء.
Future<List<(String, Uint8List)>> defaultXrayGalleryPick() async {
  try {
    final files = await ImagePicker().pickMultiImage();
    return [for (final f in files) (f.name, await f.readAsBytes())];
  } catch (_) {
    return const []; // إذن مرفوض/منصة بلا معرض — بلا انهيار.
  }
}

final xrayGalleryPickProvider = Provider<XrayPick>(
  (ref) => defaultXrayGalleryPick,
);

class XraySection extends ConsumerStatefulWidget {
  const XraySection({
    super.key,
    required this.patientName,
    this.clinic = '',
    this.phone = '',
  });

  final String patientName;

  /// عيادة الفتح — لوسم الصور الجديدة (دائم) وترشيح العزل (خلف العلم).
  final String clinic;

  /// م-عزل الهوية — هاتف الهوية المفتوحة: يعزل معرض السميّ (سطل «اسم|هاتف»)
  /// ويُختم على صف xrays الجديد (patient_id هوياتي). فارغٌ ⇒ السلوك القائم
  /// (سطل الاسم وحده) — لا فقد لأي صورة قديمة.
  final String phone;

  @override
  ConsumerState<XraySection> createState() => _XraySectionState();
}

class _XraySectionState extends ConsumerState<XraySection> {
  bool uploading = false;
  String? editingKey;
  final renameCtl = TextEditingController();

  // التحديد المتعدد — نظير xrayMultiSelect/xraySelected (بالفهارس المرئية).
  bool msMode = false;
  final selected = <int>{};

  // م142 — مؤقتات الحذف المؤجَّل (نافذة التراجع 3ث الافتراضية). التخلّص
  // يلغيها كي لا تُنفَّذ بعد نزع الودجت.
  final _pendingDeletes = <Timer>{};

  @override
  void dispose() {
    for (final t in _pendingDeletes) {
      t.cancel();
    }
    _pendingDeletes.clear();
    renameCtl.dispose();
    super.dispose();
  }

  /// م142 — مدة نافذة «التراجع» بالثواني قبل الحذف الفعلي. تُقرأ من مفتاح
  /// البيانات الوصفية المحلية `xray.delete_undo_secs` (int؛ الافتراضي 3
  /// حين تغيب/تفسد؛ 0 = مُعطَّلة ⇒ حذفٌ فوري بلا شريط تراجع). القيم السالبة
  /// تُثبَّت إلى الافتراضي.
  int _undoSecs() {
    final raw = getMetaValue(ref.read(localDbProvider), 'xray.delete_undo_secs');
    if (raw == null) return 3;
    final v = int.tryParse('$raw');
    if (v == null || v < 0) return 3;
    return v;
  }

  void _writeConfig(Map<String, Object?> next) {
    ref.read(reposProvider).settings.set('app.config', next);
    // النبضة بعد الإطار — إشعار وسط بناء طبقة الحوار يستأنف اشتراكات
    // موقوفة فيرمي تأكيد Riverpod (النمط المعتمد في المشروع).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(configRevProvider.notifier).state++;
    });
    setState(() {});
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── القائمة المرئية: مفاتيح الإعدادات − المحذوف، + ترشيح العزل ──
  // م-عزل الهوية — القراءة المتدرجة بهاتف الهوية (سطل «اسم|هاتف») + الاسم
  // القديم: صورُ السميّ الجديدة (تحت هاتفه) لا تظهر هنا، والقديمة تبقى.
  List<String> _visibleKeys(Map<String, Object?> cfg) => isolationFilteredKeys(
    cfg,
    filterDeletedKeys(
      ref.read(localDbProvider),
      xrayKeysFor(cfg, widget.patientName, phone: widget.phone),
    ),
    widget.clinic,
  );

  /// م39 — مصدر الصور: ورقة سفلية بخيارين (توأم خيارات النظام التي
  /// يعرضها input type=file في الأصل): «من المعرض» أو «من الملفات».
  Future<XrayPick?> _pickSource() {
    // نسخة الكمبيوتر: الخياران في حوار مركزي بدل الورقة السفلية —
    // مسار الهاتف أدناه كما هو حرفياً.
    if (isDesktopUi(context)) {
      return showDesktopDialog<XrayPick>(
        context,
        title: 'مصدر الصور',
        width: 380,
        builder: _pickBody,
      );
    }
    return showModalBottomSheet<XrayPick>(
      context: context,
      showDragHandle: true,
      builder: _pickBody,
    );
  }

  Widget _pickBody(BuildContext sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('xr-src-gallery'),
            leading: const Icon(
              Icons.photo_library_rounded,
              color: BrandColors.brand600,
            ),
            title: const Text(
              'من المعرض',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'صور الجهاز — اختيار متعدد',
              style: TextStyle(fontSize: 11.5),
            ),
            onTap: () =>
                Navigator.pop(sheetCtx, ref.read(xrayGalleryPickProvider)),
          ),
          ListTile(
            key: const Key('xr-src-files'),
            leading: const Icon(
              Icons.folder_open_rounded,
              color: BrandColors.gold,
            ),
            title: const Text(
              'من الملفات',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'مستندات وملفات الجهاز',
              style: TextStyle(fontSize: 11.5),
            ),
            onTap: () =>
                Navigator.pop(sheetCtx, ref.read(xrayFilePickProvider)),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );

  // ── الرفع بدلالات anyQueued: متصل ⇒ تصريف فوري ──
  Future<void> _upload() async {
    final source = await _pickSource();
    if (source == null || !mounted) return;
    // م127 — إضافة صور الأشعة ضمن صلاحية إضافة الزيارات.
    if (!gateStaff(context, 'records.add')) return;
    final picked = await source();
    if (picked.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لم تُختر صور — إن رُفض الإذن فامنح التطبيق الوصول '
              'للصور من إعدادات النظام',
            ),
          ),
        );
      }
      return;
    }
    setState(() => uploading = true);
    final store = ref.read(xrayStoreProvider);
    // م134 — حصة التخزين: نُحدِّث الحصة من الخادم عند الاتصال، ثم نمنع
    // الإدخال إن كانت ممتلئةً أصلاً — قبل أي معالجة. الحجب عند 100٪ فقط؛
    // 80/90 تحذيرٌ في الإعدادات لا منع هنا.
    final meter = ref.read(storageMeterProvider);
    if (ref.read(syncContextProvider).isOnline()) {
      await meter.refreshQuota();
    }
    if (!mounted) return;
    if (meter.check(0).usedBytes >= meter.quotaBytes) {
      setState(() => uploading = false);
      await _showStorageFullDialog(meter);
      return;
    }
    var cfg = Map<String, Object?>.from(ref.read(appConfigProvider));
    var failed = 0;
    var skippedFull = 0;
    // مجموع الدفعة التراكمي فوق المستهلَك الحالي — فلا تتجاوز الدفعةُ كلها
    // الحصة. الحجم المُلتقَط (قبل التصغير) تقديرٌ تحفّظي آمن؛ المحاسبة
    // النهائية بالبايتات المرفوعة فعلاً في خط الأنابيب.
    final baseUsed = meter.usedBytes;
    final quota = meter.quotaBytes;
    var pending = 0;
    for (final (name, bytes) in picked) {
      if (baseUsed + pending + bytes.length > quota) {
        skippedFull++;
        continue;
      }
      try {
        // الوسم بالعيادة دائم التفعيل (المرحلة H) — الترشيح وحده خلف العلم.
        // م-عزل الهوية — الهاتف يُختم على الصف (معرّف هوياتي) والمعرض
        // (سطل «اسم|هاتف») فتُعزل صورةُ السميّ عن سميّه.
        final r = store.ingest(
          widget.patientName,
          name,
          bytes,
          clinic: widget.clinic,
          phone: widget.phone,
        );
        cfg = addXrayKeyToConfig(
          cfg,
          widget.patientName,
          r.key,
          name,
          clinic: widget.clinic,
          phone: widget.phone,
        );
        pending += bytes.length;
      } catch (_) {
        failed++;
      }
    }
    _writeConfig(cfg);
    if (skippedFull > 0 && mounted) {
      await _showStorageFullDialog(meter, skipped: skippedFull);
    }
    // متصل ⇒ تصريف الرفع فوراً؛ ما بقي معلقاً يقرر الرسالة (anyQueued).
    var anyQueued = true;
    final pipeline = ref.read(xrayPipelineProvider);
    if (pipeline != null && ref.read(syncContextProvider).isOnline()) {
      try {
        final r = await pipeline.drainUploads();
        anyQueued = r.kept > 0;
      } catch (_) {
        /* يبقى معلقاً — أفضل جهد */
      }
    }
    if (!mounted) return;
    setState(() => uploading = false);
    _snack(
      failed > 0
          ? 'خطأ في رفع الصورة'
          : anyQueued
          ? 'تم حفظ الصور — سيتم رفعها تلقائياً عند الاتصال'
          : 'تم رفع صور الأشعة بنجاح',
    );
  }

  /// م134 — حوار «التخزين ممتلئ»: يشرح الخيارين (حذف صور قديمة أو ترقية
  /// الاشتراك) — والرفع يعود تلقائياً بمجرد تحرّر مساحة (الفحص يُعاد في كل
  /// محاولة). [skipped] > 0 يعني أن بعض صور الدفعة رُفضت لا الدفعة كلها.
  Future<void> _showStorageFullDialog(
    StorageMeter meter, {
    int skipped = 0,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('storage-full-dialog'),
        title: const Text('التخزين ممتلئ', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              skipped > 0
                  ? 'رُفعت الصور التي تسع، وتعذّر قبول $skipped منها لامتلاء '
                        'مساحة التخزين.'
                  : 'لا مساحة كافية لرفع صور أشعة جديدة.',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Text(
              'المستهلك ${humanBytesAr(meter.usedBytes)} من '
              '${humanBytesAr(meter.quotaBytes)}.',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF6B7E77),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'يمكنك:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              '• حذف صور أشعة قديمة لتحرير مساحة.\n'
              '• أو ترقية الاشتراك لزيادة الحصة.',
              style: TextStyle(fontSize: 12.5, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  // ── حذف مفرد (onXrayDelete) ──
  //
  // م142 — الحذف مؤجَّل خلف نافذة «تراجع»: عند النقر نعرض شريطاً «سيُحذف بعد
  // N ثوانٍ» بزر تراجع، ونؤجّل الحذف الفعلي حتى ينقضي المؤقت. التراجع يُلغي
  // المؤقت فلا يُحذف شيء (لم يُزَل بعد). N=0 يعني حذفاً فورياً بلا شريط.
  void _delete(String key) {
    // م127 — حذف صور الأشعة ضمن صلاحية حذف السجلات.
    if (!gateStaff(context, 'records.delete')) return;
    _scheduleDelete(
      [key],
      onCommit: () => _snack('تم حذف الصورة'),
    );
  }

  // ── حذف جماعي (deleteSelectedXrays): كتابة إعدادات واحدة ──
  void _deleteSelected(List<String> keys) {
    // م142 — كانت البوابة غائبة عن الحذف الجماعي (موجودة في المفرد): نضيفها.
    if (!gateStaff(context, 'records.delete')) return;
    final picked = [
      for (final i in selected)
        if (i >= 0 && i < keys.length) keys[i],
    ];
    if (picked.isEmpty) return;
    setState(() {
      msMode = false;
      selected.clear();
    });
    _scheduleDelete(
      picked,
      onCommit: () => _snack('تم حذف ${picked.length} صورة'),
    );
  }

  /// م142 — جدولة حذفٍ مؤجَّل خلف نافذة التراجع (أو فوري عند N=0). عند
  /// الانقضاء يُنفَّذ [_commitDelete] لكل المفاتيح دفعةً واحدة ثم [onCommit].
  void _scheduleDelete(List<String> keys, {required VoidCallback onCommit}) {
    if (keys.isEmpty) return;
    final secs = _undoSecs();
    if (secs <= 0) {
      // معطَّلة ⇒ حذفٌ فوري بلا شريط تراجع.
      _commitDelete(keys);
      onCommit();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    late final Timer timer;
    timer = Timer(Duration(seconds: secs), () {
      _pendingDeletes.remove(timer);
      if (!mounted) return;
      // نزيل شريط «سيُحذف بعد N ثوانٍ» قبل رسالة التأكيد كي تظهر الأخيرة فوراً
      // بدل أن تصطف خلف شريطٍ لا يزال يتلاشى.
      messenger.clearSnackBars();
      _commitDelete(keys);
      onCommit();
    });
    _pendingDeletes.add(timer);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('سيُحذف بعد $secs ثوانٍ'),
          duration: Duration(seconds: secs),
          action: SnackBarAction(
            label: 'تراجع',
            onPressed: () {
              // التراجع: إلغاء المؤقت فقط — لم يُحذف شيء بعد.
              if (_pendingDeletes.remove(timer)) timer.cancel();
            },
          ),
        ),
      );
  }

  /// م142 — الحذف الفعلي (بعد انقضاء نافذة التراجع أو فوراً عند N=0): إزالة
  /// مفاتيح المعرض من config بكتابةٍ واحدة + حذف محلي + تحرير الحصة + حارس
  /// المحذوف + طابور حذف R2، ثم تصريفٌ فوري لطابور R2 عند الاتصال كي يُحذف
  /// الكائن الآن لا في مزامنة الثلاثين ثانية القادمة، مع تبليغ الخادم.
  void _commitDelete(List<String> keys) {
    if (keys.isEmpty) return;
    var cfg = Map<String, Object?>.from(ref.read(appConfigProvider));
    for (final key in keys) {
      // م-عزل الهوية — الحذف عابرٌ لسطلي الهوية والاسم القديم (بالقيمة).
      cfg = removeXrayKeyFromConfig(cfg, widget.patientName, key,
          phone: widget.phone);
    }
    final store = ref.read(xrayStoreProvider);
    final db = ref.read(localDbProvider);
    final meter = ref.read(storageMeterProvider); // م134
    for (final key in keys) {
      store.deleteXray(key);
      meter.removeKey(key); // تحرير مساحة الحصة (نقصٌ دقيق)
      markXrayDeleted(db, key); // حارس المحذوف (لا بعث عبر دمج الإعدادات)
      enqueuePendingDelete(db, key); // طابور حذف R2
    }
    _writeConfig(cfg);
    unawaited(meter.reportUp());
    // متصل ⇒ تصريف طابور الحذف فوراً (drainNow يشغّل drainDeletes داخلياً)
    // فيُحذف كائن R2 الآن؛ أوفلاين يبقى المفتاح مصفوفاً ويُصرَّف عند عودة
    // الاتصال (reconnectKick القائم). لا يُنزع مفتاح مصفوف إلا بعد نجاح R2.
    if (ref.read(syncContextProvider).isOnline()) {
      unawaited(ref.read(xrayUploadQueueProvider)?.drainNow() ?? Future.value());
    }
  }

  void _saveRename(String key) {
    final cfg = Map<String, Object?>.from(ref.read(appConfigProvider));
    _writeConfig(renameXrayInConfig(cfg, key, renameCtl.text));
    setState(() => editingKey = null);
    _snack('تم حفظ الاسم');
  }

  void _openViewer(List<String> keys, int index) {
    final store = ref.read(xrayStoreProvider);
    final cfg = ref.read(appConfigProvider);
    // م79 — تسجيل الاطّلاع على صورة أشعة.
    //
    // يُسجَّل عند **فتح العارض** لا عند كل تنقّل بين الصور داخله: التنقّل
    // بالسهم يُنتج عشرات القيود للجلسة الواحدة فيغرق السجلّ، والحدث
    // المعتبَر هو أن مستخدماً فتح أشعة هذا المريض في هذا الوقت.
    recordAudit(
      ref.read(localDbProvider),
      action: AuditAction.viewXray,
      entity: 'xrays',
      entityId: index >= 0 && index < keys.length ? keys[index] : null,
      detail: {'count': keys.length},
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XrayViewerScreen(
          keys_: keys,
          startIndex: index,
          bytesOf: store.fullImageBytes,
          nameOf: (k) {
            final n = '${xrayMetaFor(cfg, k)['name'] ?? ''}';
            return n.isEmpty ? 'أشعة' : n;
          },
          onDelete: _delete,
        ),
      ),
    );
  }

  // ── التحديد المتعدد (ضغط مطوّل 500ms) ──
  void _enterMs(int i) => setState(() {
    msMode = true;
    selected
      ..clear()
      ..add(i);
  });

  void _toggleSelect(int i) => setState(() {
    if (!selected.remove(i)) selected.add(i);
    if (selected.isEmpty) msMode = false;
  });

  /// تاريخ عربي — توأم toLocaleDateString('ar'): «٢٧ يوليو ٢٠٢٦».
  String _arDateLabel(Map<String, Object?> meta) {
    final ts = meta['createdAt'];
    if (ts is! num || ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String n(int v) => '$v'.split('').map((c) => ar[int.parse(c)]).join();
    return '${n(d.day)} ${months[d.month - 1]} ${n(d.year)}';
  }

  // ── مصغرة بثلاث حالات: صورة / سبينر استرجاع / فشل أحمر ──
  Widget _thumb(String key, {double size = 52, double radius = 8}) {
    final bytes = ref.read(xrayStoreProvider).thumbnailBytes(key);
    if (bytes != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: BrandColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final restorer = ref.read(xrayThumbRestorerProvider);
    final online = ref.read(syncContextProvider).isOnline();
    // بلا عامل R2 لا استرجاع ممكناً ⇒ حالة الفشل مباشرة.
    var failedState = restorer == null;
    if (restorer != null) {
      restorer.request(key, online: online);
      failedState = restorer.isFailed(key);
    }
    if (failedState) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(239, 68, 68, .08),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: BrandColors.line),
        ),
        child: const Icon(
          Icons.broken_image_outlined,
          size: 16,
          color: Color.fromRGBO(239, 68, 68, .5),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(27, 94, 71, .08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: BrandColors.line),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color.fromRGBO(27, 94, 71, .5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(xrayVersionProvider); // نبضات الاسترجاع الخلفي
    final cfg = ref.watch(appConfigProvider);
    final keys = _visibleKeys(cfg);
    final details = '${cfg['xrayViewMode']}' == 'details';
    final xraysRepo = ref.watch(reposProvider).xrays;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(27, 94, 71, .04),
        border: Border.all(color: const Color.fromRGBO(27, 94, 71, .13)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط التحديد المتعدد / الترويسة ──
          if (msMode)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(239, 68, 68, .06),
                border: Border.all(
                  color: const Color.fromRGBO(239, 68, 68, .15),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} محددة',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.brand700,
                      ),
                    ),
                  ),
                  _msBtn(
                    key: const Key('xray-ms-del'),
                    label: 'حذف',
                    bg: const Color.fromRGBO(239, 68, 68, .15),
                    border: const Color.fromRGBO(239, 68, 68, .3),
                    color: const Color(0xFFF87171),
                    onTap: () => _deleteSelected(keys),
                  ),
                  const SizedBox(width: 6),
                  _msBtn(
                    key: const Key('xray-ms-cancel'),
                    label: 'إلغاء',
                    bg: BrandColors.ink.withValues(alpha: .04),
                    border: BrandColors.line,
                    color: BrandColors.brand700,
                    onTap: () => setState(() {
                      msMode = false;
                      selected.clear();
                    }),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Opacity(
                      opacity: .55,
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            size: 11,
                            color: BrandColors.ink,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'صور الأشعة (${keys.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BrandColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // مبدّل النمط التوأم — xray-seg.
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: BrandColors.ink.withValues(alpha: .04),
                      border: Border.all(
                        color: BrandColors.ink.withValues(alpha: .08),
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _segBtn(
                          key: const Key('xray-seg-grid'),
                          icon: Icons.grid_view_rounded,
                          on: !details,
                          onTap: () => _setViewMode(cfg, 'grid'),
                        ),
                        const SizedBox(width: 2),
                        _segBtn(
                          key: const Key('xray-seg-details'),
                          icon: Icons.view_list_rounded,
                          on: details,
                          onTap: () => _setViewMode(cfg, 'details'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // ── المحتوى ──
          if (keys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Opacity(
                opacity: .55,
                child: Text(
                  'لا توجد صور أشعة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: BrandColors.ink),
                ),
              ),
            )
          else if (!details)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < keys.length; i++)
                    GestureDetector(
                      key: Key('xray-thumb-$i'),
                      onTap: () =>
                          msMode ? _toggleSelect(i) : _openViewer(keys, i),
                      onLongPress: () => _enterMs(i),
                      child: Stack(
                        children: [
                          _thumb(keys[i]),
                          if (msMode)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                key: Key('xray-check-$i'),
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: selected.contains(i)
                                      ? const Color.fromRGBO(27, 94, 71, .9)
                                      : Colors.white.withValues(alpha: .7),
                                  border: Border.all(
                                    color: selected.contains(i)
                                        ? BrandColors.brand
                                        : Colors.black.withValues(alpha: .3),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: selected.contains(i)
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 13,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  for (var i = 0; i < keys.length; i++)
                    _detRow(cfg, xraysRepo, keys, i),
                ],
              ),
            ),

          // ── الرفع ──
          if (uploading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(27, 94, 71, .12),
                border: Border.all(color: const Color.fromRGBO(27, 94, 71, .3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BrandColors.brand700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'جاري التحميل...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.brand700,
                    ),
                  ),
                ],
              ),
            )
          else
            CustomPaint(
              painter: _DashedRRectPainter(
                color: const Color.fromRGBO(27, 94, 71, .25),
                radius: 14,
                strokeWidth: 2,
              ),
              child: Material(
                color: const Color.fromRGBO(27, 94, 71, .04),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: const Key('xray-upload'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: _upload,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.upload_rounded,
                          size: 14,
                          color: BrandColors.brand700,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'إرفاق صور أشعة',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.brand700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setViewMode(Map<String, Object?> cfg, String mode) {
    if ('${cfg['xrayViewMode']}' != mode) {
      _writeConfig({...cfg, 'xrayViewMode': mode});
    }
  }

  Widget _segBtn({
    required Key key,
    required IconData icon,
    required bool on,
    required VoidCallback onTap,
  }) => Material(
    color: on ? const Color.fromRGBO(27, 94, 71, .95) : Colors.transparent,
    borderRadius: BorderRadius.circular(7),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 26,
        child: Icon(
          icon,
          size: 15,
          color: on ? Colors.white : const Color(0xFF6B7280),
        ),
      ),
    ),
  );

  Widget _msBtn({
    required Key key,
    required String label,
    required Color bg,
    required Color border,
    required Color color,
    required VoidCallback onTap,
  }) => Material(
    color: bg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: border),
    ),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    ),
  );

  /// أزرار العرض التفصيلي المربعة — xray-det-btn التوأم.
  Widget _detBtn({
    Key? key,
    required Widget child,
    required VoidCallback onTap,
    Color? bg,
    Color? border,
  }) => Material(
    color: bg ?? BrandColors.ink.withValues(alpha: .03),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: border ?? BrandColors.ink.withValues(alpha: .08)),
    ),
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(width: 28, height: 28, child: Center(child: child)),
    ),
  );

  /// صف العرض التفصيلي — xray-det-row التوأم.
  Widget _detRow(
    Map<String, Object?> cfg,
    dynamic xraysRepo,
    List<String> keys,
    int i,
  ) {
    final key = keys[i];
    final meta = xrayMetaFor(cfg, key);
    final row = xraysRepo.getById(key);
    final uploaded = '${row?['upload_status']}' == 'uploaded';
    final name = '${meta['name'] ?? ''}';
    final date = _arDateLabel(meta);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(27, 94, 71, .04),
        border: Border.all(color: const Color.fromRGBO(27, 94, 71, .1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _openViewer(keys, i),
            child: _thumb(key, size: 48, radius: 10),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: editingKey == key
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('xray-rename'),
                          controller: renameCtl,
                          autofocus: true,
                          maxLength: 60,
                          style: const TextStyle(
                            fontSize: 13,
                            color: BrandColors.brand700,
                          ),
                          onSubmitted: (_) => _saveRename(key),
                          decoration: InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: 'اسم الصورة',
                            filled: true,
                            fillColor: BrandColors.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color.fromRGBO(17, 74, 56, .45),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color.fromRGBO(17, 74, 56, .45),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _detBtn(
                        key: const Key('xray-rename-save'),
                        bg: const Color.fromRGBO(34, 197, 94, .12),
                        border: const Color.fromRGBO(34, 197, 94, .25),
                        onTap: () => _saveRename(key),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _detBtn(
                        key: const Key('xray-rename-cancel'),
                        onTap: () => setState(() => editingKey = null),
                        child: Text(
                          '✕',
                          style: TextStyle(
                            fontSize: 12,
                            color: BrandColors.mut,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'أشعة' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.brand700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (date.isNotEmpty) ...[
                            Opacity(
                              opacity: .5,
                              child: Text(
                                date,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: BrandColors.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          // شارة الحالة — xray-badge-ok / xray-badge-wait.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: uploaded
                                  ? const Color.fromRGBO(34, 197, 94, .15)
                                  : const Color.fromRGBO(234, 179, 8, .15),
                              border: Border.all(
                                color: uploaded
                                    ? const Color.fromRGBO(34, 197, 94, .25)
                                    : const Color.fromRGBO(234, 179, 8, .25),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  uploaded
                                      ? Icons.check_rounded
                                      : Icons.schedule_rounded,
                                  size: 9,
                                  color: uploaded
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFB8860B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  uploaded ? 'مرفوعة' : 'بانتظار الرفع',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: uploaded
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFB8860B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          if (editingKey != key) ...[
            const SizedBox(width: 6),
            _detBtn(
              key: Key('xray-rename-btn-$i'),
              onTap: () => setState(() {
                editingKey = key;
                renameCtl.text = name;
              }),
              child: const Icon(
                Icons.edit_rounded,
                size: 14,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 4),
            _detBtn(
              key: Key('xray-del-btn-$i'),
              bg: const Color.fromRGBO(239, 68, 68, .12),
              border: const Color.fromRGBO(239, 68, 68, .25),
              onTap: () => _delete(key),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: Color(0xFFF87171),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// حد متقطع لمستطيل مدوّر — زر الرفع «إرفاق صور أشعة» التوأم
/// (border: 2px dashed).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  static const double dash = 6;
  static const double gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
