"""Focused tests for the external macOS library migration tool."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('migration', Path(__file__).resolve().parents[1] / 'tool/migrate_macos_data.py')
migration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migration)


def library(path, populated=False, wal=False):
    db = sqlite3.connect(path)
    if wal:
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA wal_autocheckpoint=0')
    for name in migration.USER_TABLES:
        db.execute(f'CREATE TABLE {name}(id TEXT PRIMARY KEY, document TEXT)')
    db.execute('CREATE TABLE editor_preferences(key TEXT PRIMARY KEY, value TEXT)')
    db.execute('PRAGMA user_version=4')
    if populated:
        db.execute("INSERT INTO archives VALUES ('saved', '{\"plants\":42}')")
        db.execute("INSERT INTO archive_versions VALUES ('history', '{\"plants\":41}')")
        db.execute("INSERT INTO drafts VALUES ('draft', '{\"plants\":43}')")
        db.execute("INSERT INTO editor_preferences VALUES ('open_workspace', '{\"active\":0}')")
    db.commit()
    return db


class MigrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pvz-migration-test-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'old.sqlite'
        self.destination = self.root / 'new.sqlite'
        self.backups = self.root / 'backups'

    def tearDown(self):
        self.temp.cleanup()

    def migrate(self, closed=True):
        return migration.migrate(self.source, self.destination, self.backups, apps_closed=closed)

    def test_committed_wal_and_workspace_survive_without_changing_source(self):
        # Keep the writer open to force committed data to remain in WAL. The CLI
        # still requires the operator's closed-app confirmation in production.
        source = library(self.source, populated=True, wal=True)
        try:
            self.assertTrue(Path(str(self.source) + '-wal').exists())
            result = self.migrate()
            with sqlite3.connect(self.destination) as copied:
                self.assertEqual(copied.execute('SELECT * FROM archives').fetchall(), source.execute('SELECT * FROM archives').fetchall())
                self.assertEqual(copied.execute('SELECT * FROM editor_preferences').fetchall(), source.execute('SELECT * FROM editor_preferences').fetchall())
            self.assertEqual(result['manifest']['counts']['archive_versions'], 1)
            self.assertEqual(source.execute('SELECT count(*) FROM archives').fetchone()[0], 1)
            self.assertTrue((Path(result['backup_dir']) / 'source.sqlite').exists())
        finally:
            source.close()

    def test_empty_destination_is_backed_up_then_replaced(self):
        library(self.source, populated=True).close()
        library(self.destination).close()
        result = self.migrate()
        snapshot = Path(result['backup_dir']) / 'destination-before.sqlite'
        with sqlite3.connect(snapshot) as before:
            self.assertEqual(before.execute('SELECT count(*) FROM archives').fetchone()[0], 0)
        with sqlite3.connect(self.destination) as after:
            self.assertEqual(after.execute('SELECT count(*) FROM archives').fetchone()[0], 1)

    def test_any_user_table_blocks_overwrite(self):
        library(self.source, populated=True).close()
        for table in migration.USER_TABLES:
            with self.subTest(table=table):
                self.destination.unlink(missing_ok=True)
                db = library(self.destination)
                db.execute(f"INSERT INTO {table} VALUES ('keep', 'do not replace')")
                db.commit()
                db.close()
                original = self.destination.read_bytes()
                with self.assertRaisesRegex(ValueError, 'merging is not supported'):
                    self.migrate()
                self.assertEqual(self.destination.read_bytes(), original)

    def test_corrupt_source_does_not_replace_empty_destination(self):
        self.source.write_bytes(b'not sqlite')
        library(self.destination).close()
        before = self.destination.read_bytes()
        with self.assertRaises(sqlite3.DatabaseError):
            self.migrate()
        self.assertEqual(self.destination.read_bytes(), before)

    def test_destination_sidecars_are_rejected(self):
        library(self.source).close()
        for suffix in ['-wal', '-shm', '-journal']:
            sidecar = Path(str(self.destination) + suffix)
            sidecar.touch()
            with self.assertRaisesRegex(ValueError, 'sidecars'):
                self.migrate()
            sidecar.unlink()

    def test_requires_explicit_closed_apps_confirmation(self):
        library(self.source).close()
        with self.assertRaisesRegex(ValueError, '--apps-closed'):
            self.migrate(closed=False)
        self.assertFalse(self.destination.exists())

    def test_same_source_destination_is_rejected(self):
        library(self.source).close()
        with self.assertRaisesRegex(ValueError, 'must differ'):
            migration.migrate(self.source, self.source, self.backups, apps_closed=True)


if __name__ == '__main__':
    unittest.main()
