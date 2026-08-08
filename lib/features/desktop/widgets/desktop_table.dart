/// ============================================================================
///  عدة الجداول المكتبية — DesktopDataTable: جدول واحد احترافي لكل الشاشات
/// ============================================================================
///
///  (قرار المالك — «ثامناً: الجداول»): كل جداول نسخة الكمبيوتر تدعم:
///  البحث الفوري · ترتيب الأعمدة · تغيير العرض بالسحب · تثبيت الأعمدة ·
///  إظهار/إخفاء الأعمدة · Pagination · تمرير احترافي · تحديد متعدد ·
///  اختصارات لوحة المفاتيح — مع Hover ونقر مزدوج وقائمة زر يمين ووسوم
///  ألوان الصفوف.
///
///  البنية: لوحان متجاوران — لوح الأعمدة **المثبتة** (يمين RTL، لا يتحرك
///  أفقياً) ولوح الأعمدة القابلة للتمرير الأفقي؛ التمرير العمودي مربوط
///  بين اللوحين بمجموعة متحكمات موصولة، وكل لوح ListView.builder بارتفاع
///  صف ثابت (itemExtent) — أي **Virtual Scrolling** حقيقي: يُبنى المرئي
///  فقط مهما بلغ عدد الصفوف.
///
///  حالة كل جدول (عرض/إخفاء/تثبيت/فرز/حجم صفحة) تُحفظ محلياً باسم
///  الجدول عبر desktop_prefs — تعود كما تركتها بعد إعادة التشغيل.
library;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../desktop_prefs.dart';
import 'context_menu.dart';
import 'tag_colors.dart';

// ── نموذج العمود ────────────────────────────────────────────────────────────

class DeskCol<T> {
  const DeskCol({
    required this.id,
    required this.label,
    required this.cell,
    this.width = 120,
    this.minWidth = 56,
    this.flex = 0,
    this.numeric = false,
    this.sortable = true,
    this.resizable = true,
    this.hideable = true,
    this.sortKey,
    this.tooltip,
  });

  final String id;
  final String label;
  final double width;
  final double minWidth;

  /// flex > 0: يتوسع العمود بنسبة flex ليملأ الفراغ حين يقلّ مجموع
  /// الأعمدة عن عرض اللوح (لا فراغات ميتة على الشاشات العريضة).
  final int flex;

  final bool numeric;
  final bool sortable;
  final bool resizable;
  final bool hideable;
  final Comparable<Object?>? Function(T row)? sortKey;
  final String? tooltip;
  final Widget Function(BuildContext context, T row) cell;

  /// عمود نصي جاهز.
  static DeskCol<T> text<T>({
    required String id,
    required String label,
    required String Function(T) value,
    double width = 120,
    double minWidth = 56,
    int flex = 0,
    bool numeric = false,
    bool sortable = true,
    Comparable<Object?>? Function(T)? sortKey,
    Color? Function(T)? color,
    FontWeight weight = FontWeight.w600,
  }) {
    return DeskCol<T>(
      id: id,
      label: label,
      width: width,
      minWidth: minWidth,
      flex: flex,
      numeric: numeric,
      sortable: sortable,
      sortKey: sortKey ?? ((r) => value(r)),
      cell: (context, r) {
        final s = value(r);
        return Text(
          s.isEmpty ? '—' : s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: numeric ? TextDirection.ltr : null,
          textAlign: numeric ? TextAlign.center : null,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: weight,
            color: color?.call(r) ?? BrandColors.ink,
            fontFeatures:
                numeric ? const [FontFeature.tabularFigures()] : null,
          ),
        );
      },
    );
  }
}

// ── متحكم الجدول (لخدمات خارجية: تركيز البحث، قراءة التحديد…) ───────────────

class DeskTableController<T> extends ChangeNotifier {
  final FocusNode searchFocus = FocusNode(debugLabel: 'desk-table-search');
  final FocusNode tableFocus = FocusNode(debugLabel: 'desk-table');

  Set<String> _selected = {};
  Set<String> get selected => _selected;

  void Function()? _clearSelectionImpl;

  /// تركيز حقل البحث (يخدم Ctrl+F من الشاشة الحاضنة).
  void focusSearch() => searchFocus.requestFocus();

  void clearSelection() => _clearSelectionImpl?.call();

  @override
  void dispose() {
    searchFocus.dispose();
    tableFocus.dispose();
    super.dispose();
  }
}

// ── مزامنة التمرير العمودي بين اللوحين ─────────────────────────────────────

class _LinkedScrollGroup {
  final List<ScrollController> _controllers = [];
  bool _syncing = false;

