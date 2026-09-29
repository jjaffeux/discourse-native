import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/composer_syntax.dart';
import '../theme/d_icons.dart';
import 'composer_block_selection.dart';
import 'composer_controller.dart';
import 'composer_embedded_editor.dart';
import 'composer_marks.dart';
import 'composer_tables.dart';

ComposerSyntaxKind get composerTableSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('core'),
  name: 'table',
  label: appL10n.table,
);

void insertComposerTable(ComposerController composer) {
  if (!composer.isCurrent || !composer.isEditing || composer.target.isPlugin) {
    return;
  }
  composer.insertBlock(
    expectedValue: composer.value,
    markdown: appL10n.column1Column2,
  );
  composer.requestFocus();
}

final class ComposerTablePolicy implements ComposerSyntaxPolicy {
  const ComposerTablePolicy(this.composer);
  final ComposerController composer;

  @override
  ComposerSyntaxKind get kind => composerTableSyntaxKind;
  @override
  Object get projectionState => composer.isEditing;
  @override
  TextInputFormatter get inputFormatter => const ComposerTableInputFormatter();
  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final table in parseComposerTables(source))
      _TableProjection(composer, table),
  ];
}

final class _TableProjection implements ComposerInteractiveSyntaxProjection {
  _TableProjection(this.composer, this.table);
  final ComposerController composer;
  final ComposerTableBlock table;
  GlobalKey? _editorKey;
  @override
  int get start => table.start;
  @override
  int get end => table.end;
  @override
  String get source => table.source;
  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      document.isComposingRangeValid &&
      !document.composing.isCollapsed &&
      document.composing.start < end &&
      document.composing.end > start;
  @override
  int caretAfter(String document) =>
      end < document.length && document[end] == '\n' ? end + 1 : end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) {
    // The visual line below a terminal table still maps to its last source
    // row. Give body text its own line before placing the caret there.
    final text = end == document.text.length
        ? '${document.text}\n'
        : document.text;
    return document.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: caretAfter(text)),
      composing: TextRange.empty,
    );
  }

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    _editorKey = context.pillKey;
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: LayoutBuilder(
          builder: (widgetContext, constraints) {
            // RenderEditable reserves a one-pixel gap plus the cursor width for
            // text, but measures inline widgets against the full viewport.
            final caretMargin =
                (widgetContext
                        .findAncestorWidgetOfExactType<EditableText>()
                        ?.cursorWidth ??
                    2) +
                1;
            return SizedBox(
              width: (constraints.maxWidth - caretMargin).clamp(
                0,
                double.infinity,
              ),
              // WidgetSpan scales the whole table with the surrounding text.
              // Do not apply the inherited scaler again inside its controls.
              child: MediaQuery.withNoTextScaling(
                child: ComposerTableEditor(
                  key: context.pillKey,
                  composer: composer,
                  table: table,
                  selected: context.highlighted,
                ),
              ),
            );
          },
        ),
      ),
      // The source's real newline ends the widget line when present. Hidden
      // table rows must not introduce another apparent typing line below it.
      TextSpan(
        text: source.substring(1, hiddenEnd),
        semanticsLabel: '\u200B' * (hiddenEnd - 1),
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
      if (!context.followedByLineBreak)
        TextSpan(
          text: '\n',
          style: context.baseStyle.copyWith(color: Colors.transparent),
        ),
    ];
  }

  @override
  void edit(BuildContext context, ComposerEditorHost editor) {
    if (_editorKey?.currentState case final _ComposerTableEditorState state) {
      state._focusCell(0, 0);
    }
  }

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isCurrent || !editor.isEditing) return;
    final current = editor.value;
    if (end > current.text.length ||
        current.text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: current.text,
      value: TextEditingValue(
        text: current.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}

/// The post table's existing builders compose Native inputs and action menus.
/// Every edit synchronously updates canonical Markdown, including draft saves.
class ComposerTableEditor extends StatefulWidget {
  const ComposerTableEditor({
    super.key,
    required this.composer,
    required this.table,
    this.selected = false,
  });
  final ComposerController composer;
  final ComposerTableBlock table;
  final bool selected;

  @override
  State<ComposerTableEditor> createState() => _ComposerTableEditorState();
}

class _ComposerTableEditorState extends State<ComposerTableEditor> {
  late ComposerTableBlock _table = widget.table;
  int _nextId = 0;
  late List<int> _columns = List.generate(_table.columnCount, (_) => _nextId++);
  late List<int> _rows = List.generate(_table.rowCount + 1, (_) => _nextId++);
  final _cells = <(int, int), _CellEditing>{};
  Widget? _content;
  bool? _contentEditing;
  Object _actionVersion = Object();

  void _invalidateContent() {
    _content = null;
    _actionVersion = Object();
  }

  @override
  void didUpdateWidget(ComposerTableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composer != widget.composer) _invalidateContent();
    if (oldWidget.selected != widget.selected) _content = null;
    if (_table.source == widget.table.source &&
        _table.start == widget.table.start) {
      return;
    }
    _invalidateContent();
    _table = widget.table;
    // External history and restored drafts replace the snapshot. Existing
    // fields retain their controllers when the shape has not changed.
    if (_columns.length != _table.columnCount ||
        _rows.length != _table.rowCount + 1) {
      _columns = List.generate(_table.columnCount, (_) => _nextId++);
      _rows = List.generate(_table.rowCount + 1, (_) => _nextId++);
      _pruneCells();
    }
    for (var row = 0; row < _rows.length; row++) {
      for (var column = 0; column < _columns.length; column++) {
        final cell = _cells[(_rows[row], _columns[column])];
        if (cell == null) continue;
        final text = _table.cell(row, column);
        if (text != cell.source) {
          cell.source = text;
          cell.padding = _table.cellPadding(row, column);
          cell.controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    for (final cell in _cells.values) {
      cell.dispose();
    }
    super.dispose();
  }

  bool _replace(String source, {VoidCallback? structureChanged}) {
    final composer = widget.composer;
    final current = composer.value;
    if (!composer.isCurrent ||
        !composer.isEditing ||
        _table.end > current.text.length ||
        current.text.substring(_table.start, _table.end) != _table.source) {
      return false;
    }
    if (source == _table.source) return true;
    final start = _table.start;
    final next = current.text.replaceRange(start, _table.end, source);
    final table = source.isEmpty
        ? null
        : parseComposerTables(next)
              .where((table) => table.start == start && table.source == source)
              .firstOrNull;
    if (source.isNotEmpty && table == null) return false;
    if (!composer.commitText(
      expectedText: current.text,
      value: TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + source.length),
      ),
    )) {
      return false;
    }
    if (source.isEmpty) {
      composer.requestFocus();
      return true;
    }
    _table = table!;
    // Cell controllers already own text, selection and IME updates. Rebuilding
    // every Native input/menu here turns each keystroke into a whole-table edit.
    if (structureChanged != null) {
      setState(() {
        structureChanged();
        _invalidateContent();
        _pruneCells();
      });
    }
    return true;
  }

  void _pruneCells() {
    final removed = <_CellEditing>[];
    _cells.removeWhere((id, cell) {
      if (_rows.contains(id.$1) && _columns.contains(id.$2)) return false;
      removed.add(cell);
      return true;
    });
    if (removed.isEmpty) return;
    // Old fields are still mounted until this frame finishes rebuilding.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final cell in removed) {
        cell.dispose();
      }
    });
  }

  void _insertRow(int index) => _replace(
    _table.insertRow(index),
    structureChanged: () => _rows.insert(index + 1, _nextId++),
  );
  void _insertColumn(int index) => _replace(
    _table.insertColumn(index),
    structureChanged: () => _columns.insert(index, _nextId++),
  );
  void _moveRow(int from, int to) => _replace(
    _table.moveRow(from, to),
    structureChanged: () => _rows.insert(to + 1, _rows.removeAt(from + 1)),
  );
  void _moveColumn(int from, int to) => _replace(
    _table.moveColumn(from, to),
    structureChanged: () => _columns.insert(to, _columns.removeAt(from)),
  );

  void _finish() {
    final composer = widget.composer;
    if (!composer.isCurrent || !composer.isEditing) return;
    composer.text.selection = TextSelection.collapsed(
      offset: _table.end.clamp(0, composer.value.text.length),
    );
    composer.requestFocus();
  }

  void _focusCell(int row, int column) {
    if (row < 0) {
      _finish();
      return;
    }
    if (row >= _rows.length) _insertRow(_table.rowCount);
    if (row >= _rows.length) return;
    final id = (_rows[row], _columns[column]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cell = _cells[id];
      cell?.focus.requestFocus();
      if (cell?.focus.context case final context?) {
        Scrollable.ensureVisible(context, alignment: .5);
      }
    });
    setState(() {});
  }

  Widget _input(int row, int column) {
    final id = (_rows[row], _columns[column]);
    final cell = _cells.putIfAbsent(
      id,
      () => _CellEditing(
        _table.cell(row, column),
        _table.cellPadding(row, column),
      ),
    );
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final keyboard = HardwareKeyboard.instance;
        if ((keyboard.isMetaPressed || keyboard.isControlPressed) &&
            !keyboard.isAltPressed) {
          final marker = switch (event.logicalKey) {
            LogicalKeyboardKey.keyB => '**',
            LogicalKeyboardKey.keyI => '*',
            LogicalKeyboardKey.keyE => '`',
            _ => null,
          };
          if (marker != null) {
            final next = toggleMarkdownMark(cell.controller.value, marker);
            if (_replace(
              _table.editCell(row, column, next.text, padding: cell.padding),
            )) {
              cell.source = _table.cell(row, column);
              cell.controller.value = next;
            }
            return KeyEventResult.handled;
          }
          // The surrounding composer's link dialog edits its main selection.
          // Keep that shortcut from inserting a link outside the active cell.
          if (event.logicalKey == LogicalKeyboardKey.keyL) {
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _finish();
          return KeyEventResult.handled;
        }
        if (keyboard.isMetaPressed ||
            keyboard.isControlPressed ||
            keyboard.isAltPressed) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.tab) {
          final next =
              row * _columns.length +
              column +
              (keyboard.isShiftPressed ? -1 : 1);
          _focusCell(
            next < 0 ? -1 : next ~/ _columns.length,
            next < 0 ? 0 : next % _columns.length,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _focusCell(row + (keyboard.isShiftPressed ? -1 : 1), column);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DInput(
        key: ValueKey('table-cell-$row-$column'),
        controller: cell.controller,
        focusNode: cell.focus,
        borderless: true,
        semanticLabel: row == 0
            ? appL10n.columnHeading((column + 1).toString())
            : appL10n.rowColumn((row).toString(), (column + 1).toString()),
        hintText: row == 0 ? appL10n.heading : appL10n.cell,
        enabled: widget.composer.isEditing,
        style: row == 0 ? const TextStyle(fontWeight: FontWeight.w600) : null,
        onSubmitted: (_) => _focusCell(row + 1, column),
        onChanged: (value) {
          if (_replace(
            _table.editCell(row, column, value, padding: cell.padding),
          )) {
            cell.source = _table.cell(row, column);
          }
        },
      ),
    );
  }

  Widget _menu(String label, List<Widget> items, {Widget? child}) =>
      DDropdownMenu(
        content: DDropdownMenuContent(
          semanticLabel: label,
          width: 220,
          children: items,
        ),
        child: DDropdownMenuTrigger(
          builder: (context, trigger) => child == null
              ? DButton.iconOnly(
                  tooltip: label,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  hasPopup: true,
                  expanded: trigger.open,
                  focusNode: trigger.focusNode,
                  onPressed: widget.composer.isEditing ? trigger.toggle : null,
                  icon: const DIcon(DIcons.ellipsis, size: 16),
                )
              : DButton(
                  tooltip: label,
                  label: child,
                  variant: DButtonVariant.ghost,
                  size: DButtonSize.small,
                  hasPopup: true,
                  expanded: trigger.open,
                  focusNode: trigger.focusNode,
                  onPressed: widget.composer.isEditing ? trigger.toggle : null,
                ),
        ),
      );

  VoidCallback _menuAction(VoidCallback action) {
    final version = _actionVersion;
    return () {
      if (mounted &&
          identical(version, _actionVersion) &&
          widget.composer.isEditing) {
        action();
      }
    };
  }

  Widget _columnMenu(int column) => _menu(
    appL10n.columnActions((column + 1).toString()),
    _columnItems(column),
  );

  List<Widget> _columnItems(int column) => [
    DDropdownMenuItem(
      onPressed: _menuAction(() => _insertColumn(column)),
      child: Text(appL10n.insertColumnBefore),
    ),
    DDropdownMenuItem(
      onPressed: _menuAction(() => _insertColumn(column + 1)),
      child: Text(appL10n.insertColumnAfter),
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuItem(
      onPressed: column == 0
          ? null
          : _menuAction(() => _moveColumn(column, column - 1)),
      child: Text(appL10n.moveColumnEarlier),
    ),
    DDropdownMenuItem(
      onPressed: column == _columns.length - 1
          ? null
          : _menuAction(() => _moveColumn(column, column + 1)),
      child: Text(appL10n.moveColumnLater),
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuItem(
      onPressed: _columns.length == 1
          ? null
          : _menuAction(
              () => _replace(
                _table.removeColumn(column),
                structureChanged: () => _columns.removeAt(column),
              ),
            ),
      child: Text(appL10n.deleteColumn),
    ),
  ];

  Widget _rowMenu(int row) => _menu(
    appL10n.rowActions((row + 1).toString()),
    _rowItems(row),
    child: Text('${row + 1}'),
  );

  DContextMenuContent _rowContextMenu(int row) => DContextMenuContent(
    semanticLabel: appL10n.rowActions((row + 1).toString()),
    width: 220,
    children: _rowItems(row),
  );

  List<Widget> _rowItems(int row) => [
    DDropdownMenuItem(
      onPressed: _menuAction(() => _insertRow(row)),
      child: Text(appL10n.insertRowAbove),
    ),
    DDropdownMenuItem(
      onPressed: _menuAction(() => _insertRow(row + 1)),
      child: Text(appL10n.insertRowBelow),
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuItem(
      onPressed: row == 0 ? null : _menuAction(() => _moveRow(row, row - 1)),
      child: Text(appL10n.moveRowUp),
    ),
    DDropdownMenuItem(
      onPressed: row == _table.rowCount - 1
          ? null
          : _menuAction(() => _moveRow(row, row + 1)),
      child: Text(appL10n.moveRowDown),
    ),
    const DDropdownMenuSeparator(),
    DDropdownMenuItem(
      onPressed: _menuAction(
        () => _replace(
          _table.removeRow(row),
          structureChanged: () => _rows.removeAt(row + 1),
        ),
      ),
      child: Text(appL10n.deleteRow),
    ),
  ];

  @override
  Widget build(BuildContext context) => ComposerEmbeddedEditor(
    owner: widget.composer,
    scrollController: widget.composer.text.imageScrollController,
    semanticLabel: context.l10n.tableEditor,
    child: _tableContent(),
  );

  Widget _tableContent() => ListenableBuilder(
    listenable: widget.composer,
    builder: (context, _) {
      if (_contentEditing != widget.composer.isEditing) {
        _contentEditing = widget.composer.isEditing;
        _invalidateContent();
      }
      return _content ??= _buildTableContent();
    },
  );

  Widget _buildTableContent() => Padding(
    padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ComposerBlockSelection(
          selected: widget.selected,
          child: DDataTable<int>(
            semanticLabel: appL10n.editableTable,
            variant: DDataTableVariant.softHeader,
            data: _rows.skip(1).toList(),
            rowId: (row) => row,
            operationMode: DDataTableOperationMode.manual,
            empty: Text(appL10n.addARowToStartWriting),
            columns: [
              DDataTableColumn<int>(
                id: 'row-actions',
                cellContextMenuBuilder: widget.composer.isEditing
                    ? (cell) => _rowContextMenu(_rows.indexOf(cell.row) - 1)
                    : null,
                label: appL10n.rows,
                hideable: false,
                width: const FixedColumnWidth(64),
                cellBuilder: (_, cell) => _rowMenu(_rows.indexOf(cell.row) - 1),
              ),
              for (final (column, id) in _columns.indexed)
                DDataTableColumn<int>(
                  id: '$id',
                  // The input owns the live heading. Keep the resize/menu
                  // identity stable while the heading's text is being edited.
                  label: appL10n.column((column + 1).toString()),
                  hideable: false,
                  width: const FixedColumnWidth(200),
                  resizable: true,
                  headerContextMenu: widget.composer.isEditing
                      ? DContextMenuContent(
                          semanticLabel: appL10n.columnActions(
                            (column + 1).toString(),
                          ),
                          width: 220,
                          children: _columnItems(column),
                        )
                      : null,
                  cellContextMenuBuilder: widget.composer.isEditing
                      ? (cell) => _rowContextMenu(_rows.indexOf(cell.row) - 1)
                      : null,
                  cellMouseCursor: SystemMouseCursors.text,
                  onHeaderTap: widget.composer.isEditing
                      ? () => _focusCell(0, column)
                      : null,
                  onCellTap: widget.composer.isEditing
                      ? (cell) => _focusCell(_rows.indexOf(cell.row), column)
                      : null,
                  headerBuilder: (_, _) => Row(
                    children: [
                      Expanded(child: _input(0, column)),
                      _columnMenu(column),
                    ],
                  ),
                  cellBuilder: (_, cell) =>
                      _input(_rows.indexOf(cell.row), column),
                ),
            ],
          ),
        ),
        const SizedBox(height: DSpacing.sm),
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.sm,
          children: [
            DButton(
              label: Text(appL10n.addRow),
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              onPressed: widget.composer.isEditing
                  ? () => _insertRow(_table.rowCount)
                  : null,
            ),
            DButton(
              label: Text(appL10n.addColumn),
              variant: DButtonVariant.outline,
              size: DButtonSize.small,
              onPressed: widget.composer.isEditing
                  ? () => _insertColumn(_columns.length)
                  : null,
            ),
            DButton.iconOnly(
              tooltip: appL10n.removeTable,
              icon: const DIcon(DIcons.trashCan, size: 14),
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              onPressed: widget.composer.isEditing ? () => _replace('') : null,
            ),
          ],
        ),
      ],
    ),
  );
}

class _CellEditing {
  _CellEditing(this.source, this.padding)
    : controller = TextEditingController(text: source);
  String source;
  // Keep authored spacing separate from whitespace entered in the field,
  // including when deletion makes the source's content boundary ambiguous.
  ({String before, String after}) padding;
  final TextEditingController controller;
  final FocusNode focus = FocusNode();
  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}
