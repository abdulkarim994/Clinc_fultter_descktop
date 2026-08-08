/// شاشة إثبات الميلستون صفر — دليل مرئي حي على نجاح كل فحوصات Go/No-Go.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/db/db_proof.dart';

/// Directory that hosts the SQLite file. Overridden at startup (real app:
/// application-support dir; tests: temp dir).
final dbDirProvider = Provider<String>(
  (ref) => throw UnimplementedError('dbDirProvider must be overridden'),
);

/// Runs the full Milestone-0 database proof once per app session.
final dbProofProvider = FutureProvider<DbProofReport>((ref) async {
  final dir = ref.watch(dbDirProvider);
  return runDbProof(dir);
});

class ProofScreen extends ConsumerWidget {
  const ProofScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proof = ref.watch(dbProofProvider);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Brand header (── --brand-g gradient) ──
          Container(
            decoration: const BoxDecoration(
              gradient: BrandColors.brandGradient,
            ),
            padding: const EdgeInsets.fromLTRB(20, 64, 20, 28),
            child: Column(
              children: [
                const Text(
                  'طب الأسنان الرقمي',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'نسخة Flutter — إثبات الميلستون صفر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.gold,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'م0 — إثبات ثم قرار',
                    style: TextStyle(
                      color: BrandColors.brand900,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Typography & direction card ──
                _ProofCard(
                  title: 'الخط والاتجاه',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'خط قمرة — الوزن العادي 400',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'خط قمرة — الوزن المتوسط 500',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'خط قمرة — الوزن العريض 700',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cairo fallback — نص لاتيني 123',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Divider(height: 24),
                      _CheckRow(
                        ok: isRtl,
                        label: 'اتجاه الواجهة: من اليمين إلى اليسار (RTL)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Database proof card ──
                _ProofCard(
                  title: 'قاعدة البيانات — التكافؤ مع النسخة الأصلية',
                  child: proof.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) =>
                        _CheckRow(ok: false, label: 'فشل فتح القاعدة: $e'),
                    data: (r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CheckRow(
                          ok: r.crudOk,
                          label: 'إنشاء القاعدة + إدخال واسترجاع عربي',
                        ),
                        _CheckRow(
                          ok: r.schemaOk,
                          label:
                              'الجداول العلائقية: ${r.relationalTableCount}/${r.expectedTableCount}',
                        ),
                        _CheckRow(
                          ok: r.ftsOk,
                          label: 'فهرس FTS5 العربي + المحفزات الثلاثة',
                        ),
                        _CheckRow(
                          ok: r.ftsSearchOk,
                          label: 'بحث عربي: «أحمد» تُطبَّع وتجد «أحمد الطيّب»',
                        ),
                        _CheckRow(
                          ok: r.arParityOk,
                          label: 'تطابق تطبيع الأسماء: SQL = Dart',
                        ),
                        _CheckRow(
                          ok: r.phoneParityOk,
                          label: 'تطابق تطبيع الهاتف: SQL = Dart',
                        ),
                        const Divider(height: 24),
                        Text(
                          'SQLite ${r.sqliteVersion} · user_version ${r.userVersion} · أعلام الهجرة: ${r.migrationFlags.length}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: BrandColors.ink.withValues(alpha: .6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Overall verdict banner ──
                proof.maybeWhen(
                  data: (r) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: (r.allOk && isRtl)
                          ? BrandColors.green
                          : BrandColors.red,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      (r.allOk && isRtl)
                          ? 'الميلستون صفر: كل الفحوصات ناجحة ✓'
                          : 'الميلستون صفر: توجد فحوصات متعثرة',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 20,
                  decoration: BoxDecoration(
                    color: BrandColors.gold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: BrandColors.brand900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: ok ? BrandColors.green : BrandColors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
        ],
      ),
    );
  }
}
