CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  day TEXT NOT NULL,
  at TEXT NOT NULL,
  visitor TEXT NOT NULL,
  session TEXT NOT NULL,
  event TEXT NOT NULL,
  path TEXT NOT NULL,
  source TEXT NOT NULL,
  country TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_day ON events(day);
CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT OR IGNORE INTO settings VALUES ('started_at', strftime('%Y-%m-%dT%H:%M:%fZ','now'));
