import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ command, mode }) => ({
  plugins: [react()],
  // GitHub Pages serves this project from /deutsch-lernen/, not the domain
  // root — only apply that base when actually building for deployment so
  // local dev (npm run dev) keeps working at the plain "/" root. The
  // Capacitor build (mode "mobile") is bundled straight into the native app
  // and served from its own root, so it needs the plain "/" base too.
  base: command === "build" && mode !== "mobile" ? "/deutsch-lernen/" : "/",
  server: {
    // Allows access via a temporary Cloudflare quick-tunnel URL (*.trycloudflare.com)
    // for sharing the local dev server with someone else to test.
    allowedHosts: [".trycloudflare.com"],
  },
}));
