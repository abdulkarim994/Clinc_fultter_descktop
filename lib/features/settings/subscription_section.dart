/// المرحلة د — قسم «الاشتراك والترخيص» في إعدادات العيادة.
///
/// نافذة المستخدم على ترخيصه: الخطة والحالة والتواريخ والأيام المتبقية،
/// حدود العيادات/الأجهزة المستخدَمة مقابل المسموح، شريط التخزين بتنبيهات
/// 80/90/95/100٪، عدد الصور والإصدار ورقم الكود وآخر تحقق/مزامنة، ورسائل
/// انتهاء التجربة/الاشتراك مع تجديدٍ وترقيةٍ بالكود، ومقارنة الباقات.
///
/// كل الأرقام من مصدرها الحق: verify_license (حالة/خطة/حدود)، get_my_subscription
/// (تواريخ/كود/آخر تحقق)، StorageMeter (التخزين الحيّ)، وapp.config (العيادات).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/app_build.dart' show kAppStage;
import '../../core/theme/app_theme.dart' show BrandColors;
import '../../data/sync/transport.dart' show LicenseTransport;
import '../../features/auth/license_service.dart';
import '../../features/xrays/storage_meter.dart';

class SubscriptionSection extends ConsumerStatefulWidget {
  const SubscriptionSection({super.key});
  @override
  ConsumerState<SubscriptionSection> createState() =>
      _SubscriptionSectionState();
}

