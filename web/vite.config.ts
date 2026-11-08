/// <reference types="vitest" />
import { defineConfig, loadEnv, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

/** Adds canonical / og:url / absolute og:image only when VITE_SITE_URL is supplied. */
function siteMeta(siteUrl: string): Plugin {
  return {
    name: 'kairo-site-meta',
    transformIndexHtml() {
      if (!siteUrl) return []
      const base = siteUrl.replace(/\/$/, '')
      return [
        { tag: 'link', attrs: { rel: 'canonical', href: `${base}/` }, injectTo: 'head' },
        { tag: 'meta', attrs: { property: 'og:url', content: `${base}/` }, injectTo: 'head' },
        { tag: 'meta', attrs: { property: 'og:image', content: `${base}/og.png` }, injectTo: 'head' },
        { tag: 'meta', attrs: { property: 'og:image:width', content: '1200' }, injectTo: 'head' },
        { tag: 'meta', attrs: { property: 'og:image:height', content: '630' }, injectTo: 'head' },
        { tag: 'meta', attrs: { property: 'og:image:alt', content: 'Kairo: find a little time together' }, injectTo: 'head' },
        { tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' }, injectTo: 'head' },
        { tag: 'meta', attrs: { name: 'twitter:image', content: `${base}/og.png` }, injectTo: 'head' },
      ]
    },
  }
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '.', 'VITE_')
  return {
    // GitHub Pages serves under /<repo>/, so the deploy workflow sets VITE_BASE. Default is the site root.
    base: env.VITE_BASE || '/',
    plugins: [react(), siteMeta(env.VITE_SITE_URL ?? '')],
    test: { environment: 'node', include: ['src/**/*.test.ts', 'server/**/*.test.mjs'] },
  }
})
