import express from "express";
import cors from "cors";

import { config } from "./config.js";
import { readToken } from "./vault.js";
import patientRoutes from "./routes/patient.js";
import doctorRoutes from "./routes/doctor.js";
import surgeonRoutes from "./routes/surgeon.js";
import platformRoutes from "./routes/platform.js";

const app = express();

app.use(
  cors({
    origin: config.corsOrigins,
    methods: ["GET", "POST", "PUT", "OPTIONS"],
    allowedHeaders: ["Content-Type"],
  }),
);

app.use(express.json());

app.get("/health", async (_req, res) => {
  res.json({
    ok: true,
    service: "secret-theatre-api",
    vault_token: (await readToken()) ? "present" : "missing",
    timestamp: new Date().toISOString(),
  });
});

app.use("/api/patient", patientRoutes);
app.use("/api/doctor", doctorRoutes);
app.use("/api/surgeon", surgeonRoutes);
app.use("/api/platform", platformRoutes);

const server = app.listen(config.port, () => {
  console.log(`secret-theatre-api listening on :${config.port}`);
});

// PID 1 in the container: without a handler Node ignores SIGTERM and Podman
// kills it after the stop timeout (exit 137).
for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