  ScrollController create() {
    final c = ScrollController();
    c.addListener(() {
      if (_syncing || !c.hasClients) return;
      _syncing = true;
      for (final o in _controllers) {
        if (identical(o, c) || !o.hasClients) continue;
        if ((o.offset - c.offset).abs() > .5) o.jumpTo(c.offset);
      }
      _syncing = false;
    });
    _controllers.add(c);
    return c;
  }

  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
  }
}

// ── الجدول ──────────────────────────────────────────────────────────────────

class DesktopDataTable<T> extends ConsumerStatefulWidget {
  const DesktopDataTable({
    super.key,
    required this.tableId,
    required this.columns,
    required this.rows,
    required this.rowId,
    this.controller,
    this.onOpen,
    this.onDelete,
    this.contextMenuOf,
    this.rowTagOf,
    this.onTagRows,
    this.searchText,
    this.searchHint = 'بحث فوري…',
    this.showSearch = true,
    this.toolbarLeading,
    this.toolbarTrailing,
    this.selectionActions,
    this.onSelectionChanged,
    this.defaultSortId,
    this.defaultSortAsc = false,
    this.persistSort = true,
    this.defaultPinned = const [],
    this.defaultHidden = const [],
    this.emptyTitle = 'لا صفوف',
    this.emptyHint,
    this.footer,
    this.rowHeight = 40,
    this.selectable = true,
    this.zebra = true,
  });

  final String tableId;
  final List<DeskCol<T>> columns;
  final List<T> rows;
  final String Function(T) rowId;
  final DeskTableController<T>? controller;

  /// نقر مزدوج / Enter.
  final void Function(T row)? onOpen;

  /// Delete (بعد تأكيد الشاشة) — يستقبل الصفوف المحددة أو صف التركيز.
  final void Function(List<T> rows)? onDelete;

  /// عناصر قائمة الزر الأيمن لصف.
  final List<CtxItem> Function(T row)? contextMenuOf;

  /// وسم لون الصف (معرف اللون من tag_colors) — null بلا وسم.
  final String? Function(T row)? rowTagOf;

  /// تلوين مجموعة صفوف (من قائمة السياق/شريط التحديد).
  final void Function(List<T> rows, String? tag)? onTagRows;

  /// نص البحث الفوري للصف (null يعطل حقل البحث الداخلي).
  final String Function(T row)? searchText;
  final String searchHint;
  final bool showSearch;

  /// عناصر تُحقن في شريط أدوات الجدول (فلاتر الشاشة).
  final Widget? toolbarLeading;
  final Widget? toolbarTrailing;

  /// أزرار إضافية في شريط التحديد المتعدد.
  final List<Widget> Function(List<T> rows)? selectionActions;
  final ValueChanged<Set<String>>? onSelectionChanged;

  final String? defaultSortId;
  final bool defaultSortAsc;

  /// م-تكافؤ — تعطيل حفظ الفرز بين الفتحات: جداول تطابق سلوك الهاتف
  /// (كدفتر الرئيسية: يفتح دائماً على الأحدث أولاً) تمرر false، فيبقى
  /// الفرز داخل الجلسة فقط ويعود الافتراضي عند كل فتح.
  final bool persistSort;
  final List<String> defaultPinned;
  final List<String> defaultHidden;

  final String emptyTitle;
  final String? emptyHint;

  /// شريحة حرة أسفل الجدول (فوق الترقيم) — إجماليات ونحوها.
  final Widget? footer;

  final double rowHeight;
  final bool selectable;
  final bool zebra;

  @override
  ConsumerState<DesktopDataTable<T>> createState() =>
      _DesktopDataTableState<T>();
}

class _DesktopDataTableState<T> extends ConsumerState<DesktopDataTable<T>> {
  late DeskTableController<T> _ctl;
  bool _ownsCtl = false;

  final _searchCtl = TextEditingController();
  String _query = '';

  // حالة الأعمدة (تُحمَّل من التفضيلات في أول بناء).
  final Map<String, double> _widths = {};
  final Set<String> _hidden = {};
  final List<String> _pinned = [];
  // ترتيب الأعمدة المخصَّص (قرار المالك — إدارة ترتيب الأعمدة). فارغٌ =
  // ترتيب الإعلان الأصلي. المعرّفات غير المذكورة تُلحَق بذيله بترتيبها الأصلي.
  final List<String> _order = [];
  // معرّف العمود الذي تحوم فوق مقبض تحجيمه الفأرة (لإبراز المقبض).
  String? _hoverCol;
  String? _sortId;
  bool _sortAsc = true;
  int _pageSize = 50;
  int _page = 0;
  bool _loadedPrefs = false;

  // تفاعل الصفوف — التمرير بالمؤشر عبر ValueNotifier معزول: تغيّره لا
  // يعيد بناء الجدول كله بل الصفين المعنيين فقط (أهم مسار حراري: الفأرة
  // تتحرك باستمرار فوق مئات الصفوف الافتراضية).
  final ValueNotifier<int?> _hover = ValueNotifier<int?>(null);
  int _focusIndex = -1;
  int? _anchorIndex;
  Set<String> _selected = {};

