/// ============================================================================
///  المرحلة هـ — مركز الإشعارات داخل التطبيق (بلا Firebase/دفع)
/// ============================================================================
///
///  عند فتح التطبيق (بعد بوابة ما بعد الدخول ودخولها حالة `done`) نعرض:
///    • الإشعارات غير المقروءة نافذةً تلو نافذة (بالترتيب: الأقدم أولاً)،
///      وبعد إغلاق كلٍّ منها نعلّمه مقروءاً على الخادم — فلا يعود.
///    • ثم — إن توفّر تحديثٌ مفعَّلٌ بنسخةٍ تخالف نسخة التطبيق — نافذةَ
///      تحديثٍ دائمة بزرِّ تحميلٍ اختياريٍّ (يحكمه تفضيلٌ محليٌّ لكل جهاز).
///
///  كلُّ نداءات الشبكة أفضلُ جهدٍ (try/catch): فشلُها لا يُعطّل فتح التطبيق.
///  في الوضع المحلي (ناقلٌ لا يُنفّذ [NotificationsTransport]) لا شيء يحدث.
///
///  التفضيل «إظهار زر تحديث التطبيق» محليٌّ في `sync_meta` بمفتاح المالك —
///  نفس نمط تفضيلات القفل (lock_prefs): لا يغادر الجهاز ولا يدخل حمولة
///  المزامنة، والغياب = مفعَّل (الافتراض إظهار الزر).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/app_build.dart' show kAppStage;
import '../../core/theme/app_theme.dart' show BrandColors;
import '../../data/db/local_db.dart' show LocalDb;
import '../../data/sync/db_sync.dart' show getMetaValue, setMetaValue;
import '../../data/sync/transport.dart' show NotificationsTransport;

const String _kShowUpdateButtonKey = 'notif.show_update_button';

String _owner(LocalDb db) => db.getOwnerUid() ?? '';

/// هل يُظهَر زرُّ «تحميل التحديث» في نافذة التحديث؟ الغياب ⇒ **نعم**
/// (الافتراض إظهار الزر). تفضيلٌ محليٌّ لكل جهاز.
bool showUpdateButtonPref(LocalDb db) {
  final v = getMetaValue(db, _kShowUpdateButtonKey);
  if (v == null) return true; // الغياب = مفعَّل
  return '$v' == '1';
}

void setShowUpdateButtonPref(LocalDb db, bool enabled) {
  setMetaValue(db, _kShowUpdateButtonKey, enabled ? '1' : '0', _owner(db));
}

/// يقرأ حقلاً نصّياً من خريطة `data` الاختيارية داخل الإشعار.
String _dataString(Map<String, Object?> data, String key) {
  final v = data[key];
  return v is String ? v : (v == null ? '' : '$v');
}

/// يفتح رابطاً خارجيّاً أفضلَ جهدٍ (متصفّح النظام). فشلُ الفتح لا يُعطّل شيئاً.
Future<void> _openUrl(String url) async {
  if (url.trim().isEmpty) return;
  try {
    final uri = Uri.parse(url.trim());
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    /* أفضل جهد — رابطٌ غير صالح أو لا مُطلِق */
  }
}

/// يُعرَض مرةً واحدةً عند فتح التطبيق: تسلسل نوافذ الإشعارات غير المقروءة،
/// ثم نافذة التحديث إن توفّر. أفضلُ جهدٍ بالكامل — لا يرمي أبداً.
Future<void> showPendingNotifications(
  BuildContext context,
  WidgetRef ref,
) async {
  final t = ref.read(transportProvider);
  // الوضع المحلي (ناقلٌ لا يُنفّذ القناة) ⇒ لا شيء.
  if (t is! NotificationsTransport) return;
  final notif = t as NotificationsTransport;
  final db = ref.read(localDbProvider);

  // ١) الإشعارات غير المقروءة — بالترتيب (الأقدم أولاً).
  List<Map<String, Object?>> items = const [];
  try {
    items = await notif.getMyNotifications();
  } catch (_) {
    items = const []; // أفضل جهد — فشل الجلب يتخطّى الإشعارات
  }

  for (final n in items) {
    if (!context.mounted) return;
    final id = _dataString(n, 'id');
    final title = _dataString(n, 'title');
    final body = _dataString(n, 'body');
    final dataRaw = n['data'];
    final data = dataRaw is Map
        ? Map<String, Object?>.from(dataRaw)
        : const <String, Object?>{};
    final imageUrl = _dataString(data, 'image_url');
    final actionLabel = _dataString(data, 'action_label');
    final actionUrl = _dataString(data, 'action_url');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const Key('notif-dialog'),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    // فشل التحميل لا يكسر النافذة: نطوي الصورة بلطف.
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (body.isNotEmpty)
                Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ),
        ),
        actions: [
          if (actionLabel.isNotEmpty && actionUrl.isNotEmpty)
            TextButton(
              key: const Key('notif-action'),
              onPressed: () => _openUrl(actionUrl),
              child: Text(actionLabel),
            ),
          FilledButton(
            key: const Key('notif-done'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تم'),
          ),
        ],
      ),
    );

    // بعد إغلاق النافذة: علّم الإشعار مقروءاً (أفضل جهد) فلا يعود.
    if (id.isNotEmpty) {
      try {
        await notif.markNotificationRead(id);
      } catch (_) {
        /* أفضل جهد — يبقى غير مقروءٍ ويظهر في فتحةٍ لاحقة */
      }
    }
  }

  // ٢) تنبيه تحديث التطبيق (بلا تعليم قراءة).
  if (!context.mounted) return;
  Map<String, Object?> update = const {};
  try {
    update = await notif.getAppUpdate();
  } catch (_) {
    update = const {}; // أفضل جهد
  }
  if (!context.mounted) return;

  final enabled = update['enabled'] == true;
  final version = _dataString(update, 'version');
  final url = _dataString(update, 'url');
  final notes = _dataString(update, 'notes');
  // نُظهر النافذة فقط لتحديثٍ مفعَّلٍ بنسخةٍ غير فارغةٍ تخالف نسخة التطبيق.
  if (!enabled || version.isEmpty || version == kAppStage) return;

  final showDownload = showUpdateButtonPref(db);

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('update-dialog'),
      title: const Text('تحديث متوفّر'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الإصدار $version',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: BrandColors.brand700,
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(notes, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('لاحقاً'),
        ),
        if (showDownload)
          FilledButton(
            key: const Key('update-download'),
            onPressed: () => _openUrl(url),
            child: const Text('تحميل التحديث'),
          ),
      ],
    ),
  );
}
