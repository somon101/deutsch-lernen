import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // Allows access via a temporary Cloudflare quick-tunnel URL (*.trycloudflare.com)
    // for sharing the local dev server with someone else to test.
    allowedHosts: [".trycloudflare.com"],
  },
});
