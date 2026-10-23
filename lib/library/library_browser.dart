import '../platform/app_language.dart';
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import 'library_presets.dart';
import '../editor/board_painter.dart';
import '../storage/formation_repository.dart';

/// Browses snapshots and working copies without embedding an editor.
class LibraryBrowser extends StatefulWidget {
  final List<DraftRecord> drafts;
  final List<ArchiveRecord> archives;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onSettings;
  final VoidCallback onNew, onImportProject, onImportString;
  final void Function(DraftRecord) onOpenDraft;
  final void Function(ArchiveRecord) onOpenArchive;
  final void Function(ArchiveRecord)? onOpenArchiveTab;
  final void Function(DraftRecord)? onOpenDraftTab, onCopyDraft;
  final void Function(String, DraftRecord) onDraftAction;
  final void Function(String, ArchiveRecord) onArchiveAction;
  final String? error;
  final VoidCallback? onImportGameSave;
  final bool showTitle;
  final Future<void> Function(Formation?)? onGameTools;
  final List<LibraryPreset> presets;
  final ValueChanged<LibraryPreset>? onPresetPick;
  final Future<void> Function(LibraryPreset)? onAddPreset;
  final Future<void> Function(String, LibraryPreset)? onPresetAction;
  final Set<String> favoritePresetIds;
  final Future<void> Function(List<ArchiveRecord>)? onExportArchives;
  const LibraryBrowser(
      {super.key,
      required this.drafts,
      required this.archives,
      required this.onRefresh,
      this.onSettings,
      required this.onNew,
      required this.onImportProject,
      required this.onImportString,
      required this.onOpenDraft,
      required this.onOpenArchive,
      required this.onDraftAction,
      required this.onArchiveAction,
      this.onOpenArchiveTab,
      this.onOpenDraftTab,
      this.onCopyDraft,
      this.error,
      this.onGameTools,
      this.onImportGameSave,
      this.showTitle = true,
      this.presets = const [],
      this.onPresetPick,
      this.onAddPreset,
      this.onPresetAction,
      this.onExportArchives,
      this.favoritePresetIds = const {}});
  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _Entry {
  final ArchiveRecord? archive;
  final LibraryPreset? preset;
  final bool presetFavorite;
  _Entry.archive(this.archive)
      : preset = null,
        presetFavorite = false;
  _Entry.preset(this.preset, {this.presetFavorite = false}) : archive = null;
  String get id =>
      '${preset != null ? 'preset' : 'archive'}:${preset?.id ?? archive!.id}';
  String get name => preset?.name ?? archive!.name;
  String get note => archive?.note ?? '';
  bool get favorite => archive?.favorite ?? presetFavorite;
  DateTime get updated => archive?.updatedAt ?? DateTime(2000);
  List<String> get tags => archive?.tags ?? const [];
  Map<String, dynamic> get document =>
      preset?.document.toJson() ?? archive!.document;
  String get mapId => preset?.mapId ?? (document['map'] as String? ?? 'pool');
  late final int cannonCount =
      formation?.pieces.where((p) => p.type == 'cob').length ?? 0;
  Formation? get formation {
    if (preset != null) return preset!.document;
    try {
      return Formation.fromJson(document);
    } catch (_) {
      return null;
    }
  }
}

class _LibraryBrowserState extends State<LibraryBrowser> {
  static const ink = Color(0xff263f35);
  static const green = Color(0xff376b50);
  String section = '我的存档', query = '', sort = '最近修改';
  String mapFilter = '';
  String? tagFilter;
  int? cannonFilter;
  bool filterDialogOpen = false;
  String? addingPreset;
  bool narrowDetails = false;
  bool selectingArchives = false, exportingArchives = false;
  final selectedArchiveIds = <String>{};
  void toggleArchive(String id) => setState(() {
        if (!selectedArchiveIds.add(id)) selectedArchiveIds.remove(id);
      });
  Future<void> exportArchives(List<ArchiveRecord> archives) async {
    if (archives.isEmpty ||
        exportingArchives ||
        widget.onExportArchives == null) return;
    setState(() => exportingArchives = true);
    try {
      await widget.onExportArchives!(List.unmodifiable(archives));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLanguage.text('导出失败：$error'))));
      }
    } finally {
      if (mounted) setState(() => exportingArchives = false);
    }
  }

  Widget archiveSelectionBar() {
    if (section != '我的存档' || widget.onExportArchives == null) {
      return const SizedBox.shrink();
    }
    final visible = filtered
        .where((e) => e.archive != null)
        .map((e) => e.archive!)
        .toList();
    final chosen = widget.archives
        .where((a) => selectedArchiveIds.contains(a.id))
        .toList();
    final visibleIds = visible.map((a) => a.id).toSet();
    final hiddenCount = chosen.where((a) => !visibleIds.contains(a.id)).length;
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!selectingArchives) ...[
                TextButton(
                    key: const ValueKey('library-select-archives'),
                    onPressed: () => setState(() => selectingArchives = true),
                    child: Text(AppLanguage.text('批量选择'))),
                TextButton(
                    key: const ValueKey('library-export-all'),
                    onPressed: exportingArchives || widget.archives.isEmpty
                        ? null
                        : () => exportArchives(widget.archives),
                    child: Text(AppLanguage.text('导出全部'))),
              ] else ...[
                Text(
                    AppLanguage.text(
                        '已选 ${chosen.length}${hiddenCount > 0 ? '（含 $hiddenCount 个筛选外存档）' : ''}'),
                    key: const ValueKey('library-selected-count'),
                    style: const TextStyle(fontSize: 12)),
                TextButton(
                    key: const ValueKey('library-select-all'),
                    onPressed: () => setState(() =>
                        selectedArchiveIds.addAll(visible.map((a) => a.id))),
                    child: Text(AppLanguage.text('全选当前结果'))),
                TextButton(
                    key: const ValueKey('library-export-selected'),
                    onPressed: exportingArchives || chosen.isEmpty
                        ? null
                        : () => exportArchives(chosen),
                    child: Text(AppLanguage.text(
                        exportingArchives ? '正在导出…' : '导出已选'))),
                TextButton(
                    key: const ValueKey('library-selection-cancel'),
                    onPressed: () => setState(() {
                          selectingArchives = false;
                          selectedArchiveIds.clear();
                        }),
                    child: Text(AppLanguage.text('取消'))),
              ]
            ]));
  }

  final narrowListScroll = ScrollController();
  final narrowDetailScroll = ScrollController();
  @override
  void initState() {
    super.initState();
    if (widget.archives.isEmpty && widget.presets.isNotEmpty) section = '预制名阵';
  }

  @override
  void didUpdateWidget(covariant LibraryBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selected != null && !entries.any((e) => e.id == selected)) {
      selected = null;
      narrowDetails = false;
    }
  }

  String? selected;
  bool refreshing = false;
  final searchController = TextEditingController();
  @override
  void dispose() {
    searchController.dispose();
    narrowListScroll.dispose();
    narrowDetailScroll.dispose();
    super.dispose();
  }

  List<_Entry> get entries => [
        ...widget.presets.map((preset) => _Entry.preset(preset,
            presetFavorite: widget.favoritePresetIds.contains(preset.id))),
        ...widget.archives.map(_Entry.archive)
      ];
  int get favoriteCount =>
      widget.archives.where((a) => a.favorite).length +
      widget.presets
          .where((p) => widget.favoritePresetIds.contains(p.id))
          .length;
  bool inSection(_Entry e) =>
      (section == '预制名阵'
          ? e.preset != null
          : section == '收藏' || e.preset == null) &&
      (section != '我的存档' || e.archive != null) &&
      (section != '收藏' || e.favorite);

  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final archive in widget.archives) {
      for (final tag in archive.tags.toSet()) {
        if (tag.trim().isNotEmpty) {
          counts.update(tag, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    return counts;
  }

  void openTag(String? tag) => setState(() {
        section = '我的存档';
        tagFilter = tag;
        query = '';
        searchController.clear();
        mapFilter = '';
        cannonFilter = null;
        selected = null;
        narrowDetails = false;
      });

  Widget tagBrowser() {
    if (section == '预制名阵') return const SizedBox.shrink();
    final counts = tagCounts;
    final tags = counts.keys.toList()..sort();
    return ExpansionTile(
        key: const ValueKey('library-tags'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
        title: Text(
            AppLanguage.text(
                tagFilter == null ? '标签 · ${tags.length}' : '标签 · $tagFilter'),
            style: const TextStyle(fontSize: 12)),
        children: [
          ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 144),
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Wrap(spacing: 5, runSpacing: 4, children: [
                        filterChip(
                            key: 'library-tag-all',
                            label: '全部存档',
                            count: widget.archives.length,
                            selected: tagFilter == null,
                            select: () => openTag(null)),
                        for (final tag in tags)
                          filterChip(
                              key: 'library-tag:$tag',
                              label: tag,
                              count: counts[tag],
                              selected: tagFilter == tag,
                              select: () => openTag(tag)),
                        if (tags.isEmpty)
                          Text(AppLanguage.text('在存档详情中设置标签即可分类。'),
                              style: const TextStyle(fontSize: 11)),
                      ]))))
        ]);
  }

  bool matchesQuery(_Entry e) {
    final q = query.trim().toLowerCase();
    return (tagFilter == null || e.tags.contains(tagFilter)) &&
        (q.isEmpty ||
            [e.name, e.note, ...e.tags].join(' ').toLowerCase().contains(q));
  }

  String get filterSummary => [
        if (tagFilter != null) AppLanguage.text('标签：$tagFilter'),
        if (mapFilter.isNotEmpty)
          AppLanguage.text(BoardMap.byId(mapFilter).name),
        if (cannonFilter != null) cannonLabel(cannonFilter!),
      ].join(' · ');
  void clearFilters() => setState(() {
        tagFilter = null;
        mapFilter = '';
        cannonFilter = null;
      });
  Widget filterChip(
          {required String key,
          required String label,
          int? count,
          required bool selected,
          required VoidCallback select}) =>
      ChoiceChip(
          key: ValueKey(key),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(AppLanguage.text(label), style: const TextStyle(fontSize: 11)),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xffc2d6bc)
                          : const Color(0xffe7ecdf),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(AppLanguage.text('$count阵'),
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xff5d7054))))
            ]
          ]),
          selected: selected,
          onSelected: (_) => select(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          selectedColor: const Color(0xffd6e5d2),
          backgroundColor: const Color(0xfff7f8f3),
          side: BorderSide(color: selected ? green : const Color(0xffdce3d7)));
  String cannonLabel(int count) =>
      AppLanguage.text(count == 0 ? '无炮' : '$count炮');
  Future<void> showFilters() async {
    if (filterDialogOpen) return;
    filterDialogOpen = true;
    final all = entries;
    final base = all.where((e) => inSection(e) && matchesQuery(e)).toList();
    final maps =
        BoardMap.all.where((m) => all.any((e) => e.mapId == m.id)).toList();
    final cannons = {
      0,
      ...all.where(inSection).map((e) => e.cannonCount),
      if (cannonFilter != null) cannonFilter!
    }.toList()
      ..sort();
    var selectedMap = mapFilter;
    int? selectedCannon = cannonFilter;
    try {
      final result = await showDialog<(String, int?)>(
          context: context,
          builder: (dialogContext) =>
              StatefulBuilder(builder: (context, update) {
                final mapBase = base
                    .where((e) =>
                        selectedCannon == null ||
                        e.cannonCount == selectedCannon)
                    .toList();
                final cannonBase = base
                    .where((e) => selectedMap.isEmpty || e.mapId == selectedMap)
                    .toList();
                final count = base
                    .where((e) =>
                        (selectedMap.isEmpty || e.mapId == selectedMap) &&
                        (selectedCannon == null ||
                            e.cannonCount == selectedCannon))
                    .length;
                Widget mapTag(String id, String name, int available) =>
                    filterChip(
                        key: 'library-map-${id.isEmpty ? 'all' : id}',
                        label: name,
                        count: available > 0 ? available : null,
                        selected: selectedMap == id,
                        select: () => update(() => selectedMap = id));
                Widget cannonTag(int? value, int available) => filterChip(
                    key: 'library-cannon-${value ?? 'all'}',
                    label: value == null ? '全部' : cannonLabel(value),
                    count: available > 0 ? available : null,
                    selected: selectedCannon == value,
                    select: () => update(() => selectedCannon = value));
                return Dialog(
                    key: const ValueKey('library-filters-panel'),
                    insetPadding: const EdgeInsets.all(24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: 480,
                            maxHeight: MediaQuery.sizeOf(context).height - 80),
                        child: SizedBox(
                            width: 480,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 12, 8, 8),
                                      child: Row(children: [
                                        const Icon(Icons.tune,
                                            size: 19, color: green),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(
                                                AppLanguage.text('筛选阵型'),
                                                style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                    color: ink))),
                                        IconButton(
                                            key: const ValueKey(
                                                'library-filter-close'),
                                            tooltip: AppLanguage.text('关闭'),
                                            onPressed: () =>
                                                Navigator.pop(dialogContext),
                                            icon: const Icon(Icons.close,
                                                size: 18))
                                      ])),
                                  Flexible(
                                      child: SingleChildScrollView(
                                          key: const ValueKey(
                                              'library-filter-scroll'),
                                          padding: const EdgeInsets.fromLTRB(
                                              20, 4, 20, 16),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(AppLanguage.text('场地'),
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: ink)),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                    key: const ValueKey(
                                                        'library-map-filter'),
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      mapTag('', '全部',
                                                          mapBase.length),
                                                      for (final map
                                                          in maps.where((m) =>
                                                              mapBase.any((e) =>
                                                                  e.mapId ==
                                                                  m.id)))
                                                        mapTag(
                                                            map.id,
                                                            map.name,
                                                            mapBase
                                                                .where((e) =>
                                                                    e.mapId ==
                                                                    map.id)
                                                                .length)
                                                    ]),
                                                const SizedBox(height: 20),
                                                Text(AppLanguage.text('炮数'),
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: ink)),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                    key: const ValueKey(
                                                        'library-cannon-filter'),
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    children: [
                                                      cannonTag(null,
                                                          cannonBase.length),
                                                      for (final value in cannons
                                                          .where((c) => cannonBase
                                                              .any((e) =>
                                                                  e.cannonCount ==
                                                                  c)))
                                                        cannonTag(
                                                            value,
                                                            cannonBase
                                                                .where((e) =>
                                                                    e.cannonCount ==
                                                                    value)
                                                                .length)
                                                    ]),
                                                const SizedBox(height: 14),
                                                Text(
                                                    AppLanguage.text(
                                                        '炮数按实际玉米加农炮数量统计；浅色徽标表示匹配的阵型数量。'),
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        height: 1.6,
                                                        color:
                                                            Color(0xff7b8975)))
                                              ]))),
                                  const Divider(
                                      height: 1, color: Color(0xffe0e6d9)),
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 12, 16, 12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 4, bottom: 8),
                                                child: Text(
                                                    AppLanguage.text(
                                                        '匹配 $count 个阵型'),
                                                    key: const ValueKey(
                                                        'library-filter-count'),
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: green))),
                                            Row(children: [
                                              TextButton(
                                                  key: const ValueKey(
                                                      'library-filter-reset'),
                                                  onPressed: () => update(() {
                                                        selectedMap = '';
                                                        selectedCannon = null;
                                                      }),
                                                  child: Text(
                                                      AppLanguage.text('重置'))),
                                              const Spacer(),
                                              TextButton(
                                                  key: const ValueKey(
                                                      'library-filter-cancel'),
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dialogContext),
                                                  child: Text(
                                                      AppLanguage.text('取消'))),
                                              const SizedBox(width: 8),
                                              FilledButton(
                                                  key: const ValueKey(
                                                      'library-filter-apply'),
                                                  style: FilledButton.styleFrom(
                                                      backgroundColor: green),
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dialogContext, (
                                                        selectedMap,
                                                        selectedCannon
                                                      )),
                                                  child: Text(
                                                      AppLanguage.text('确定')))
                                            ])
                                          ]))
                                ]))));
              }));
      if (result != null && mounted) {
        setState(() {
          mapFilter = result.$1;
          cannonFilter = result.$2;
        });
      }
    } finally {
      filterDialogOpen = false;
    }
  }

  Widget filterControls() => SizedBox(
      height: 28,
      child: Row(children: [
        TextButton.icon(
            key: const ValueKey('library-filter-toggle'),
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 26),
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            onPressed: showFilters,
            icon: const Icon(Icons.tune, size: 16),
            label: Text(AppLanguage.text('筛选'),
                style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
                AppLanguage.text(
                    filterSummary.isEmpty ? '场地 · 炮数' : filterSummary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: filterSummary.isEmpty
                        ? const Color(0xff83907c)
                        : green))),
        if (mapFilter.isNotEmpty || cannonFilter != null)
          TextButton(
              key: const ValueKey('library-clear-filters'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 26),
                  padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: clearFilters,
              child: Text(AppLanguage.text('清除筛选'),
                  style: const TextStyle(fontSize: 11)))
      ]));

  List<_Entry> get filtered {
    final list = entries
        .where((e) =>
            inSection(e) &&
            (mapFilter.isEmpty || e.mapId == mapFilter) &&
            (cannonFilter == null || e.cannonCount == cannonFilter) &&
            matchesQuery(e))
        .toList();
    list.sort((a, b) {
      if (sort == '名称') return a.name.compareTo(b.name);
      if (sort == '收藏优先' && a.favorite != b.favorite) {
        return a.favorite ? -1 : 1;
      }
      final modified = b.updated.compareTo(a.updated);
      if (modified != 0) return modified;
      if (a.preset != null && b.preset != null) {
        final ai = int.tryParse(a.preset!.id.split('-').last) ?? 0;
        final bi = int.tryParse(b.preset!.id.split('-').last) ?? 0;
        return ai.compareTo(bi);
      }
      return a.id.compareTo(b.id);
    });
    return list;
  }

  Future<void> refresh() async {
    setState(() => refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  String date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  Future<void> presetAction(String value, _Entry e) async {
    if (value == 'copy' && addingPreset != null) return;
    if (value == 'copy') setState(() => addingPreset = e.id);
    try {
      if (widget.onPresetAction != null) {
        await widget.onPresetAction!(value, e.preset!);
        if (mounted && (value == 'open-current' || value == 'open-tab')) {
          setState(() {
            narrowDetails = false;
            selected = null;
          });
        }
      } else if (value == 'copy' && widget.onAddPreset != null) {
        await widget.onAddPreset!(e.preset!);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLanguage.text('名阵操作失败：$error'))));
      }
    } finally {
      if (value == 'copy' && mounted) setState(() => addingPreset = null);
    }
  }

  void action(String value, _Entry e) {
    if (e.preset != null) {
      presetAction(value, e);
      return;
    }
    widget.onArchiveAction(value, e.archive!);
  }

  Widget preview(_Entry e) {
    final f = e.formation;
    return AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: ColoredBox(
                color: const Color(0xffe5eadf),
                child: f == null
                    ? const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey))
                    : RepaintBoundary(
                        child: CustomPaint(
                            painter:
                                BoardPainter(document: f, helpers: false))))));
  }

  List<PopupMenuEntry<String>> menuItems(_Entry e) {
    final labels = e.preset != null
        ? {
            'open-current': '当前标签页使用模板',
            'open-tab': '新标签页使用模板',
            'copy-code': '复制 Toolkit 阵型码',
            'copy-image': '复制图片',
            'export-image': '导出图片',
            'preview': '只读预览',
            'favorite': e.favorite ? '取消收藏' : '收藏',
            'copy': '加入我的存档',
            'export': '导出完整项目',
          }
        : {
            'open-current': '当前标签页打开',
            if (widget.onOpenArchiveTab != null) 'open-tab': '新标签页打开',
            'copy-code': '复制 Toolkit 阵型码',
            'copy-image': '复制图片',
            'export-image': '导出图片',
            'preview': '只读预览',
            'rename': '重命名',
            'tags': '设置标签',
            'metadata': '名称、备注、标签',
            'favorite': e.favorite ? '取消收藏' : '收藏',
            'copy': '另存为副本',
            'versions': '历史版本与回退',
            'export': '导出完整项目',
            'delete': '删除存档',
          };
    return labels.entries
        .map((item) => PopupMenuItem(
            value: item.key,
            enabled: e.preset == null ||
                widget.onPresetAction != null ||
                (item.key == 'copy' && widget.onAddPreset != null),
            child: Text(AppLanguage.text(item.value))))
        .toList();
  }

  PopupMenuButton<String> menu(_Entry e) => PopupMenuButton<String>(
      key: ValueKey('library-menu-${e.id}'),
      tooltip: AppLanguage.text('更多操作'),
      onSelected: (value) => action(value, e),
      itemBuilder: (_) => menuItems(e));
  Future<void> contextMenu(_Entry e, Offset position) async {
    setState(() => selected = e.id);
    final bounds = Offset.zero & MediaQuery.sizeOf(context);
    final value = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            Rect.fromLTWH(position.dx, position.dy, 0, 0), bounds),
        items: menuItems(e));
    if (value != null && mounted) action(value, e);
  }

  Widget rail(bool compact) => Container(
      width: compact ? 64 : 130,
      decoration: const BoxDecoration(
          color: Color(0xffedf2e9),
          border: Border(right: BorderSide(color: Color(0xffdde4d8)))),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 6, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: EdgeInsets.only(left: compact ? 12 : 10, bottom: 18),
            child: Row(children: [
              const Icon(Icons.grass_rounded, color: green, size: 28),
              if (!compact) ...[
                const SizedBox(width: 9),
                Text(AppLanguage.text('阵型收藏'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: ink))
              ]
            ])),
        for (final item in [
          ('预制名阵', Icons.auto_awesome_outlined, widget.presets.length),
          ('我的存档', Icons.inventory_2_outlined, widget.archives.length),
          ('收藏', Icons.star_outline_rounded, favoriteCount)
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Tooltip(
                  message: AppLanguage.text(item.$1),
                  child: Material(
                      color: section == item.$1
                          ? const Color(0xffd6e5d2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                          key: ValueKey('library-section-${item.$1}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() {
                                section = item.$1;
                                tagFilter = null;
                              }),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 10),
                              child: Row(children: [
                                Icon(item.$2, size: 21, color: ink),
                                if (!compact) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(AppLanguage.text(item.$1),
                                          style: const TextStyle(
                                              color: ink, fontSize: 12))),
                                  Text('${item.$3}',
                                      style: const TextStyle(
                                          color: green, fontSize: 12))
                                ]
                              ])))))),
        const Spacer(),
        if (!compact)
          Padding(
              padding: const EdgeInsets.all(10),
              child: Text(AppLanguage.text('自动保存修改\n历史版本可回退'),
                  style: const TextStyle(
                      fontSize: 12, height: 1.8, color: Color(0xff6a7a6b))))
      ]));
  Widget header() => Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.showTitle)
                Text(AppLanguage.text('存档库'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
              FilledButton.icon(
                  key: const ValueKey('library-new'),
                  onPressed: widget.onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(AppLanguage.text('新建阵型'))),
              PopupMenuButton<String>(
                  key: const ValueKey('library-import'),
                  tooltip: AppLanguage.text('导入'),
                  onSelected: (v) {
                    if (v == 'game-save') {
                      widget.onImportGameSave?.call();
                    } else if (v == 'project') {
                      widget.onImportProject();
                    } else {
                      widget.onImportString();
                    }
                  },
                  itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'project',
                            child: Text(AppLanguage.text('导入项目文件'))),
                        PopupMenuItem(
                            value: 'string',
                            child: Text(AppLanguage.text('导入阵型字符串'))),
                        if (widget.onImportGameSave != null)
                          PopupMenuItem(
                              key: const ValueKey('library-import-game-save'),
                              value: 'game-save',
                              child: Text(AppLanguage.text('导入PC无尽存档（实验）'))),
                      ],
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.file_download_outlined, size: 19),
                        const SizedBox(width: 6),
                        Text(AppLanguage.text('导入')),
                        const Icon(Icons.arrow_drop_down, size: 18)
                      ]))),
              if (widget.onGameTools != null)
                TextButton.icon(
                    key: const ValueKey('library-game-tools'),
                    onPressed: () => widget.onGameTools!(null),
                    icon: const Icon(Icons.sports_esports_outlined, size: 17),
                    label: Text(AppLanguage.text('游戏存档'))),
              if (widget.onSettings != null) settingsButton(),
              IconButton(
                  key: const ValueKey('library-refresh'),
                  tooltip: AppLanguage.text('刷新存档库'),
                  onPressed: refreshing ? null : refresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 21))
            ]),
        const SizedBox(height: 5),
        Text(AppLanguage.text('整理你的布阵灵感，随时接着上一次创作。'),
            style: const TextStyle(color: Color(0xff6a786c), fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: searchController,
                  key: const ValueKey('library-search'),
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                      hintText: AppLanguage.text('搜索名称、备注或标签'),
                      prefixIcon: const Icon(Icons.search, size: 21),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xffdce3d7)))))),
          const SizedBox(width: 12),
          DropdownButton<String>(
              key: const ValueKey('library-sort'),
              value: sort,
              underline: const SizedBox(),
              items: ['最近修改', '名称', '收藏优先']
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                          AppLanguage.text(
                              section == '预制名阵' && s == '最近修改' ? '原站顺序' : s),
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setState(() => sort = v!))
        ]),
        const SizedBox(height: 6),
        filterControls(),
        tagBrowser(),
        if (widget.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(AppLanguage.text(widget.error!),
                  key: const ValueKey('library-error'),
                  style: const TextStyle(color: Colors.red)))
      ]));
  Widget empty() => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                query.trim().isNotEmpty
                    ? Icons.search_off_rounded
                    : Icons.spa_outlined,
                size: 48,
                color: const Color(0xff8da28a)),
            const SizedBox(height: 16),
            Text(
                AppLanguage.text(cannonFilter != null
                    ? '没有符合筛选条件的阵型'
                    : mapFilter.isNotEmpty
                        ? '此场地下暂无阵型'
                        : query.trim().isNotEmpty
                            ? '没有找到匹配的阵型'
                            : section == '收藏'
                                ? '把喜欢的阵型留在这里'
                                : '你的阵型故事，从这里开始'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: ink)),
            const SizedBox(height: 8),
            Text(
                AppLanguage.text(cannonFilter != null
                    ? '试试其他场地或炮数，也可以清除筛选。'
                    : mapFilter.isNotEmpty
                        ? '换一个场地，或清除场地筛选查看全部阵型。'
                        : query.trim().isNotEmpty
                            ? '试试其他名称、备注或标签。'
                            : section == '收藏'
                                ? '在存档详情中点亮星标，方便下次找到。'
                                : '新建阵型或导入已有作品，开始整理你的布阵。'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xff6a786c), height: 1.6)),
            const SizedBox(height: 12),
            if (mapFilter.isNotEmpty)
              TextButton(
                  key: const ValueKey('library-clear-map-filter'),
                  onPressed: () => setState(() => mapFilter = ''),
                  child: Text(AppLanguage.text('清除场地筛选'))),
            if (cannonFilter != null)
              TextButton(
                  key: const ValueKey('library-clear-cannon-filter'),
                  onPressed: () => setState(() => cannonFilter = null),
                  child: Text(AppLanguage.text('清除炮数筛选'))),
            if (query.trim().isNotEmpty)
              TextButton(
                  key: const ValueKey('library-clear-search'),
                  onPressed: () {
                    searchController.clear();
                    setState(() => query = '');
                  },
                  child: Text(AppLanguage.text('清除搜索')))
            else if (mapFilter.isEmpty && cannonFilter == null)
              OutlinedButton.icon(
                  onPressed: widget.onNew,
                  icon: const Icon(Icons.add),
                  label: Text(AppLanguage.text('新建阵型')))
          ])));
  Widget tile(_Entry e, {bool active = false, bool narrow = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
          color: active ? const Color(0xffeaf2e6) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side:
                  BorderSide(color: active ? green : const Color(0xffe1e6dd))),
          child: InkWell(
              key: ValueKey('library-item-${e.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (widget.onPresetPick != null && e.preset != null) {
                  widget.onPresetPick!(e.preset!);
                  return;
                }
                if (selectingArchives &&
                    section == '我的存档' &&
                    e.archive != null) {
                  toggleArchive(e.archive!.id);
                  return;
                }
                if (narrow && narrowDetailScroll.hasClients) {
                  narrowDetailScroll.jumpTo(0);
                }
                setState(() {
                  selected = e.id;
                  if (narrow) narrowDetails = true;
                });
              },
              onSecondaryTapDown: (details) =>
                  contextMenu(e, details.globalPosition),
              child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    if (selectingArchives &&
                        section == '我的存档' &&
                        e.archive != null)
                      Checkbox(
                          key: ValueKey('library-select-${e.archive!.id}'),
                          value: selectedArchiveIds.contains(e.archive!.id),
                          onChanged: (_) => toggleArchive(e.archive!.id),
                          visualDensity: VisualDensity.compact),
                    SizedBox(width: narrow ? 88 : 80, child: preview(e)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.name,
                              maxLines: narrow ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, color: ink)),
                          const SizedBox(height: 6),
                          Text(
                              AppLanguage.text(
                                  '${narrow ? '' : '${AppLanguage.text(e.preset != null ? '预制名阵' : '存档')} · '}${AppLanguage.text(e.formation?.map.name ?? '未知场景')} · ${cannonLabel(e.cannonCount)}'),
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xff6a786c))),
                          if (!narrow) ...[
                            const SizedBox(height: 5),
                            Text(
                                AppLanguage.text(e.preset != null
                                    ? '原站经典布局'
                                    : date(e.updated)),
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xff899286)))
                          ]
                        ])),
                    if (e.favorite)
                      const Icon(Icons.star_rounded,
                          size: 18, color: Color(0xffb18a31)),
                    if (widget.onPresetPick == null)
                      menu(e)
                    else
                      const Icon(Icons.arrow_forward_rounded,
                          size: 18, color: green)
                  ])))));
  Widget detail(_Entry e, {bool bordered = true, bool narrow = false}) =>
      Container(
          width: narrow ? double.infinity : 230,
          decoration: BoxDecoration(
              color: Colors.white,
              border: bordered
                  ? const Border(left: BorderSide(color: Color(0xffe1e6dd)))
                  : null),
          child: SingleChildScrollView(
              key: const ValueKey('library-detail-scroll'),
              controller: narrow ? narrowDetailScroll : null,
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(
                              AppLanguage.text(
                                  e.preset != null ? '预制名阵' : '存档详情'),
                              style: const TextStyle(
                                  color: Color(0xff72816f), fontSize: 12))),
                      if (e.archive != null || e.preset != null)
                        IconButton(
                            key: const ValueKey('library-favorite'),
                            tooltip:
                                AppLanguage.text(e.favorite ? '取消收藏' : '收藏'),
                            onPressed: e.preset != null &&
                                    widget.onPresetAction == null
                                ? null
                                : () => action('favorite', e),
                            icon: Icon(
                                e.favorite
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                color: e.favorite
                                    ? const Color(0xffb18a31)
                                    : green)),
                      if (widget.onPresetPick == null)
                        menu(e)
                      else
                        const Icon(Icons.arrow_forward_rounded,
                            size: 18, color: green)
                    ]),
                    const SizedBox(height: 8),
                    if (narrow)
                      SizedBox(
                          height: 180,
                          child: Center(
                              child: SizedBox(width: 240, child: preview(e))))
                    else
                      preview(e),
                    const SizedBox(height: 12),
                    Text(e.name,
                        key: const ValueKey('library-detail-name'),
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: ink)),
                    const SizedBox(height: 10),
                    Text(
                        AppLanguage.text(
                            '${AppLanguage.text(e.formation?.map.name ?? '未知场景')} · ${cannonLabel(e.cannonCount)} · ${e.formation?.pieces.length ?? 0} 个对象'),
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xff63755f))),
                    const SizedBox(height: 6),
                    Text(
                        AppLanguage.text(e.preset != null
                            ? '原站经典布阵 · 完整阵型'
                            : '修改于 ${date(e.updated)}'),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xff85917e))),
                    if (widget.onGameTools != null && e.formation != null)
                      TextButton.icon(
                          key: const ValueKey('library-apply-game'),
                          onPressed: () => widget.onGameTools!(e.formation),
                          icon: const Icon(Icons.sports_esports_outlined,
                              size: 16),
                          label: Text(AppLanguage.text('应用到游戏'))),
                    const SizedBox(height: 12),
                    if (e.preset != null) ...[
                      Text(AppLanguage.text('使用模板会创建可编辑副本。也可以直接收藏模板或加入我的存档。'),
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: Color(0xff71806c))),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              key: const ValueKey('library-open-current'),
                              onPressed: widget.onPresetAction == null
                                  ? null
                                  : () => action('open-current', e),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: Text(AppLanguage.text('当前标签页使用模板')))),
                      const SizedBox(height: 8),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              key: const ValueKey('library-open-tab'),
                              onPressed: widget.onPresetAction == null
                                  ? null
                                  : () => action('open-tab', e),
                              icon: const Icon(Icons.tab_outlined, size: 18),
                              label: Text(AppLanguage.text('新标签页使用模板')))),
                      TextButton.icon(
                          key: const ValueKey('library-copy-code'),
                          onPressed: widget.onPresetAction == null
                              ? null
                              : () => action('copy-code', e),
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(AppLanguage.text('复制 Toolkit 阵型码'))),
                      const SizedBox(height: 6),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              key: const ValueKey('library-add-preset'),
                              onPressed: (widget.onPresetAction == null &&
                                          widget.onAddPreset == null) ||
                                      addingPreset != null
                                  ? null
                                  : () => action('copy', e),
                              icon: const Icon(Icons.add, size: 16),
                              label: Text(AppLanguage.text(
                                  addingPreset == e.id ? '正在加入…' : '加入我的存档')))),
                    ] else if (e.archive != null) ...[
                      Text(AppLanguage.text('备注'),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ink)),
                      const SizedBox(height: 7),
                      Text(
                          e.note.isEmpty
                              ? AppLanguage.text('还没有备注，添加一些布阵思路吧。')
                              : e.note,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Color(0xff71806c))),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: e.tags
                              .map((t) => ActionChip(
                                  key: ValueKey('library-detail-tag:$t'),
                                  onPressed: () => openTag(t),
                                  label: Text(t,
                                      style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  side: BorderSide.none,
                                  backgroundColor: const Color(0xffeef3e9)))
                              .toList()),
                      TextButton.icon(
                          key: const ValueKey('library-edit-tags'),
                          onPressed: () => action('tags', e),
                          icon: const Icon(Icons.label_outline, size: 16),
                          label: Text(AppLanguage.text('设置标签'))),
                      TextButton(
                          key: const ValueKey('library-edit-metadata'),
                          onPressed: () => action('metadata', e),
                          child: Text(AppLanguage.text('编辑名称、备注与标签'))),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              key: const ValueKey('library-open-current'),
                              onPressed: () => widget.onOpenArchive(e.archive!),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: Text(AppLanguage.text('当前标签页打开')))),
                      if (widget.onOpenArchiveTab != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                                key: const ValueKey('library-open-tab'),
                                onPressed: () =>
                                    widget.onOpenArchiveTab!(e.archive!),
                                icon: const Icon(Icons.tab_outlined, size: 18),
                                label: Text(AppLanguage.text('新标签页打开')))),
                      ],
                      TextButton.icon(
                          key: const ValueKey('library-copy-code'),
                          onPressed: () => action('copy-code', e),
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(AppLanguage.text('复制 Toolkit 阵型码'))),
                      const SizedBox(height: 10),
                      Text(AppLanguage.text('保存可更新原存档并保留历史；另存为可创建独立副本。'),
                          style: const TextStyle(
                              fontSize: 11,
                              height: 1.6,
                              color: Color(0xff85917e)))
                    ]
                  ])));
  List<PopupMenuEntry<String>> importItems() => [
        PopupMenuItem(
            value: 'project', child: Text(AppLanguage.text('导入项目文件'))),
        PopupMenuItem(
            value: 'string', child: Text(AppLanguage.text('导入阵型字符串'))),
        if (widget.onImportGameSave != null)
          PopupMenuItem(
              key: const ValueKey('library-import-game-save'),
              value: 'game-save',
              child: Text(AppLanguage.text('导入PC无尽存档（实验）'))),
      ];
  void importSelected(String value) {
    if (value == 'game-save') {
      widget.onImportGameSave?.call();
    } else if (value == 'project') {
      widget.onImportProject();
    } else {
      widget.onImportString();
    }
  }

  Widget narrowCategories() => Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xffdfe5d8)))),
      child: Row(children: [
        for (final category in [
          ('预制名阵', '预制', widget.presets.length),
          ('我的存档', '我的', widget.archives.length),
          ('收藏', '收藏', favoriteCount)
        ])
          Expanded(
              child: Tooltip(
                  message: AppLanguage.text(category.$1),
                  child: InkWell(
                      key: ValueKey('library-section-${category.$1}'),
                      onTap: () => setState(() {
                            section = category.$1;
                            tagFilter = null;
                          }),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: section == category.$1
                                          ? green
                                          : Colors.transparent,
                                      width: 2))),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(AppLanguage.text(category.$2),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: section == category.$1
                                            ? green
                                            : const Color(0xff6d7b66),
                                        fontWeight: section == category.$1
                                            ? FontWeight.w600
                                            : FontWeight.w400)),
                                const SizedBox(width: 5),
                                Text('${category.$3}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xff87927e)))
                              ])))))
      ]));
  Widget settingsButton() => IconButton(
      key: const ValueKey('library-settings'),
      tooltip: AppLanguage.text('设置'),
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        try {
          await widget.onSettings?.call();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLanguage.text('无法打开设置：$error'))));
          }
        }
      },
      icon: const Icon(Icons.settings_outlined, size: 19));
  Widget narrowHeader() => Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 2),
      child: Row(children: [
        if (widget.showTitle) ...[
          const Icon(Icons.grass_rounded, size: 21, color: green),
          const SizedBox(width: 6),
          Expanded(
              child: Text(AppLanguage.text('存档库'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: ink))),
        ],
        TextButton.icon(
            key: const ValueKey('library-new'),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            onPressed: widget.onNew,
            icon: const Icon(Icons.add, size: 16),
            label: Text(AppLanguage.text('新建'),
                style: const TextStyle(fontSize: 12))),
        PopupMenuButton<String>(
            key: const ValueKey('library-import'),
            tooltip: AppLanguage.text('导入'),
            padding: const EdgeInsets.all(6),
            iconSize: 19,
            icon: const Icon(Icons.file_download_outlined),
            onSelected: importSelected,
            itemBuilder: (_) => importItems()),
        if (!widget.showTitle) const Spacer(),
        if (widget.onGameTools != null)
          IconButton(
              key: const ValueKey('library-game-tools'),
              tooltip: AppLanguage.text('游戏存档'),
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onGameTools!(null),
              icon: const Icon(Icons.sports_esports_outlined, size: 19)),
        if (widget.onSettings != null) settingsButton(),
        IconButton(
            key: const ValueKey('library-refresh'),
            tooltip: AppLanguage.text('刷新存档库'),
            visualDensity: VisualDensity.compact,
            onPressed: refreshing ? null : refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                : const Icon(Icons.refresh, size: 19))
      ]));
  Widget narrowSearch() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 4),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      key: const ValueKey('library-search'),
                      controller: searchController,
                      onChanged: (v) => setState(() => query = v),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                          hintText: AppLanguage.text('搜索名称、备注或标签'),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 34),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xffdce3d7)))))),
              const SizedBox(width: 4),
              TextButton.icon(
                  key: const ValueKey('library-filter-toggle'),
                  onPressed: showFilters,
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 7)),
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text(AppLanguage.text('筛选'),
                      style: const TextStyle(fontSize: 12))),
              PopupMenuButton<String>(
                  key: const ValueKey('library-sort'),
                  tooltip: AppLanguage.text('排序'),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.sort, size: 20),
                  onSelected: (v) => setState(() => sort = v),
                  itemBuilder: (_) => ['最近修改', '名称', '收藏优先']
                      .map((v) => CheckedPopupMenuItem(
                          value: v,
                          checked: sort == v,
                          child: Text(AppLanguage.text(
                              section == '预制名阵' && v == '最近修改' ? '原站顺序' : v))))
                      .toList())
            ])),
        tagBrowser(),
        if (filterSummary.isNotEmpty)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              child: Row(children: [
                Expanded(
                    child: Text(AppLanguage.text(filterSummary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: green))),
                SizedBox(
                    height: 25,
                    child: TextButton(
                        key: const ValueKey('library-clear-filters'),
                        onPressed: clearFilters,
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 6)),
                        child: Text(AppLanguage.text('清除筛选'),
                            style: const TextStyle(fontSize: 11))))
              ])),
        if (widget.error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(AppLanguage.text(widget.error!),
                  key: const ValueKey('library-error'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.red)))
      ]);
  Widget narrowBody(List<_Entry> list, _Entry? picked) => IndexedStack(
          index: narrowDetails && picked != null ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            ExcludeFocus(
                excluding: narrowDetails && picked != null,
                child: Column(
                    key: const ValueKey('library-narrow-list'),
                    children: [
                      narrowHeader(),
                      narrowCategories(),
                      narrowSearch(),
                      archiveSelectionBar(),
                      Expanded(
                          child: list.isEmpty
                              ? empty()
                              : ListView.builder(
                                  key: const ValueKey('library-results'),
                                  controller: narrowListScroll,
                                  padding:
                                      const EdgeInsets.fromLTRB(10, 4, 10, 12),
                                  itemCount: list.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == 0) {
                                      return Padding(
                                          padding: const EdgeInsets.only(
                                              left: 2, bottom: 7),
                                          child: Text(
                                              AppLanguage.text(
                                                  '共 ${list.length} 个阵型'),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xff89947f))));
                                    }
                                    final entry = list[index - 1];
                                    return tile(entry,
                                        active: entry.id == picked?.id,
                                        narrow: true);
                                  }))
                    ])),
            if (picked == null)
              const SizedBox.shrink()
            else
              ExcludeFocus(
                  excluding: !narrowDetails,
                  child: Column(
                      key: const ValueKey('library-narrow-detail'),
                      children: [
                        Container(
                            height: 42,
                            decoration: const BoxDecoration(
                                color: Color(0xffedf2e8),
                                border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xffdce4d6)))),
                            child: Row(children: [
                              IconButton(
                                  key: const ValueKey('library-detail-back'),
                                  tooltip: AppLanguage.text('返回列表'),
                                  onPressed: () =>
                                      setState(() => narrowDetails = false),
                                  icon: const Icon(Icons.arrow_back, size: 19)),
                              Expanded(
                                  child: Text(picked.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: ink))),
                              const SizedBox(width: 12)
                            ])),
                        Expanded(
                            child:
                                detail(picked, bordered: false, narrow: true))
                      ]))
          ]);
  @override
  Widget build(BuildContext context) => Theme(
      data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: green),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 12))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 12))),
          scaffoldBackgroundColor: const Color(0xfff7f8f3)),
      child: Scaffold(body: LayoutBuilder(builder: (context, c) {
        final list = filtered;
        if (widget.onPresetPick != null) {
          return Column(children: [
            narrowSearch(),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(AppLanguage.text('共 ${list.length} 个阵型 · 点击在当前页打开'),
                    style: const TextStyle(fontSize: 12, color: green))),
            Expanded(
                child: list.isEmpty
                    ? empty()
                    : ListView.builder(
                        key: const ValueKey('preset-picker-results'),
                        padding: const EdgeInsets.all(12),
                        itemCount: list.length,
                        itemBuilder: (_, i) => tile(list[i], narrow: true))),
          ]);
        }
        _Entry? picked;
        for (final e in list) {
          if (e.id == selected) {
            picked = e;
            break;
          }
        }
        picked ??= list.isEmpty ? null : list.first;
        if (c.maxWidth <= 500) return narrowBody(list, picked);
        final wide = c.maxWidth >= 760;
        return Row(children: [
          rail(c.maxWidth < 860),
          Expanded(
              child: Column(children: [
            header(),
            archiveSelectionBar(),
            Expanded(
                child: list.isEmpty
                    ? empty()
                    : LayoutBuilder(
                        builder: (context, inner) => ListView.builder(
                            key: const ValueKey('library-results'),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: 1 +
                                list.length +
                                (!wide && picked != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                        AppLanguage.text(
                                            '${AppLanguage.text(section)} · ${list.length} 项'),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xff7c8976))));
                              }
                              if (index <= list.length) {
                                final e = list[index - 1];
                                return tile(e, active: e.id == picked?.id);
                              }
                              return detail(picked!, bordered: false);
                            })))
          ])),
          if (wide && picked != null) detail(picked)
        ]);
      })));
}
