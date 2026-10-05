-- postgres/init/01-schema.sql — runs once, on an empty volume, connected to
-- the database named by POSTGRES_DB (SROT_DB_NAME, default hospital).

-- Nobody connects unless granted: Vault grants CONNECT to each dynamic role.
DO $$ BEGIN EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', current_database()); END $$;

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
  ('dynamic-secret-patient', 'critical', 32);
