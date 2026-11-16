// Counts ISO downloads on the server, then sends the browser on to the file.
//
// The page's own stats (src/analytics.ts) run in the browser, where ad
// blockers hide them, so a click is not always counted. This runs for
// /download only (see wrangler.jsonc): it sends one anonymous `iso_download`
// event to PostHog and redirects to the ISO in R2. Everything else on the
// site is served as files, without this.
//
// The event carries where on the page the link was, the visitor's country
// and OS family, and a random ID. Browsers that ask not to be tracked
// (DNT or Global Privacy Control) and link previews are not counted.

const iso = 'https://iso.makors.xyz/latest/agency-installer.iso'
const key = 'phc_yBGvjZW4wAfvVSufdysvJxTWdoyQAtP7fcxrg4khcif4'
const previews = /bot|crawl|spider|preview|slack|discord|telegram|whatsapp|facebook|twitter|embed/i

function osOf(agent) {
  if (/Windows/.test(agent)) return 'Windows'
  if (/Mac OS X|Macintosh/.test(agent)) return 'macOS'
  if (/Android/.test(agent)) return 'Android'
  if (/iPhone|iPad/.test(agent)) return 'iOS'
  if (/Linux|X11/.test(agent)) return 'Linux'
  return 'other'
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url)
    if (url.pathname !== '/download') return env.ASSETS.fetch(request)

    const agent = request.headers.get('user-agent') ?? ''
    const optedOut = request.headers.get('dnt') === '1' || request.headers.get('sec-gpc') === '1'
    if (request.method === 'GET' && !optedOut && !previews.test(agent)) {
      ctx.waitUntil(
        fetch('https://us.i.posthog.com/i/v0/e/', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            api_key: key,
            event: 'iso_download',
            distinct_id: crypto.randomUUID(),
            properties: {
              $process_person_profile: false,
              from: (url.searchParams.get('from') ?? 'link').slice(0, 40),
              country: request.cf?.country ?? '',
              os: osOf(agent),
            },
          }),
        }).catch(() => {}),
      )
    }
    return Response.redirect(iso, 302)
  },
}
