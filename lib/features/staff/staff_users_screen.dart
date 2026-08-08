/// م118 — إدارة المستخدمين والصلاحيات (للإدارة حصراً — المرحلة 1).
///
///  قائمة الموظفين ببطاقاتٍ (الاسم، اسم الدخول، الدور، الوردية، الحالة)
///  وإضافة/تعديل بورقةٍ سفلية: البيانات، الدور، الوردية، تعيين/إعادة
///  تعيين كلمة المرور، مفاتيح الصلاحيات (بقالب «موظف استعلامات» جاهز)،
///  والإيقاف بدل الحذف. كل فعلٍ يُسجَّل في سجل التدقيق.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import 'staff_session.dart';
import 'staff_store.dart';
import 'activity_log_screen.dart' show ActivityLogScreen;

/// نبضة إعادة قراءة بعد كل تعديل.
final _staffRevProvider = StateProvider<int>((ref) => 0);

class StaffUsersScreen extends ConsumerWidget {
  const StaffUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_staffRevProvider);
    final store = StaffStore(ref.watch(reposProvider).settings);
    final users = store.listAll();
    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('المستخدمون والصلاحيات'),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
        actions: [
          // م120 — سجل النشاط: من فعل ماذا ومتى.
          IconButton(
            key: const Key('staff-activity'),
            tooltip: 'سجل النشاط',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ActivityLogScreen()),
            ),
          ),
          IconButton(
            key: const Key('staff-add'),
            tooltip: 'موظف جديد',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => _editSheet(context, ref),
          ),
        ],
      ),
      body: users.isEmpty
          ? Center(
              child: Text('لا مستخدمون بعد — أضف موظفاً من الزر أعلاه.',
                  style: TextStyle(fontSize: 13, color: BrandColors.mut)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: users.length,
              itemBuilder: (_, i) => _userCard(context, ref, users[i]),
            ),
    );
  }

  Widget _userCard(BuildContext context, WidgetRef ref, Map<String, Object?> u) {
    final active = u['active'] != false;
    final admin = u['role'] == 'admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active
                ? BrandColors.line
                : BrandColors.red.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editSheet(context, ref, existing: u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: admin
                    ? const Color.fromRGBO(201, 162, 75, .16)
                    : BrandColors.surface2,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  admin
                      ? Icons.admin_panel_settings_rounded
                      : Icons.person_rounded,
                  size: 22,
                  color: admin ? BrandColors.goldDark : BrandColors.mut),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${u['name'] ?? ''}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: active
                              ? BrandColors.brandText
                              : BrandColors.mut)),
                  Text(
                      '@${u['username']}'
                      ' • ${admin ? 'إدارة' : 'موظف'}'
                      '${'${u['shift'] ?? ''}'.isEmpty ? '' : ' • ${u['shift']}'}',
                      style: TextStyle(
                          fontSize: 11, color: BrandColors.mut2)),
                ],
              ),
            ),
            if (!active)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BrandColors.red.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('موقوف',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.red)),
              ),
            Icon(Icons.chevron_left_rounded,
                size: 20, color: BrandColors.mut),
          ]),
        ),
      ),
    );
  }

  Future<void> _editSheet(BuildContext context, WidgetRef ref,
      {Map<String, Object?>? existing}) async {
    final store = StaffStore(ref.read(reposProvider).settings);
    final editing = existing != null;
    final nameC = TextEditingController(text: '${existing?['name'] ?? ''}');
    final userC =
        TextEditingController(text: '${existing?['username'] ?? ''}');
    final passC = TextEditingController();
    var role = '${existing?['role'] ?? 'staff'}';
    var shift = '${existing?['shift'] ?? ''}';
    var active = existing?['active'] != false;
    final perms = <String, bool>{
      for (final p in kStaffPerms)
        p.key: existing?['perms'] is Map
            ? (existing!['perms'] as Map)[p.key] == true
            : kReceptionistTemplate[p.key] ?? false,
    };
    String? err;

    // نسخة الكمبيوتر: محرر الموظف حوار مركزي بدل الورقة السفلية —
    // مسار الهاتف كما هو حرفياً.
    Widget staffBody(BuildContext sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setLocal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * .9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                            color: BrandColors.line,
                            borderRadius: BorderRadius.circular(4))),
                  ),
                  const SizedBox(height: 10),
                  Text(editing ? 'تعديل موظف' : 'موظف جديد',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameC,
                    decoration:
                        const InputDecoration(labelText: 'الاسم الظاهر'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: userC,
                    enabled: !editing,
                    decoration: InputDecoration(
                        labelText: 'اسم الدخول',
                        helperText:
                            editing ? 'اسم الدخول لا يتغير بعد الإنشاء' : null),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passC,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: editing
                            ? 'كلمة مرور جديدة (اتركها فارغة للإبقاء)'
                            : 'كلمة المرور'),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'staff', label: Text('موظف')),
                          ButtonSegment(value: 'admin', label: Text('إدارة')),
                        ],
                        selected: {role},
                        onSelectionChanged: (s) =>
                            setLocal(() => role = s.first),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: '', label: Text('بلا وردية')),
                          ButtonSegment(value: 'صباحي', label: Text('صباحي')),
                          ButtonSegment(value: 'مسائي', label: Text('مسائي')),
                        ],
                        selected: {shift},
                        onSelectionChanged: (s) =>
                            setLocal(() => shift = s.first),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: Text('الحساب نشط',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: BrandColors.brandText))),
                    Switch(
                        value: active,
                        onChanged: (v) => setLocal(() => active = v)),
                  ]),
                  if (role != 'admin') ...[
                    const Divider(height: 22),
                    Row(children: [
                      Expanded(
                        child: Text('الصلاحيات',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.brandText)),
                      ),
                      TextButton.icon(
                        onPressed: () => setLocal(() {
                          perms
                            ..clear()
                            ..addAll(kReceptionistTemplate);
                        }),
                        icon: const Icon(Icons.badge_rounded, size: 15),
                        label: const Text('قالب موظف استعلامات',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                    for (final p in kStaffPerms)
                      Row(children: [
                        Expanded(
                            child: Text(p.label,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: BrandColors.ink))),
                        Switch(
                          value: perms[p.key] ?? false,
                          onChanged: (v) =>
                              setLocal(() => perms[p.key] = v),
                        ),
                      ]),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('الإدارة تملك كل الصلاحيات تلقائياً.',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BrandColors.red)),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const Key('staff-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.brand600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      final nm = nameC.text.trim();
                      final un = normalizeUsername(userC.text);
                      if (nm.isEmpty || un.isEmpty) {
                        setLocal(() => err = 'أدخل الاسم واسم الدخول');
                        return;
                      }
                      if (!editing && passC.text.length < 4) {
                        setLocal(
                            () => err = 'كلمة المرور 4 محارف على الأقل');
                        return;
                      }
                      if (!editing && store.byUsername(un) != null) {
                        setLocal(() => err = 'اسم الدخول مستعمل');
                        return;
                      }
                      // حماية: لا يُوقَف/يُنزَل آخرُ حساب إدارةٍ نشط.
                      if (editing &&
                          existing['role'] == 'admin' &&
                          (role != 'admin' || !active)) {
                        final otherAdmin = store.listActive().any((x) =>
                            x['role'] == 'admin' &&
                            '${x['id']}' != '${existing['id']}');
                        if (!otherAdmin) {
                          setLocal(() =>
                              err = 'لا يمكن إيقاف أو تنزيل آخر حساب إدارة');
                          return;
                        }
                      }
                      Navigator.pop(sheetCtx, true);
                    },
                    child: Text(editing ? 'حفظ التعديلات' : 'إنشاء الموظف',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

    final saved = isDesktopUi(context)
        ? await showDesktopDialog<bool>(
            context,
            width: 520,
            builder: staffBody,
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: BrandColors.surface,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: staffBody,
          );

    if (saved != true) return;
    final id = store.upsert(
      id: editing ? '${existing['id']}' : null,
      username: normalizeUsername(userC.text),
      name: nameC.text.trim(),
      role: role,
      shift: shift,
      perms: perms,
      active: active,
    );
    if (passC.text.isNotEmpty) store.setPassword(id, passC.text);
    recordAudit(ref.read(reposProvider).db,
        action: editing ? 'staff.edit' : 'staff.add',
        entity: 'staff',
        entityId: id,
        detail: {
          'by': currentStaffName(),
          'username': normalizeUsername(userC.text),
          'role': role,
          'active': active,
          if (passC.text.isNotEmpty) 'passwordChanged': true,
        });
    ref.read(_staffRevProvider.notifier).state++;
  }
}
