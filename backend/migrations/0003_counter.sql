CREATE TABLE IF NOT EXISTS counter (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  total_walks INTEGER NOT NULL DEFAULT 0,
  total_distance_km REAL NOT NULL DEFAULT 0,
  total_meditation_min INTEGER NOT NULL DEFAULT 0,
  total_talk_min INTEGER NOT NULL DEFAULT 0,
  last_walk_at TEXT
);

INSERT OR IGNORE INTO counter (id) VALUES (1);

CREATE TABLE IF NOT EXISTS counter_rate_limit (
  token TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_token ON counter_rate_limit (token, created_at);
