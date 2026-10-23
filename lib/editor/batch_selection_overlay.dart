import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import '../domain/formation.dart';
import '../platform/app_language.dart';
import 'board_painter.dart';

/// The source site's row/column selectors. Operations use their intersection;
/// axis boundaries use thin yellow lines and intersections receive a soft tint.
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
          left: center.dx - 22,
          top: center.dy - 22,
          width: 44,
          height: 44,
          child: Tooltip(
              message: AppLanguage.text(label),
              child: Semantics(
                  checked: value,
                  label: AppLanguage.text(label),
                  onTap: () => onChanged(!value),
                  child: GestureDetector(
                      key: ValueKey('$key-target'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(!value),
                      child: Center(
                          child: ExcludeSemantics(
                              child: IgnorePointer(
                                  child: Transform.scale(
                                      scale: 39 / 18,
                                      child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: Checkbox(
                                              key: ValueKey(key),
                                              value: value,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              fillColor: MaterialStateProperty.resolveWith(
                                                  (states) => states.contains(
                                                          MaterialState.selected)
                                                      ? const Color(0xff1976d2)
                                                      : Colors.white),
                                              onChanged: (value) => onChanged(value!)))))))))));

  @override
  Widget build(BuildContext context) {
    final geometry = BoardGeometry(document);
    final rows = document.map.rows, columns = document.map.columns;
    final first = geometry.cellCenter(0, 0);
    final rowX = (first.dx - geometry.cellWidth / 2 - 26).clamp(22.0, 778.0);
    double columnY(int col) =>
        (geometry.cellCenter(0, col).dy - geometry.cellHeight / 2 - 25)
            .clamp(22.0, 578.0);
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
    final fill = Paint()..color = const Color(0x33ffdf70);
    final highlight = Paint()
      ..color = const Color(0xbfe8c75b)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    for (final row in selectedRows) {
      if (row < 0 || row >= document.map.rows) continue;
      for (final col in selectedColumns) {
        if (col < 0 || col >= document.map.columns) continue;
        canvas.drawPath(geometry.cellPath(row, col), fill);
      }
    }
    Offset corner(int row, int col) => Offset(
        40 + col * geometry.cellWidth,
        geometry.boardTop +
            row * geometry.cellHeight +
            geometry.slope(col.toDouble()));
    for (final row in selectedRows) {
      if (row < 0 || row >= document.map.rows) continue;
      for (final boundary in [row, row + 1]) {
        final start = corner(boundary, 0);
        final path = Path()..moveTo(start.dx, start.dy);
        for (var col = 1; col <= document.map.columns; col++) {
          final point = corner(boundary, col);
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, highlight);
      }
    }
    for (final col in selectedColumns) {
      if (col < 0 || col >= document.map.columns) continue;
      for (final boundary in [col, col + 1]) {
        canvas.drawLine(corner(0, boundary),
            corner(document.map.rows, boundary), highlight);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BatchSelectionMaskPainter oldDelegate) =>
      oldDelegate.document.mapId != document.mapId ||
      !setEquals(oldDelegate.selectedRows, selectedRows) ||
      !setEquals(oldDelegate.selectedColumns, selectedColumns);
}
