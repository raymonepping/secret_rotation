import dotenv from "dotenv";
import express from "express";
import cors from "cors";

import patientRoutes from "./routes/patient.js";
import doctorRoutes from "./routes/doctor.js";
import surgeonRoutes from "./routes/surgeon.js";

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(
  cors({
    origin: ["http://127.0.0.1:3001", "http://localhost:3001"],
    methods: ["GET", "POST", "PUT", "OPTIONS"],
    allowedHeaders: ["Content-Type"],
  })
);

app.use(express.json());

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "library-api",
    timestamp: new Date().toISOString(),
  });
});

app.use("/api/patient", patientRoutes);
app.use("/api/doctor", doctorRoutes);
app.use("/api/surgeon", surgeonRoutes);

app.listen(port, () => {
  console.log(`library-api listening on http://127.0.0.1:${port}`);
});