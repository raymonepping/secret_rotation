// Empty = same origin: in the stack nginx serves the UI and proxies /api.
// `npm run dev` proxies /api through Vite (vite.config.js).
export const API_BASE = import.meta.env.VITE_API_BASE ?? "";