class _SubscriptionSectionState extends ConsumerState<SubscriptionSection> {
  LicenseSnapshot? _snap;
  Map<String, Object?> _sub = const {};
  List<Map<String, Object?>> _plans = const [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final svc = ref.read(licenseServiceProvider);
      final snap = await svc.evaluate();
      // حصة/استهلاك محدّثان قبل العرض.
      await ref.read(storageMeterProvider).refreshFromServer();
      final t = ref.read(transportProvider);
      Map<String, Object?> sub = const {};
      List<Map<String, Object?>> plans = const [];
      // تثبيت النوع في متغيّرٍ محلّي: الترقية عبر await قد تضيع، فنحتفظ
      // بمرجعٍ مُرقّى صريح.
      final lic = t is LicenseTransport ? t as LicenseTransport : null;
      if (lic != null) {
        try {
          sub = await lic.getMySubscription();
        } catch (_) {}
        try {
          plans = await lic.listPublicPlans();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _sub = sub;
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل بيانات الاشتراك: $e';
        _loading = false;
      });
    }
  }

  // ── مساعدات العرض ──────────────────────────────────────────────────────────
  DateTime? _t(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
  String _d(DateTime? t) => t == null ? '—' : t.toString().substring(0, 10);
  String _dt(DateTime? t) => t == null ? '—' : t.toString().substring(0, 16);

  ({String label, Color color}) _statusChip(String s) => switch (s) {
    'active' => (label: 'نشط', color: BrandColors.brand),
    'trial' => (label: 'تجريبي', color: BrandColors.gold),
    'expired' => (label: 'منتهٍ', color: const Color(0xFFC0392B)),
    'frozen' => (label: 'مجمَّد', color: BrandColors.goldDark),
    'banned' => (label: 'محظور', color: const Color(0xFFC0392B)),
    _ => (label: 'غير مفعّل', color: const Color(0xFF6B7E77)),
  };

  int _clinicCount() {
    final cfg = ref.read(reposProvider).settings.get('app.config');
    if (cfg is Map && cfg['clinics'] is List) {
      return (cfg['clinics'] as List).length;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // ملاحظة تخطيط حرجة: هذا الجسم يُستضاف **داخل ListView** في شاشة الإعدادات
    // (children:[section.body(cfg)])، فيجب ألا يُعيد ListView (ارتفاع غير محدود
    // ⇒ فراغٌ صامت في نسخة الإصدار). كل الحالات تُعيد Column/ارتفاعاً محدوداً.
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final snap = _snap!;
    final meter = ref.read(storageMeterProvider);
    final status = '${_sub['status'] ?? snap.status}';
    final chip = _statusChip(status);
    final expires = _t(_sub['expires_at']) ?? snap.expiresAt;
    final starts = _t(_sub['starts_at']);
    final daysLeft = expires?.difference(DateTime.now()).inDays;
    final planName = '${_sub['plan_name'] ?? ''}'.isNotEmpty
        ? '${_sub['plan_name']}'
        : (snap.planCode.isEmpty ? '—' : snap.planCode);
    final usedClinics = _clinicCount();
    final maxClinics = snap.maxClinics;
    final deviceCount = int.tryParse('${_sub['device_count'] ?? ''}') ?? 0;
    final maxDevices = snap.maxDevices;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 30),
      child: Column(
        key: const Key('subscription-body'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusMessages(status, snap, daysLeft),
          _card(
            title: 'الخطة الحالية',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        planName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _chip(chip.label, chip.color),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    _kv(
                      'نوع الاشتراك',
                      _sub['trial'] == true ? 'تجريبي' : 'مدفوع',
                    ),
                    _kv('تاريخ التفعيل', _d(starts)),
                    _kv('تاريخ الانتهاء', _d(expires)),
                    _kv(
                      'المتبقّي',
                      expires == null
                          ? 'دائم'
                          : (daysLeft != null && daysLeft >= 0
                                ? '$daysLeft يوماً'
                                : 'منتهٍ'),
                    ),
                    _kv(
                      'العيادات',
                      '$usedClinics / ${maxClinics == 0 ? '∞' : maxClinics}',
                    ),
                    _kv(
                      'الأجهزة',
                      '$deviceCount / ${maxDevices == 0 ? '∞' : maxDevices}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _storageCard(meter),
          const SizedBox(height: 10),
          _card(
            title: 'تفاصيل الترخيص',
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _kv('رقم الكود', '${_sub['code_prefix'] ?? '—'}'),
                _kv('عدد الصور', '${meter.fileCount}'),
                _kv('إصدار التطبيق', kAppStage),
                _kv('آخر تحقق', _dt(_t(_sub['last_verified']))),
                _kv('آخر مزامنة', _dt(_t(_sub['last_sync']))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _actions(status),
          const SizedBox(height: 14),
          _comparison(snap.planCode),
        ],
      ),
    );
  }

  // ── رسائل الحالة (تجربة/انتهاء) ─────────────────────────────────────────────
  Widget _statusMessages(String status, LicenseSnapshot snap, int? daysLeft) {
    final widgets = <Widget>[];
    if (status == 'expired' || status == 'none') {
      widgets.add(
        _banner(
          'انتهى اشتراكك — جدّده بكودٍ جديد لمواصلة المزامنة والرفع.',
          const Color(0xFFC0392B),
          Icons.error_rounded,
        ),
      );
    } else if (status == 'trial') {
      widgets.add(
        _banner(
          daysLeft != null && daysLeft >= 0
              ? 'أنت في الفترة التجريبية — تنتهي خلال $daysLeft يوماً. فعّل بكودٍ قبل انتهائها.'
              : 'انتهت فترتك التجريبية — أدخل كود تفعيل للمتابعة.',
          BrandColors.goldDark,
          Icons.hourglass_bottom_rounded,
        ),
      );
    } else if (status == 'frozen') {
      widgets.add(
        _banner(
          'اشتراكك مجمَّد من الإدارة — تواصل مع مزوّد الخدمة.',
          BrandColors.goldDark,
          Icons.ac_unit_rounded,
        ),
      );
    } else if (daysLeft != null && daysLeft <= 7 && daysLeft >= 0) {
      widgets.add(
        _banner(
          'اشتراكك ينتهي خلال $daysLeft يوماً — جدّده مبكراً لتفادي الانقطاع.',
          BrandColors.goldDark,
          Icons.schedule_rounded,
        ),
      );
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(children: [...widgets, const SizedBox(height: 10)]);
  }

  // ── شريط التخزين بتنبيهات العتبات ───────────────────────────────────────────
  Widget _storageCard(StorageMeter meter) {
    final used = meter.usedBytes;
    final quota = meter.quotaBytes;
    final ratio = quota <= 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();
    final (Color barColor, String? alert) = switch (ratio) {
      >= 1.0 => (
        const Color(0xFFC0392B),
        'التخزين ممتلئ — احذف صوراً قديمة أو رقِّ خطتك لمواصلة الرفع.',
      ),
      >= 0.95 => (
        const Color(0xFFC0392B),
        'تجاوزت 95٪ من مساحتك — الرفع سيتوقف قريباً.',
      ),
      >= 0.9 => (BrandColors.goldDark, 'تجاوزت 90٪ من مساحتك.'),
      >= 0.8 => (BrandColors.gold, 'تجاوزت 80٪ من مساحتك.'),
      _ => (BrandColors.brand, null),
    };
    return _card(
      title: 'التخزين',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${humanBytesAr(used)} من ${humanBytesAr(quota)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text('$pct٪', style: TextStyle(fontSize: 13.5, color: barColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              key: const Key('sub-storage-bar'),
              value: ratio == 0 ? 0.02 : ratio,
              minHeight: 12,
              backgroundColor: barColor.withValues(alpha: .15),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'المتبقّي: ${humanBytesAr((quota - used).clamp(0, quota))}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7E77)),
          ),
          if (alert != null) ...[
            const SizedBox(height: 8),
            _banner(alert, barColor, Icons.warning_amber_rounded),
          ],
        ],
      ),
    );
  }

  // ── أزرار التجديد والترقية (بالكود) ─────────────────────────────────────────
  Widget _actions(String status) {
    final expired = status == 'expired' || status == 'none';
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('sub-renew'),
            onPressed: _busy ? null : () => _enterCode(upgrade: false),
            style: FilledButton.styleFrom(
              backgroundColor: expired
                  ? const Color(0xFFC0392B)
                  : BrandColors.brand,
              minimumSize: const Size(0, 46),
            ),
            icon: const Icon(Icons.autorenew_rounded, size: 18),
            label: Text(expired ? 'تجديد الاشتراك' : 'تمديد/تجديد'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('sub-upgrade'),
            onPressed: _busy ? null : () => _enterCode(upgrade: true),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            icon: const Icon(Icons.upgrade_rounded, size: 18),
            label: const Text('ترقية الخطة'),
          ),
        ),
      ],
    );
  }

  Future<void> _enterCode({required bool upgrade}) async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          upgrade ? 'ترقية الخطة بكود' : 'تجديد الاشتراك بكود',
          style: const TextStyle(fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              upgrade
                  ? 'أدخل كود الباقة الأعلى الذي حصلت عليه من مزوّد الخدمة.'
                  : 'أدخل كود التفعيل الجديد لتمديد اشتراكك.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7E77)),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('sub-code-field'),
              controller: ctl,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: 'DENT-XXXX-XXXX-XXXX',
                hintTextDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('sub-code-submit'),
            onPressed: () => Navigator.pop(d, ctl.text.trim()),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(licenseServiceProvider).activate(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التفعيل — حُدِّث اشتراكك.')),
      );
      await _load();
    } on LicenseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── مقارنة الباقات ──────────────────────────────────────────────────────────
  Widget _comparison(String currentCode) {
    if (_plans.length < 2) return const SizedBox.shrink();
    int f(Map<String, Object?> p, String k) {
      final feats = p['features'];
      if (feats is Map) return int.tryParse('${feats[k] ?? ''}') ?? 0;
      return 0;
    }

    return _card(
      title: 'مقارنة الباقات',
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(flex: 2, child: Text('الباقة', style: _thStyle)),
              Expanded(
                child: Text(
                  'تخزين',
                  style: _thStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'عيادات',
                  style: _thStyle,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'أجهزة',
                  style: _thStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const Divider(),
          for (final p in _plans)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        if ('${p['code']}' == currentCode)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(end: 4),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: BrandColors.brand,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            '${p['name'] ?? p['code']}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: '${p['code']}' == currentCode
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      mbLabelAr(f(p, 'storage_mb')),
                      style: _tdStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${f(p, 'max_clinics')}',
                      style: _tdStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${f(p, 'max_devices')}',
                      style: _tdStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── لبنات ───────────────────────────────────────────────────────────────────
  static const _thStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    color: Color(0xFF6B7E77),
  );
  static const _tdStyle = TextStyle(fontSize: 12.5);

  Widget _card({required String title, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE3E8E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _kv(String k, String v) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          k,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7E77)),
        ),
        const SizedBox(height: 2),
        Text(
          v,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    ),
  );

  Widget _banner(String text, Color color, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.5, color: color),
          ),
        ),
      ],
    ),
  );
}

/// تسمية تخزين مضغوطة بالميغابايت (0 = بلا حدّ) — للمقارنة.
String mbLabelAr(int mb) {
  if (mb <= 0) return '∞';
  if (mb < 1024) return '$mb م.ب';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb == gb.roundToDouble() ? 0 : 1)} غ.ب';
}
