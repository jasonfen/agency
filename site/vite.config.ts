import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [react(), tailwindcss(), cloudflare()],
  resolve: {
    alias: { '@': path.resolve(import.meta.dirname, './src') },
  },
  // Two pages: the landing page, and /changelog.
  environments: {
    client: {
      build: {
        rollupOptions: {
          input: {
            main: path.resolve(import.meta.dirname, 'index.html'),
            changelog: path.resolve(import.meta.dirname, 'changelog.html'),
          },
        },
      },
    },
  },
})