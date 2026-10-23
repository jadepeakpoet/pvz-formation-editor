import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import '../platform/app_language.dart';
import 'board_painter.dart';

typedef MapPickerChoice = ({String mapId, bool keepPlants});

Future<MapPickerChoice?> showMapPickerDialog(BuildContext context,
        {required String currentMapId, bool readOnly = false}) =>
    showDialog<MapPickerChoice>(
        context: context,
        builder: (_) =>
            _MapPickerDialog(currentMapId: currentMapId, readOnly: readOnly));

class _MapPickerDialog extends StatefulWidget {
  final String currentMapId;
  final bool readOnly;
  const _MapPickerDialog({required this.currentMapId, required this.readOnly});
  @override
  State<_MapPickerDialog> createState() => _MapPickerDialogState();
}

class _MapPickerDialogState extends State<_MapPickerDialog> {
  late String selectedMapId = widget.currentMapId;
  bool keepPlants = false;

  void previewMap(String id) {
    if (selectedMapId != id) setState(() => selectedMapId = id);
  }

  void chooseMap(String id) {
    previewMap(id);
    if (!widget.readOnly) {
      Navigator.of(context).pop((mapId: id, keepPlants: keepPlants));
    }
  }

  Widget preview(BoardMap map, {Key? key}) => AspectRatio(
      aspectRatio: 4 / 3,
      child: CustomPaint(
          key: key,
          painter: BoardPainter(
              document: Formation(mapId: map.id, display: const {}),
              helpers: false)));

  Widget mapList() => DecoratedBox(
      decoration: BoxDecoration(
          color: const Color(0xffedf1e6),
          borderRadius: BorderRadius.circular(8)),
      child: SingleChildScrollView(
          child: Column(children: [
        for (final map in BoardMap.all)
          Semantics(
              selected: selectedMapId == map.id,
              button: true,
              child: InkWell(
                  key: ValueKey('map-picker-map-${map.id}'),
                  onHover: (hovering) {
                    if (hovering) previewMap(map.id);
                  },
                  onFocusChange: (focused) {
                    if (focused) previewMap(map.id);
                  },
                  onTap: () => chooseMap(map.id),
                  child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: selectedMapId == map.id
                              ? const Color(0xffd7e4cc)
                              : Colors.transparent,
                          border: Border(
                              left: BorderSide(
                                  width: 3,
                                  color: selectedMapId == map.id
                                      ? const Color(0xff456b4e)
                                      : Colors.transparent))),
                      child: Row(children: [
                        SizedBox(
                            width: 76,
                            child: RepaintBoundary(child: preview(map))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(AppLanguage.text(map.name),
                                style: const TextStyle(fontSize: 12))),
                        if (selectedMapId == map.id)
                          const Icon(Icons.check_circle,
                              size: 17, color: Color(0xff456b4e)),
                      ]))))
      ])));

  Widget selectedPreview() {
    final map = BoardMap.byId(selectedMapId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(AppLanguage.text(map.name),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: preview(map, key: const ValueKey('map-picker-preview'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 32;
    return Dialog(
        key: const ValueKey('map-picker-dialog'),
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: const Color(0xfff4f5ed),
        child: SizedBox(
            width: 760,
            height: math.min(620, availableHeight),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(AppLanguage.text('更换地图'),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600))),
                        TextButton(
                            key: const ValueKey('map-picker-cancel'),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(AppLanguage.text('取消'))),
                      ]),
                      Row(children: [
                        SizedBox(
                            width: 24,
                            height: 32,
                            child: Checkbox(
                                key: const ValueKey('map-picker-keep-plants'),
                                value: keepPlants,
                                onChanged: widget.readOnly
                                    ? null
                                    : (value) =>
                                        setState(() => keepPlants = value!))),
                        const SizedBox(width: 6),
                        Text(AppLanguage.text('保留植物')),
                      ]),
                      const SizedBox(height: 8),
                      Expanded(child: LayoutBuilder(builder: (_, constraints) {
                        if (constraints.maxWidth < 560) {
                          return Column(children: [
                            SizedBox(
                                height:
                                    math.min(190, constraints.maxHeight * .48),
                                child: FittedBox(
                                    child: SizedBox(
                                        width: 360, child: selectedPreview()))),
                            const SizedBox(height: 12),
                            Expanded(child: mapList()),
                          ]);
                        }
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 242, child: mapList()),
                              const SizedBox(width: 16),
                              Expanded(child: selectedPreview()),
                            ]);
                      })),
                      const SizedBox(height: 8),
                      Text(
                          AppLanguage.text(keepPlants
                              ? '保留植物时，超出新地图范围的植物将被移除。'
                              : '未勾选“保留植物”，切换地图时将清空植物。'),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xff63755f))),
                    ]))));
  }
}
