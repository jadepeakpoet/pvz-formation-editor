// Real Flutter engine session persistence check, temporary SQLite only.
import 'dart:io';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('pvz-empty-draft-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final session = EditorSession(repo);
  try {
    await session.flush();
    await session.flush();
    check((await repo.listArchives()).single.id == session.sourceArchiveId,
        'Untouched empty editor creates an archive');
    session.execute(
        'first plant',
        session.document.copy(pieces: [
          Piece(id: 'first', type: 'pea', row: 0, col: 0, layer: 10)
        ]));
    await session.flush();
    check((await repo.listArchives()).single.id == session.id,
        'First plant creates one identified draft');
    session.execute('clear', session.document.copy(pieces: []));
    await session.flush();
    final saved = (await repo.listArchives()).single;
    check(saved.id == session.id && (saved.document['objects'] as List).isEmpty,
        'Clear retains same previously edited draft');
    stdout.writeln(
        'PASS 3: untouched empty archive; first plant updates same archive; clear keeps same archive/history');
    session.dispose();
    await repo.close();
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    session.dispose();
    await repo.close();
    await dir.delete(recursive: true);
    exit(1);
  }
}
