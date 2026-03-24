\connect librarydemo;

CREATE TABLE IF NOT EXISTS patient_status_demo (
  id SERIAL PRIMARY KEY,
  patient_name TEXT NOT NULL,
  status TEXT NOT NULL,
  heartbeat INTEGER NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO patient_status_demo (patient_name, status, heartbeat)
VALUES
  ('dynamic-secret-patient', 'stable', 72),
  ('dynamic-secret-patient', 'warning', 58),
  ('dynamic-secret-patient', 'critical', 32)
ON CONFLICT DO NOTHING;

GRANT CONNECT ON DATABASE librarydemo TO vaultadmin;
GRANT USAGE ON SCHEMA public TO vaultadmin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vaultadmin;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vaultadmin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vaultadmin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO vaultadmin;