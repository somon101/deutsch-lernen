import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ command }) => ({
  plugins: [react()],
  // GitHub Pages serves this project from /deutsch-lernen/, not the domain
  // root — only apply that base when actually building for deployment so
  // local dev (npm run dev) keeps working at the plain "/" root.
  base: command === "build" ? "/deutsch-lernen/" : "/",
  server: {
    // Allows access via a temporary Cloudflare quick-tunnel URL (*.trycloudflare.com)
    // for sharing the local dev server with someone else to test.
    allowedHosts: [".trycloudflare.com"],
  },
}));
