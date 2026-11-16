// Visitor stats for agency.makors.xyz, in PostHog (project "agency", US).
// The key is a public project key: it can only send events, not read them.
// The flash script and the installer send to the same project.
//
// Events, besides pageviews and clicks:
//   download_clicked        the ISO link       { from }
//   command_copied          a copy button      { command, from }
// From outside the page, in the order an install goes:
//   iso_download                    worker.js, counted on the server  { from, country, os }
//   flash_started, flash_written    public/flash
//   setup_started                   the installer, once it has a network
//   install_started, install_completed, install_failed { step }
//   first_boot                      the new machine, the first time it starts
//   vm_started                      the try-it VM (hosts/agency/vm.nix), once per VM disk
// The installer's four and first_boot share one random ID per install
// (installer/count.sh), so they line up as a funnel.

const key = 'phc_yBGvjZW4wAfvVSufdysvJxTWdoyQAtP7fcxrg4khcif4'

type PostHog = typeof import('posthog-js').default

// The SDK is bigger than the rest of the page, so it loads after the page,
// as its own chunk. Events from before it arrives wait in `queue`.
let posthog: PostHog | undefined
const queue: [string, Record<string, unknown> | undefined][] = []

// Only the real site counts; `npm run dev` and previews stay out of it.
if (location.hostname === 'agency.makors.xyz') {
  import('posthog-js').then(({ default: ph }) => {
    ph.init(key, {
      api_host: 'https://us.i.posthog.com',
      defaults: '2026-08-30',
      person_profiles: 'identified_only',
    })
    posthog = ph
    for (const [event, properties] of queue.splice(0)) ph.capture(event, properties)
  })
}

export function track(event: string, properties?: Record<string, unknown>) {
  if (posthog) posthog.capture(event, properties)
  else if (location.hostname === 'agency.makors.xyz') queue.push([event, properties])
}
