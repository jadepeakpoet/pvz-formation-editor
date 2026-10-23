import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import '../domain/formation.dart';
import '../platform/app_language.dart';
import 'board_painter.dart';

/// The source site's row/column selectors. Operations use their intersection;
/// the white masks deliberately show each axis separately, as on the website.
class BatchSelectionOverlay extends StatelessWidget {
  final Formation document;
  final Set<int> selectedRows, selectedColumns;
  final ValueChanged<Set<int>> onRowsChanged, onColumnsChanged;

  const BatchSelectionOverlay({
    super.key,
    required this.document,
    required this.selectedRows,
    required this.selectedColumns,
    required this.onRowsChanged,
    required this.onColumnsChanged,
  });

  Widget selector(String key, String label, Offset center, bool value,
          ValueChanged<bool> onChanged) =>
      Positioned(
          left: center.dx - 9,
          top: center.dy - 9,
          width: 18,
          height: 18,
          child: Tooltip(
              message: AppLanguage.text(label),
              child: Checkbox(
                  key: ValueKey(key),
                  value: value,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  fillColor: MaterialStateProperty.resolveWith((states) =>
                      states.contains(MaterialState.selected)
                          ? const Color(0xff1976d2)
                          : Colors.white),
                  onChanged: (value) => onChanged(value!))));

  @override
  Widget build(BuildContext context) {
    final geometry = BoardGeometry(document);
    final rows = document.map.rows, columns = document.map.columns;
    final first = geometry.cellCenter(0, 0);
    final rowX = first.dx - geometry.cellWidth / 2 - 26;
    double columnY(int col) =>
        geometry.cellCenter(0, col).dy - geometry.cellHeight / 2 - 25;
    Set<int> toggled(Set<int> values, int value, bool selected) =>
        Set<int>.of(values)
          ..removeWhere((v) => v == value)
          ..addAll(selected ? [value] : const []);
    return SizedBox.fromSize(
        size: geometry.size,
        child: Stack(children: [
          Positioned.fill(
              child: IgnorePointer(
                  child: ClipRect(
                      child: CustomPaint(
                          painter: BatchSelectionMaskPainter(
                              document: document,
                              selectedRows: selectedRows,
                              selectedColumns: selectedColumns))))),
          selector(
              'batch-row-all',
              '全部行',
              Offset(rowX, first.dy - geometry.cellHeight / 2 + 5),
              selectedRows.length == rows,
              (value) => onRowsChanged(
                  value ? {for (var row = 0; row < rows; row++) row} : {})),
          selector(
              'batch-col-all',
              '全部列',
              Offset(first.dx - 36, columnY(0)),
              selectedColumns.length == columns,
              (value) => onColumnsChanged(
                  value ? {for (var col = 0; col < columns; col++) col} : {})),
          for (var row = 0; row < rows; row++)
            selector(
                'batch-row-$row',
                '${row + 1}',
                Offset(rowX, geometry.cellCenter(row, 0).dy),
                selectedRows.contains(row),
                (value) => onRowsChanged(toggled(selectedRows, row, value))),
          for (var col = 0; col < columns; col++)
            selector(
                'batch-col-$col',
                '${col + 1}',
                Offset(geometry.cellCenter(0, col).dx, columnY(col)),
                selectedColumns.contains(col),
                (value) =>
                    onColumnsChanged(toggled(selectedColumns, col, value))),
        ]));
  }
}

class BatchSelectionMaskPainter extends CustomPainter {
  final Formation document;
  final Set<int> selectedRows, selectedColumns;
  BatchSelectionMaskPainter({
    required this.document,
    required Set<int> selectedRows,
    required Set<int> selectedColumns,
  })  : selectedRows = Set<int>.of(selectedRows),
        selectedColumns = Set<int>.of(selectedColumns);

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = BoardGeometry(document);
    final paint = Paint()..color = const Color(0x80ffffff);
    for (final row in selectedRows) {
      if (row < 0 || row >= document.map.rows) continue;
      for (var col = 0; col < document.map.columns; col++) {
        final center = geometry.cellCenter(row, col);
        canvas.drawRect(
            Rect.fromLTWH(center.dx - 30, center.dy - 50, 60, 60), paint);
      }
    }
    for (final col in selectedColumns) {
      if (col < 0 || col >= document.map.columns) continue;
      final center = geometry.cellCenter(0, col);
      canvas.drawRect(
          Rect.fromLTWH(
              center.dx - 30, center.dy - geometry.cellHeight / 2, 60, 600),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant BatchSelectionMaskPainter oldDelegate) =>
      oldDelegate.document.mapId != document.mapId ||
      !setEquals(oldDelegate.selectedRows, selectedRows) ||
      !setEquals(oldDelegate.selectedColumns, selectedColumns);
}
