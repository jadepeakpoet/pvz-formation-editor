// ignore_for_file: invalid_use_of_visible_for_testing_member
// Real Flutter editor + temporary files/SQLite; ONLY file dialog channel mocked.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

late Dialogs dialogs;

class Binding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      dialogs = Dialogs(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      const ViewConfiguration(size: Size(1240, 800), devicePixelRatio: 1);
}

class Dialogs extends BinaryMessenger {
  final BinaryMessenger delegate;
  Dialogs(this.delegate);
  String? pickPath, savePath;
  final calls = <MethodCall>[];
  @override
  Future<ByteData?> send(String channel, ByteData? data) async {
    if (channel != 'pvz_formation_editor/files') {
      return delegate.send(channel, data);
    }
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(data);
    calls.add(call);
    if (call.method == 'chooseSavePath') {
      return codec.encodeSuccessEnvelope(savePath);
    }
    if (call.method == 'pickFormation') {
      return codec.encodeSuccessEnvelope(pickPath == null
          ? null
          : {'path': pickPath, 'bytes': await File(pickPath!).readAsBytes()});
    }
    throw StateError('Unexpected file method ${call.method}');
  }

  @override
  void setMessageHandler(
          String channel, Future<ByteData?>? Function(ByteData?)? handler) =>
      delegate.setMessageHandler(channel, handler);
  @override
  Future<void> handlePlatformMessage(
          String channel, ByteData? data, void Function(ByteData?)? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void walk(Element e, void Function(Element) visit) {
  visit(e);
  e.visitChildren((c) => walk(c, visit));
}

Element? find(bool Function(Widget) predicate) {
  Element? result;
  walk(WidgetsBinding.instance.rootElement!, (e) {
    if (predicate(e.widget)) result = e;
  });
  return result;
}

dynamic get page => (find((w) => w is app.EditorPage) as StatefulElement).state;
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 350));
Future<void> clickText(String text) async {
  final e = find((w) => w is Text && w.data == text);
  check(e != null, 'Missing $text');
  final b = e!.renderObject as RenderBox;
  final p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final dir = await Directory.systemTemp.createTemp('pvz-io-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final report = <String>[];
  var session = EditorSession(repo, name: 'IO smoke');
  Future<void> mount() async {
    runApp(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: app.EditorPage(
            key: ValueKey(session.id),
            session: session,
            continueArchive: (_) async {})));
    await settle();
    await settle();
  }

  ProjectFiles.desktopDialogOverride = ({required save, required name}) async =>
      save ? dialogs.savePath : dialogs.pickPath;
  ExportPreferences.fileOverride = File('${dir.path}/export-preferences.json');
  ExportPreferences.documentsDirectoryOverride = dir;
  try {
    await mount();
    dialogs.savePath = '${dir.path}/default.txt';
    final export = page.exportFormationFile(saveAs: true) as Future<void>;
    await settle();
    final radio = find((w) =>
            w is RadioListTile<FormationFormat> &&
            w.value == FormationFormat.toolkit)!
        .widget as RadioListTile<FormationFormat>;
    check(radio.groupValue == FormationFormat.toolkit,
        'Toolkit selected by default');
    await clickText('选择保存位置');
    await export;
    check(
        await File(dialogs.savePath!).readAsString() ==
            ToolkitCodec.encode(session.document),
        'Default export is Toolkit actualfile');
    report.add('actual format dialog defaults Toolkit and writes Toolkit file');
    dialogs.savePath = '${dir.path}/website.txt';
    await File(dialogs.savePath!).writeAsString('previous website file');
    final websiteExport =
        page.exportFormationFile(saveAs: true) as Future<void>;
    await settle();
    await clickText(FormationFormat.website.label);
    await clickText('选择保存位置');
    await websiteExport;
    check(
        await File(dialogs.savePath!).readAsString() ==
            WebsiteCodec.encode(session.document),
        'Optional Website export');
    check(
        session.lastFileBackup != null &&
            await File(session.lastFileBackup!).readAsString() ==
                'previous website file',
        'SaveAs existing target returns its actual backup association');
    report.add('actual Website format selection writes Website file');
    final webPath = '${dir.path}/import-web.txt';
    const web = '0,0 1 1 0 0 0';
    await File(webPath).writeAsString(web);
    dialogs.pickPath = webPath;
    await page.transfer('import');
    check(
        session.filePath == webPath &&
            session.fileFormat == 'website' &&
            session.document.pieces.length == 1,
        'Website file import metadata');
    session.execute(
        'second plant', WebsiteCodec.decode('0,0 1 1 0 0 0,0 1 2 0 0 0'));
    await page.exportFormationFile(saveAs: false);
    check(await File(session.lastFileBackup!).readAsString() == web,
        'Original file backup exact');
    check(
        WebsiteCodec.decode(await File(webPath).readAsString()).pieces.length ==
            2,
        'Inplace export updated original file');
    report.add(
        'Website import path and inplace save preserve exact previous-file backup');
    await page.transfer('restoreFile');
    check(
        await File(webPath).readAsString() == web &&
            session.document.pieces.length == 1,
        'Restore action restores previous file and current editor document');
    await page.transfer('restoreFile');
    check(
        WebsiteCodec.decode(await File(webPath).readAsString()).pieces.length ==
                2 &&
            session.document.pieces.length == 2,
        'Restore action can be undone through redo backup');
    report.add(
        'actual restore-file action restores document/file and supports redo');
    final toolkitPath = '${dir.path}/import-toolkit.txt';
    await File(toolkitPath)
        .writeAsString(ToolkitCodec.encode(Formation(mapId: 'roof')));
    dialogs.pickPath = toolkitPath;
    await page.transfer('import');
    check(
        session.filePath == toolkitPath &&
            session.fileFormat == 'toolkit' &&
            session.document.mapId == 'roof',
        'Toolkit import exactscene andpath');
    report.add('Toolkit file import detected with exact scene/path');
    final historical = '${dir.path}/历史名阵.txt';
    await File(historical).writeAsString('LI5HDH/tAib/1HrXeldAXDjByF1AjX7kwjV5EJA18df513mXEtPBVT91RHxWRlfGVk91dlZnUYJejHa/VuVRBBhSVDSeSVlW');
    dialogs.pickPath = historical;
    await page.transfer('import');
    check(session.document.mapId == 'pool' && session.document.pieces.length == 86,
        'User historical formation loads through the real editor');
    report.add('user historical famous formation imports 86 objects through editor');
    final source = await repo.saveArchive(
        id: 'original-archive',
        name: session.name,
        document: session.document.toJson());
    await session.markArchived(source.id, session.document.fingerprint);
    final archiveCount = (await repo.listArchives()).length;
    final versionCount = (await repo.listVersions(source.id)).length;
    session.execute('archive edit', session.document.copy(sunValue: 44));
    await page.saveArchive();
    check(
        session.sourceArchiveId == source.id &&
            (await repo.listArchives()).length == archiveCount,
        'Archive save preservesidentity');
    check((await repo.listVersions(source.id)).length == versionCount + 1,
        'Archive update preserves oldversion');
    final saveAs = page.saveArchive(saveAs: true) as Future<void>;
    await settle();
    await clickText('另存为');
    await saveAs;
    check(
        (await repo.listArchives()).length == archiveCount + 1 &&
            session.sourceArchiveId != source.id,
        'Unchanged SaveAs newarchive identity');
    report.add(
        'inplace archive update keeps identity/history; unchanged SaveAs creates independent archive');
    final old = session;
    session = EditorSession(repo,
        id: source.id,
        document: Formation.fromJson(source.document),
        name: source.name,
        readOnly: true,
        sourceArchiveId: source.id);
    await mount();
    old.dispose();
    final readonlyAs = page.saveArchive(saveAs: true) as Future<void>;
    await settle();
    await clickText('另存为');
    await readonlyAs;
    check((await repo.listArchives()).length == archiveCount + 2,
        'Readonly SaveAs creates independent archive');
    check(session.readOnly && session.id == source.id,
        'Readonly source remains readonly unchangedidentity');
    report.add('readonly archive SaveAs preserves source');
    check(errors.isEmpty, 'Flutter errors $errors');
    await File('${Directory.systemTemp.path}/pvz-formation-io-report.json')
        .writeAsString(jsonEncode({
      'pass': report,
      'errors': errors,
      'scope':
          'real Flutter UI/editor/storage; file dialog method channel mocked; no native panel or Windows game assertions'
    }));
    stdout.writeln('PASS ${report.length}: ${report.join('; ')}');
    session.dispose();
    await repo.close();
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
