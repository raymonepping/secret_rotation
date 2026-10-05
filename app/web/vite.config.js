import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// `npm run dev`: the API runs in the Podman stack (make app-up) on 13000.
const apiTarget = process.env.SROT_API_URL || "http://127.0.0.1:13000";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": apiTarget,
      "/health": apiTarget,
    },
  },
});
