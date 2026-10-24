import 'dart:convert';
import 'formation.dart';
import 'toolkit_codec.dart';
import 'website_codec.dart';
import 'plant_game_state.dart';
import 'placement_layout.dart';

enum FormationFormat {
  toolkit,
  website,
  project;

  String get label {
    switch (this) {
      case toolkit:
        return 'PvZ Toolkit 阵型字符串';
      case website:
        return '原网页阵型字符串';
      case project:
        return '完整项目 JSON';
    }
  }

  String get description {
    switch (this) {
      case toolkit:
        return '仅保存场地、格位植物、睡眠和模仿者；不保存阳光、卡槽、显示设置或动画帧。';
      case website:
        return '保存原网页支持的布局和视觉字段（含蘑菇睡眠外观）；不保存阳光、卡槽和显示设置。';
      case project:
        return '完整保存编辑器项目，包括阳光、卡槽、显示设置和对象属性。';
    }
  }

  String get fileExtension => this == project ? 'pvzf.json' : 'txt';
}

/// One import boundary for current interchange and legacy project formats.
class FormationExchange {
  /// Keep game appearances that the compact Toolkit layout cannot express.
  static String encodeGameRead(Formation document) {
    final compact = layoutDocument(document);
    for (var i = 0; i < document.pieces.length; i++) {
      if (PlantGameState.of(document.pieces[i]) !=
          PlantGameState.of(compact.pieces[i])) {
        return encode(document, format: FormationFormat.website);
      }
    }
    return ToolkitCodec.encode(compact);
  }

  static FormationFormat detectFormat(String value) {
    final text = value.replaceFirst(RegExp(r'^\s*\uFEFF'), '').trim();
    if (text.startsWith('{') || text.startsWith('PVZF1:')) {
      return FormationFormat.project;
    }
    if (RegExp(r'^[0-9]+(?:,|$)').hasMatch(text)) {
      return FormationFormat.website;
    }
    return FormationFormat.toolkit;
  }

  static Formation decode(String value) {
    final text = value.replaceFirst(RegExp(r'^\s*\uFEFF'), '').trim();
    if (utf8.encode(text).length > ProjectCodec.maxBytes) {
      throw const FormatException('阵型文件超过 8 MiB');
    }
    if (text.isEmpty) throw const FormatException('阵型内容为空');
    if (text.startsWith('{')) return ProjectCodec.decode(text);
    if (text.startsWith('PVZF1:')) return ProjectCodec.fromAppString(text);
    if (RegExp(r'^[0-9]+(?:,|$)').hasMatch(text)) {
      return WebsiteCodec.decode(text);
    }
    return ToolkitCodec.decode(text);
  }

  /// Placement-code exports intentionally omit editor/game session metadata.
  /// Project export preserves the original document unchanged.
  static Formation layoutDocument(Formation document,
      {FormationFormat format = FormationFormat.toolkit}) {
    if (format == FormationFormat.project) return document;
    if (format == FormationFormat.toolkit) {
      document = PlacementLayout.prepare(document).document;
    }
    return document.copy(
      seedSlots: const [],
      imitaterSeedSlots: const {},
      sunValue: 9990,
      fogColumns: 0,
      display: Formation().display,
      pieces: format == FormationFormat.toolkit
          ? document.pieces.map((piece) {
              final json = piece.toJson()
                ..remove('websiteFields')
                // Strip animation frames without discarding the state that
                // was expressed by a mushroom's visible row.
                ..['asleep'] = piece.asleep
                ..['frameRow'] = Piece.mushroomTypes.contains(piece.type) &&
                        !piece.asleep ? 1 : 0
                ..['frameCol'] = 0;
              return Piece.fromJson(json);
            }).toList()
          : document.pieces,
    );
  }

  static String encode(Formation document,
      {FormationFormat format = FormationFormat.toolkit}) {
    document = layoutDocument(document, format: format);
    switch (format) {
      case FormationFormat.toolkit:
        return ToolkitCodec.encode(document);
      case FormationFormat.website:
        return WebsiteCodec.encode(document);
      case FormationFormat.project:
        return ProjectCodec.encode(document);
    }
  }

  static List<String> exportIssues(Formation document,
      {FormationFormat format = FormationFormat.toolkit}) {
    document = layoutDocument(document, format: format);
    switch (format) {
      case FormationFormat.toolkit:
        return ToolkitCodec.exportIssues(document);
      case FormationFormat.website:
        return WebsiteCodec.exportIssues(document);
      case FormationFormat.project:
        return const [];
    }
  }
}
