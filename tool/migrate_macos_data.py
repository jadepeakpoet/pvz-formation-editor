"""Copy a closed legacy macOS library safely; never merge or overwrite user data.

The caller must gracefully close both old and new apps before invoking this tool.
SQLite's backup API includes committed WAL contents; copying the main file alone
would not. Source libraries and both pre-migration snapshots are retained.
"""
from __future__ import annotations

import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import time


USER_TABLES = ('archives', 'drafts', 'archive_versions')


def _read_only(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=5)


def _manifest(connection: sqlite3.Connection) -> dict:
    check = connection.execute('PRAGMA integrity_check').fetchall()
    if check != [('ok',)]:
        raise ValueError('Database integrity check failed')
    tables = {row[0] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    if not set(USER_TABLES).issubset(tables):
        raise ValueError('Not a formation library: required tables missing')
    version = connection.execute('PRAGMA user_version').fetchone()[0]
    if not 0 <= version <= 4:
        raise ValueError(f'Unsupported library schema version: {version}')
    counts = {name: connection.execute(
        'SELECT count(*) FROM "' + name.replace('"', '""') + '"').fetchone()[0]
        for name in sorted(tables) if not name.startswith('sqlite_')}
    workspace = []
    if 'editor_preferences' in tables:
        workspace = connection.execute(
            "SELECT value FROM editor_preferences WHERE key='open_workspace'").fetchall()
    return {'user_version': version, 'counts': counts, 'workspace': workspace}


def _snapshot(source: Path, output: Path) -> dict:
    deadline = time.monotonic() + 15

    def progress(status: int, remaining: int, total: int) -> None:
        if time.monotonic() > deadline:
            raise TimeoutError('SQLite backup timed out; ensure both apps are closed')

    with closing(_read_only(source)) as reader, closing(sqlite3.connect(output)) as writer:
        reader.backup(writer, pages=256, progress=progress, sleep=0.05)
    with closing(_read_only(output)) as snapshot:
        return _manifest(snapshot)


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _no_sidecars(path: Path) -> None:
    if any(Path(str(path) + suffix).exists() for suffix in ('-wal', '-shm', '-journal')):
        raise ValueError('Destination has SQLite sidecars; close the new app and checkpoint first')


def migrate(source: Path, destination: Path, backup_dir: Path, *, apps_closed: bool) -> dict:
    if not apps_closed:
        raise ValueError('Gracefully close both apps, then pass --apps-closed')
    source = source.expanduser().resolve(strict=True)
    destination = destination.expanduser().absolute()
    backup_dir = backup_dir.expanduser().absolute()
    if not source.is_file() or destination.is_symlink():
        raise ValueError('Expected a regular source file and a non-symlink destination')
    if source == destination.resolve() or (destination.exists() and os.path.samefile(source, destination)):
        raise ValueError('Source and destination must differ')
    _no_sidecars(destination)
    before = None
    if destination.exists():
        with closing(_read_only(destination)) as existing:
            target_manifest = _manifest(existing)
        if any(target_manifest['counts'][name] for name in USER_TABLES):
            raise ValueError('Destination contains archives, drafts or history; merging is not supported')
        before = _digest(destination)

    backup_dir.mkdir(parents=True, exist_ok=True)
    # A private unique directory keeps previous migration evidence intact.
    session = Path(tempfile.mkdtemp(prefix='pvz-migration-', dir=backup_dir))
    source_backup = session / 'source.sqlite'
    source_manifest = _snapshot(source, source_backup)
    if before is not None:
        _snapshot(destination, session / 'destination-before.sqlite')
    destination.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix='.pvz-migration-', suffix='.sqlite', dir=destination.parent)
    os.close(handle)
    staged = Path(temporary)
    try:
        shutil.copyfile(source_backup, staged)
        with staged.open('rb') as file:
            os.fsync(file.fileno())
        if _digest(staged) != _digest(source_backup):
            raise ValueError('Staged snapshot checksum mismatch')
        _no_sidecars(destination)
        if before is None:
            # Atomic no-overwrite install if another process created a target.
            os.link(staged, destination)
            staged.unlink()
        else:
            if not destination.exists() or _digest(destination) != before:
                raise ValueError('Destination changed during migration; refusing to replace it')
            os.replace(staged, destination)
        with closing(_read_only(destination)) as installed:
            if _manifest(installed) != source_manifest:
                raise ValueError('Installed library verification failed; snapshots retained')
    finally:
        staged.unlink(missing_ok=True)
    result = {'source': str(source), 'destination': str(destination),
              'backup_dir': str(session), 'manifest': source_manifest,
              'sha256': _digest(destination)}
    (session / 'migration.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--backup-dir', type=Path, required=True)
    parser.add_argument('--apps-closed', action='store_true', help='Confirm both application instances have quit normally')
    args = parser.parse_args()
    try:
        result = migrate(args.source, args.destination, args.backup_dir, apps_closed=args.apps_closed)
    except (OSError, sqlite3.Error, ValueError, TimeoutError) as error:
        parser.exit(1, f'Migration refused: {error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