  final _vGroup = _LinkedScrollGroup();
  late final ScrollController _vPinned = _vGroup.create();
  late final ScrollController _vScroll = _vGroup.create();
  final _hCtl = ScrollController();

  static const _selColWidth = 34.0;

  @override
  void initState() {
    super.initState();
    _ctl = widget.controller ?? DeskTableController<T>();
    _ownsCtl = widget.controller == null;
    _ctl._clearSelectionImpl = () => _setSelection({});
    _sortId = widget.defaultSortId;
    _sortAsc = widget.defaultSortAsc;
    _pinned.addAll(widget.defaultPinned);
    _hidden.addAll(widget.defaultHidden);
    _searchCtl.addListener(() {
      final q = _searchCtl.text.trim();
      if (q == _query) return;
      setState(() {
        _query = q;
        _page = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _vGroup.dispose();
    _hCtl.dispose();
    _hover.dispose();
    if (_ownsCtl) _ctl.dispose();
    super.dispose();
  }

  // ── التفضيلات ──

  String get _prefsKey => 'table.${widget.tableId}';

  void _loadPrefs() {
    if (_loadedPrefs) return;
    _loadedPrefs = true;
    final prefs = ref.read(desktopPrefsProvider);
    final t = prefs[_prefsKey];
    if (t is! Map) return;
    final w = t['widths'];
    if (w is Map) {
      w.forEach((k, v) {
        if (v is num) _widths['$k'] = v.toDouble();
      });
    }
    final h = t['hidden'];
    if (h is List) {
      _hidden
        ..clear()
        ..addAll(h.map((e) => '$e'));
    }
    final p = t['pinned'];
    if (p is List) {
      _pinned
        ..clear()
        ..addAll(p.map((e) => '$e'));
    }
    final o = t['order'];
    if (o is List) {
      _order
        ..clear()
        ..addAll(o.map((e) => '$e'));
    }
    final s = t['sort'];
    if (widget.persistSort && s is Map && s['id'] is String) {
      _sortId = s['id'] as String;
      _sortAsc = s['asc'] == true;
    }
    final ps = t['pageSize'];
    if (ps is num) _pageSize = ps.toInt();
  }

  void _savePrefs() {
    saveDesktopPref(ref, _prefsKey, {
      'widths': _widths,
      'hidden': _hidden.toList(),
      'pinned': _pinned,
      'order': _order,
      if (widget.persistSort && _sortId != null)
        'sort': {'id': _sortId, 'asc': _sortAsc},
      'pageSize': _pageSize,
    });
  }

  // ── الأعمدة المرئية ──

  /// أعمدة الجدول بالترتيب المخصَّص (إن وُجد): المذكورة في [_order] أولاً
  /// بترتيبها، ثم أي عمودٍ جديدٍ لم يُذكر بعدُ بترتيب إعلانه — فإضافة عمودٍ
  /// للكود مستقبلاً تظهر تلقائياً بلا فقدٍ ولا كسرٍ للترتيب المحفوظ.
  List<DeskCol<T>> get _orderedCols {
    if (_order.isEmpty) return widget.columns;
    final byId = {for (final c in widget.columns) c.id: c};
    final out = <DeskCol<T>>[];
    final seen = <String>{};
    for (final id in _order) {
      final c = byId[id];
      if (c != null && seen.add(id)) out.add(c);
    }
    for (final c in widget.columns) {
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }

  List<DeskCol<T>> get _visibleCols => [
        for (final c in _orderedCols)
          if (!_hidden.contains(c.id)) c,
      ];

  List<DeskCol<T>> get _pinnedCols => [
        for (final id in _pinned)
          for (final c in _visibleCols)
            if (c.id == id) c,
      ];

  List<DeskCol<T>> get _scrollCols => [
        for (final c in _visibleCols)
          if (!_pinned.contains(c.id)) c,
      ];

  double _colWidth(DeskCol<T> c) => _widths[c.id] ?? c.width;

  // ── الصفوف: بحث ← فرز ← صفحة ──

  List<T> get _filtered {
    var rows = widget.rows;
    if (_query.isNotEmpty && widget.searchText != null) {
      final q = _query;
      rows = [
        for (final r in rows)
          if (widget.searchText!(r).contains(q)) r,
      ];
    }
    final sortCol = _sortId == null
        ? null
        : widget.columns
            .where((c) => c.id == _sortId && c.sortKey != null)
            .firstOrNull;
    if (sortCol != null) {
      rows = [...rows]..sort((a, b) {
          final ka = sortCol.sortKey!(a);
          final kb = sortCol.sortKey!(b);
          int c;
          if (ka == null && kb == null) {
            c = 0;
          } else if (ka == null) {
            c = -1;
          } else if (kb == null) {
            c = 1;
          } else {
            c = ka.compareTo(kb);
          }
          return _sortAsc ? c : -c;
        });
    }
    return rows;
  }

  List<T> _paged(List<T> rows) {
    if (_pageSize <= 0 || rows.length <= _pageSize) return rows;
    final start = (_page * _pageSize).clamp(0, rows.length);
    final end = (start + _pageSize).clamp(0, rows.length);
    return rows.sublist(start, end);
  }

  // ── التحديد ──

  void _setSelection(Set<String> s) {
    setState(() => _selected = s);
    _ctl._selected = s;
    widget.onSelectionChanged?.call(s);
  }

  void _rowTap(int index, List<T> view, T row) {
    _ctl.tableFocus.requestFocus();
    final id = widget.rowId(row);
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    setState(() => _focusIndex = index);
    if (!widget.selectable) return;
    if (shift && _anchorIndex != null) {
      final a = _anchorIndex!.clamp(0, view.length - 1);
      final lo = a < index ? a : index;
      final hi = a > index ? a : index;
      final range = {
        for (var i = lo; i <= hi; i++) widget.rowId(view[i]),
      };
      _setSelection(ctrl ? {..._selected, ...range} : range);
    } else if (ctrl) {
      final s = {..._selected};
      s.contains(id) ? s.remove(id) : s.add(id);
      _anchorIndex = index;
      _setSelection(s);
    } else {
      _anchorIndex = index;
      // نقرة عادية على صف محدد وحده تبقيه (سلوك مألوف)؛ وإلا تحديد مفرد.
      _setSelection({id});
    }
  }

  List<T> _selectedRows(List<T> filtered) => [
        for (final r in filtered)
          if (_selected.contains(widget.rowId(r))) r,
      ];

  // ── لوحة المفاتيح ──

  KeyEventResult _onKey(FocusNode node, KeyEvent e, List<T> view) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final k = e.logicalKey;

    void moveFocus(int d) {
      if (view.isEmpty) return;
      setState(() {
        _focusIndex = (_focusIndex + d).clamp(0, view.length - 1);
        if (!keys.isShiftPressed) {
          _anchorIndex = _focusIndex;
          if (widget.selectable) {
            _selected = {widget.rowId(view[_focusIndex])};
            _ctl._selected = _selected;
            widget.onSelectionChanged?.call(_selected);
          }
        } else if (widget.selectable && _anchorIndex != null) {
          final lo =
              _anchorIndex! < _focusIndex ? _anchorIndex! : _focusIndex;
          final hi =
              _anchorIndex! > _focusIndex ? _anchorIndex! : _focusIndex;
          _selected = {
            for (var i = lo; i <= hi; i++) widget.rowId(view[i]),
          };
          _ctl._selected = _selected;
          widget.onSelectionChanged?.call(_selected);
        }
      });
      _ensureVisible(_focusIndex);
    }

    if (k == LogicalKeyboardKey.arrowDown) {
      moveFocus(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageDown) {
      moveFocus(12);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageUp) {
      moveFocus(-12);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.home && view.isNotEmpty) {
      setState(() => _focusIndex = 0);
      _ensureVisible(0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.end && view.isNotEmpty) {
      setState(() => _focusIndex = view.length - 1);
      _ensureVisible(view.length - 1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (_focusIndex >= 0 && _focusIndex < view.length) {
        widget.onOpen?.call(view[_focusIndex]);
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.delete && widget.onDelete != null) {
      final sel = _selectedRows(view);
      final targets = sel.isNotEmpty
          ? sel
          : (_focusIndex >= 0 && _focusIndex < view.length
              ? [view[_focusIndex]]
              : <T>[]);
      if (targets.isNotEmpty) {
        widget.onDelete!(targets);
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_selected.isNotEmpty || _query.isNotEmpty) {
        _searchCtl.clear();
        _setSelection({});
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (ctrl && k == LogicalKeyboardKey.keyA && widget.selectable) {
      _setSelection({for (final r in view) widget.rowId(r)});
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyF && widget.showSearch) {
      _ctl.focusSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ensureVisible(int index) {
    if (!_vScroll.hasClients) return;
    final top = index * widget.rowHeight;
    final bottom = top + widget.rowHeight;
    final pos = _vScroll.position;
    if (top < pos.pixels) {
      _vScroll.jumpTo(top.toDouble());
    } else if (bottom > pos.pixels + pos.viewportDimension) {
      _vScroll.jumpTo(bottom - pos.viewportDimension);
    }
  }

  // ── البناء ──

  @override
  Widget build(BuildContext context) {
    _loadPrefs();
    final filtered = _filtered;
    final view = _paged(filtered);
    final pages = _pageSize <= 0
        ? 1
        : (filtered.length / _pageSize).ceil().clamp(1, 1 << 20);
    if (_page >= pages) _page = pages - 1;
    final selRows = _selectedRows(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(filtered.length, selRows),
        if (selRows.isNotEmpty) _selectionBar(selRows),
        Expanded(
          child: view.isEmpty
              ? _empty()
              : Focus(
                  focusNode: _ctl.tableFocus,
                  onKeyEvent: (n, e) => _onKey(n, e, view),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _tableBody(view, constraints),
                  ),
                ),
        ),
        if (widget.footer != null) widget.footer!,
        if (_pageSize > 0 && filtered.length > _pageSize)
          _paginator(filtered.length, pages),
      ],
    );
  }

  // شريط الأدوات: بحث + حقن الشاشة + قائمة الأعمدة.
  Widget _toolbar(int total, List<T> selRows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          if (widget.showSearch && widget.searchText != null)
            SizedBox(
              width: 240,
              height: 34,
              child: TextField(
                key: Key('desk-search-${widget.tableId}'),
                controller: _searchCtl,
                focusNode: _ctl.searchFocus,
                onSubmitted: (_) => _ctl.tableFocus.requestFocus(),
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '${widget.searchHint}  (Ctrl+F)',
                  hintStyle:
                      TextStyle(fontSize: 11.5, color: BrandColors.faint),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 17, color: BrandColors.mut2),
                  suffixIcon: _query.isEmpty
                      ? null
                      : InkWell(
                          onTap: _searchCtl.clear,
                          child: Icon(Icons.close_rounded,
                              size: 15, color: BrandColors.mut2),
                        ),
                  filled: true,
                  fillColor: BrandColors.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: BrandColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: BrandColors.line),
                  ),
                ),
              ),
            ),
          if (widget.toolbarLeading != null) ...[
            const SizedBox(width: 8),
            Expanded(child: widget.toolbarLeading!),
          ] else
            const Spacer(),
          Text(
            '$total صف',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2),
          ),
          const SizedBox(width: 8),
          if (widget.toolbarTrailing != null) ...[
            widget.toolbarTrailing!,
            const SizedBox(width: 8),
          ],
          _columnsButton(),
        ],
      ),
    );
  }

  Widget _columnsButton() {
    return Tooltip(
      message: 'إدارة الأعمدة (ترتيب/إظهار/إخفاء/تثبيت)',
      child: InkWell(
        key: Key('desk-cols-${widget.tableId}'),
        borderRadius: BorderRadius.circular(9),
        onTap: _openColumnsMenu,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: BrandColors.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: BrandColors.line),
          ),
          child: Icon(Icons.view_week_rounded,
              size: 17, color: BrandColors.brandIcon),
        ),
      ),
    );
  }

  Future<void> _openColumnsMenu() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(10, 48, 36, .35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: BrandColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Row(
                    children: [
                      Icon(Icons.view_week_rounded,
                          size: 17, color: BrandColors.brandIcon),
                      const SizedBox(width: 7),
                      Text('إدارة الأعمدة',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.ink)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setLocal(() {
                            setState(() {
                              _hidden.clear();
                              _widths.clear();
                              _order.clear();
                              _pinned
                                ..clear()
                                ..addAll(widget.defaultPinned);
                            });
                            _savePrefs();
                          });
                        },
                        child: const Text('إعادة الضبط',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 6),
                  child: Text(
                    'اسحب ⣿ لإعادة الترتيب، وأزِل العلامة للإخفاء. يُحفَظ تلقائياً.',
                    style:
                        TextStyle(fontSize: 11, color: BrandColors.mut2),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  // قرار المالك — إدارة ترتيب الأعمدة: سحبٌ لإعادة الترتيب
                  // + إظهار/إخفاء + تثبيت، والكل يُحفَظ فوراً في تفضيلات
                  // الجدول (مفتاح order/hidden/pinned).
                  child: ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldI, newI) {
                      // onReorderItem يعدّل newIndex لحذف العنصر عند oldIndex
                      // تلقائياً (بديل onReorder المُهمَل) — فلا حاجة لتصحيحٍ
                      // يدويّ للفهرس.
                      final ids = [for (final c in _orderedCols) c.id];
                      final moved = ids.removeAt(oldI);
                      ids.insert(newI, moved);
                      setLocal(() {
                        setState(() {
                          _order
                            ..clear()
                            ..addAll(ids);
                        });
                        _savePrefs();
                      });
                    },
                    children: [
                      for (var i = 0; i < _orderedCols.length; i++)
                        _colManageRow(_orderedCols[i], i, setLocal),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// صفُّ عمودٍ في حوار إدارة الأعمدة: مقبض سحب + إظهار/إخفاء + تثبيت.
  Widget _colManageRow(DeskCol<T> c, int index, StateSetter setLocal) {
    final pinned = _pinned.contains(c.id);
    final visible = !_hidden.contains(c.id);
    return Padding(
      key: ValueKey('colmanage-${c.id}'),
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.drag_indicator_rounded,
                    size: 18, color: BrandColors.faint),
              ),
            ),
          ),
          Expanded(
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: visible,
              onChanged: !c.hideable
                  ? null
                  : (v) {
                      setLocal(() {
                        setState(() {
                          if (v == false) {
                            _hidden.add(c.id);
                          } else {
                            _hidden.remove(c.id);
                          }
                        });
                        _savePrefs();
                      });
                    },
              title: Text(c.label,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          Tooltip(
            message: pinned ? 'إلغاء التثبيت' : 'تثبيت العمود',
            child: IconButton(
              icon: Icon(
                pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 16,
                color: pinned ? BrandColors.goldDark : BrandColors.faint,
              ),
              onPressed: () {
                setLocal(() {
                  setState(() {
                    pinned ? _pinned.remove(c.id) : _pinned.add(c.id);
                  });
                  _savePrefs();
                });
              },
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  // شريط التحديد المتعدد.
  Widget _selectionBar(List<T> selRows) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: BrandColors.brand.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: BrandColors.brand.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_box_rounded,
              size: 16, color: BrandColors.brandIcon),
          const SizedBox(width: 6),
          Text(
            '${selRows.length} محدد',
            key: const Key('desk-selection-count'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: BrandColors.brandText),
          ),
          const SizedBox(width: 12),
          if (widget.onTagRows != null) ...[
            Text('وسم:',
                style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
            const SizedBox(width: 6),
            RowTagPicker(
              onPick: (tag) => widget.onTagRows!(selRows, tag),
            ),
            const SizedBox(width: 12),
          ],
          if (widget.selectionActions != null)
            ...widget.selectionActions!(selRows),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _setSelection({}),
            icon: const Icon(Icons.close_rounded, size: 15),
            label: const Text('إلغاء التحديد (Esc)',
                style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_rows_outlined, size: 42, color: BrandColors.faint2),
          const SizedBox(height: 10),
          Text(widget.emptyTitle,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.mut)),
          if (widget.emptyHint != null) ...[
            const SizedBox(height: 4),
            Text(widget.emptyHint!,
                style: TextStyle(fontSize: 11.5, color: BrandColors.faint)),
          ],
        ],
      ),
    );
  }

  // جسد الجدول: لوح مثبت + لوح متحرك.
  Widget _tableBody(List<T> view, BoxConstraints constraints) {
    final pinnedCols = _pinnedCols;
    final scrollCols = _scrollCols;

    final selW = widget.selectable ? _selColWidth : 0.0;
    final pinnedW =
        selW + pinnedCols.fold<double>(0, (s, c) => s + _colWidth(c));
    var scrollW = scrollCols.fold<double>(0, (s, c) => s + _colWidth(c));

    // توسيع أعمدة flex لملء الفراغ (لا فراغ ميت يمين الشاشة العريضة).
    final avail = constraints.maxWidth - pinnedW;
    final extraWidths = <String, double>{};
    if (scrollW < avail) {
      final flexTotal =
          scrollCols.fold<int>(0, (s, c) => s + (c.flex > 0 ? c.flex : 0));
      if (flexTotal > 0) {
        final extra = avail - scrollW;
        for (final c in scrollCols) {
          if (c.flex > 0) {
            extraWidths[c.id] = extra * (c.flex / flexTotal);
          }
        }
        scrollW = avail;
      }
    }

    double wOf(DeskCol<T> c) => _colWidth(c) + (extraWidths[c.id] ?? 0);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── اللوح المثبت (يمين RTL) ──
          if (pinnedW > 0)
            SizedBox(
              width: pinnedW,
              child: Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: Row(children: [
                      if (widget.selectable) _selectAllBox(view),
                      for (final c in pinnedCols)
                        _headerCell(c, wOf(c), pinned: true),
                    ]),
                  ),
                  Divider(height: 1, color: BrandColors.line),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ListView.builder(
                        controller: _vPinned,
                        itemExtent: widget.rowHeight,
                        itemCount: view.length,
                        itemBuilder: (ctx, i) => _rowSlice(
                          view, i,
                          cols: pinnedCols,
                          wOf: wOf,
                          withSelBox: widget.selectable,
                          withStripe: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (pinnedW > 0)
            Container(
              width: 1.5,
              color: BrandColors.gold.withValues(alpha: .35),
            ),
          // ── اللوح المتحرك أفقياً ──
          Expanded(
            child: Scrollbar(
              controller: _hCtl,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _hCtl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: scrollW,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 42,
                        child: Row(children: [
                          for (final c in scrollCols)
                            _headerCell(c, wOf(c)),
                        ]),
                      ),
                      Divider(height: 1, color: BrandColors.line),
                      Expanded(
                        child: Scrollbar(
                          controller: _vScroll,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _vScroll,
                            itemExtent: widget.rowHeight,
                            itemCount: view.length,
                            itemBuilder: (ctx, i) => _rowSlice(
                              view, i,
                              cols: scrollCols,
                              wOf: wOf,
                              withSelBox: false,
                              withStripe: pinnedW <= 0,
                            ),
                          ),
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

  Widget _selectAllBox(List<T> view) {
    final allSelected = view.isNotEmpty &&
        view.every((r) => _selected.contains(widget.rowId(r)));
    final some = _selected.isNotEmpty && !allSelected;
    return SizedBox(
      width: _selColWidth,
      child: Center(
        child: Checkbox(
          key: Key('desk-select-all-${widget.tableId}'),
          value: allSelected ? true : (some ? null : false),
          tristate: true,
          visualDensity: VisualDensity.compact,
          onChanged: (_) {
            if (allSelected) {
              _setSelection({});
            } else {
              _setSelection({for (final r in view) widget.rowId(r)});
            }
          },
        ),
      ),
    );
  }

  Widget _headerCell(DeskCol<T> c, double w, {bool pinned = false}) {
    final sorted = _sortId == c.id;
    return SizedBox(
      width: w,
      child: Stack(
        children: [
          InkWell(
            onTap: !c.sortable || c.sortKey == null
                ? null
                : () {
                    setState(() {
                      if (_sortId == c.id) {
                        _sortAsc = !_sortAsc;
                      } else {
                        _sortId = c.id;
                        _sortAsc = c.numeric ? false : true;
                      }
                    });
                    _savePrefs();
                  },
            onSecondaryTapDown: (d) => _headerMenu(c, d.globalPosition),
            child: Tooltip(
              message: c.tooltip ?? c.label,
              waitDuration: const Duration(milliseconds: 600),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: c.numeric
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (pinned) ...[
                      Icon(Icons.push_pin_rounded,
                          size: 10, color: BrandColors.goldDark),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: sorted
                              ? BrandColors.brandText
                              : BrandColors.mut,
                        ),
                      ),
                    ),
                    if (sorted) ...[
                      const SizedBox(width: 2),
                      Icon(
                        _sortAsc
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: BrandColors.goldDark,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // مقبض تغيير العرض — حافة نهاية الخلية (يسار RTL).
          if (c.resizable)
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                onEnter: (_) => setState(() => _hoverCol = c.id),
                onExit: (_) => setState(() {
                  if (_hoverCol == c.id) _hoverCol = null;
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    setState(() {
                      // RTL: السحب يساراً (سالب) يوسّع العمود.
                      final cur = _colWidth(c);
                      _widths[c.id] =
                          (cur - d.delta.dx).clamp(c.minWidth, 640.0);
                    });
                  },
                  onHorizontalDragEnd: (_) => _savePrefs(),
                  onDoubleTap: () {
                    setState(() => _widths.remove(c.id));
                    _savePrefs();
                  },
                  // مقبض مرئيّ: خطٌّ رفيع يتوهّج عند تحويم الفأرة — يجعل
                  // قابلية سحب عرض العمود مكتشَفةً بلا حزر (بلاغ المالك:
                  // «السماح بتغيير عرض الأعمدة» — القدرة كانت خفيّة).
                  child: SizedBox(
                    width: 9,
                    child: Center(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: (_hoverCol == c.id)
                              ? BrandColors.goldDark
                              : BrandColors.line,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _headerMenu(DeskCol<T> c, Offset pos) async {
    final pinned = _pinned.contains(c.id);
    await showDesktopContextMenu(context, pos, [
      CtxItem(
        pinned ? 'إلغاء تثبيت العمود' : 'تثبيت العمود',
        icon: pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        onTap: () {
          setState(() {
            pinned ? _pinned.remove(c.id) : _pinned.add(c.id);
          });
          _savePrefs();
        },
      ),
      if (c.hideable)
        CtxItem(
          'إخفاء العمود',
          icon: Icons.visibility_off_rounded,
          onTap: () {
            setState(() => _hidden.add(c.id));
            _savePrefs();
          },
        ),
      CtxItem(
        'عرض تلقائي',
        icon: Icons.settings_backup_restore_rounded,
        onTap: () {
          setState(() => _widths.remove(c.id));
          _savePrefs();
        },
      ),
      CtxItem.divider,
      CtxItem(
        'كل الأعمدة…',
        icon: Icons.view_week_rounded,
        onTap: _openColumnsMenu,
      ),
    ]);
  }

  // شريحة صف داخل لوح (المثبت أو المتحرك).
  Widget _rowSlice(
    List<T> view,
    int index, {
    required List<DeskCol<T>> cols,
    required double Function(DeskCol<T>) wOf,
    required bool withSelBox,
    required bool withStripe,
  }) {
    final row = view[index];
    final id = widget.rowId(row);
    final selected = _selected.contains(id);
    final focused = _focusIndex == index;
    final tagId = widget.rowTagOf?.call(row);

    // RepaintBoundary: تغيّر صفٍّ (تحويم/تحديد) لا يعيد رسم بقية الصفوف.
    return RepaintBoundary(
        child: MouseRegion(
      onEnter: (_) => _hover.value = index,
      onExit: (_) {
        if (_hover.value == index) _hover.value = null;
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _rowTap(index, view, row),
        onDoubleTap:
            widget.onOpen == null ? null : () => widget.onOpen!(row),
        onSecondaryTapDown: widget.contextMenuOf == null
            ? null
            : (d) {
                if (!_selected.contains(id)) _rowTap(index, view, row);
                showDesktopContextMenu(
                    context, d.globalPosition, widget.contextMenuOf!(row));
              },
        onLongPressStart: widget.contextMenuOf == null
            ? null
            : (d) => showDesktopContextMenu(
                context, d.globalPosition, widget.contextMenuOf!(row)),
        child: ValueListenableBuilder<int?>(
          valueListenable: _hover,
          builder: (context, hoverIndex, rowChild) {
            final hovered = hoverIndex == index;
            Color? bg;
            if (selected) {
              bg = BrandColors.brand.withValues(alpha: .10);
            } else {
              bg = rowTagTint(tagId);
              bg ??= (widget.zebra && index.isOdd)
                  ? BrandColors.surface2.withValues(alpha: .55)
                  : null;
              if (hovered) {
                bg = Color.alphaBlend(BrandColors.brand.withValues(alpha: .05),
                    bg ?? BrandColors.surface);
              }
            }
            return Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(
                      color: BrandColors.line.withValues(alpha: .5),
                      width: .5),
                  // إطار تركيز لوحة المفاتيح.
                  top: focused
                      ? BorderSide(
                          color: BrandColors.gold.withValues(alpha: .55))
                      : BorderSide.none,
                ),
              ),
              child: rowChild,
            );
          },
          child: Row(
            children: [
              if (withStripe)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 2),
                  child: rowTagStripe(tagId,
                      height: widget.rowHeight - 14),
                ),
              if (withSelBox)
                SizedBox(
                  width: _selColWidth - (withStripe ? 5 : 0),
                  child: Center(
                    child: Checkbox(
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) {
                        final s = {..._selected};
                        selected ? s.remove(id) : s.add(id);
                        _anchorIndex = index;
                        _setSelection(s);
                      },
                    ),
                  ),
                ),
              for (final c in cols)
                SizedBox(
                  width: wOf(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: c.numeric
                          ? Alignment.center
                          : AlignmentDirectional.centerStart,
                      child: c.cell(context, row),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ));
  }

  // شريط الترقيم.
  Widget _paginator(int total, int pages) {
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: Icon(icon,
                  size: 17,
                  color:
                      onTap == null ? BrandColors.faint2 : BrandColors.mut),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          Text(
            'الصفحة ${_page + 1} من $pages — $total صف',
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
          ),
          const Spacer(),
          Text('صفوف الصفحة:',
              style: TextStyle(fontSize: 11, color: BrandColors.mut2)),
          const SizedBox(width: 6),
          DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 11.5, color: BrandColors.ink),
            items: const [
              DropdownMenuItem(value: 25, child: Text('25')),
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
              DropdownMenuItem(value: 200, child: Text('200')),
              DropdownMenuItem(value: 0, child: Text('الكل')),
            ],
            onChanged: (v) {
              setState(() {
                _pageSize = v ?? 50;
                _page = 0;
              });
              _savePrefs();
            },
          ),
          const SizedBox(width: 10),
          // RTL: «التالي» يذهب يساراً بصرياً — الأسهم بالاتجاه المنطقي.
          btn(Icons.last_page_rounded, 'الأولى',
              _page == 0 ? null : () => setState(() => _page = 0)),
          btn(Icons.chevron_right_rounded, 'السابقة',
              _page == 0 ? null : () => setState(() => _page--)),
          btn(
              Icons.chevron_left_rounded,
              'التالية',
              _page >= pages - 1
                  ? null
                  : () => setState(() => _page++)),
          btn(
              Icons.first_page_rounded,
              'الأخيرة',
              _page >= pages - 1
                  ? null
                  : () => setState(() => _page = pages - 1)),
        ],
      ),
    );
  }
}

/// أداة مساعدة: التقاط النقر الأوسط/الثانوي خارج الجدول إن لزم مستقبلاً.
bool isSecondaryClick(PointerDownEvent e) =>
    e.buttons & kSecondaryMouseButton != 0;
