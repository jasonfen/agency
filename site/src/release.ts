import { useSyncExternalStore } from 'react'

// Everything about the download lives here. No other file hard-codes it.
//
// GitHub Actions uploads every ISO build to Cloudflare R2 and writes
// `latest.json` next to it. The page reads that file when it loads, so a new
// build shows up without rebuilding the site. The values below are only a
// fallback for when the fetch fails.

/** Public base URL of the R2 bucket `agency-iso`. */
export const r2Base = 'https://iso.makors.xyz'

export type Release = {
  /** Direct link to the ISO. */
  url: string
  fileName: string
  sizeBytes: number
  /** Hex SHA-256 of the ISO. Empty hides the checksum on the page. */
  sha256: string
  version: string
  /** Build date, YYYY-MM-DD. */
  date: string
}

let release: Release = {
  url: `${r2Base}/latest/agency-installer.iso`,
  fileName: 'agency-installer.iso',
  sizeBytes: 2807562240,
  sha256: '',
  version: 'latest',
  date: '2026-11-14',
}

const listeners = new Set<() => void>()

fetch(`${r2Base}/latest.json`, { cache: 'no-cache' })
  .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
  .then((j) => {
    release = {
      url: new URL(j.url, `${r2Base}/`).href,
      fileName: j.fileName ?? release.fileName,
      sizeBytes: Number(j.sizeBytes) || release.sizeBytes,
      sha256: j.sha256 ?? '',
      // Builds from main carry the branch name; only tags are versions.
      version: /^v\d/.test(j.version ?? '') ? j.version : 'latest',
      date: j.date ?? release.date,
    }
    listeners.forEach((l) => l())
  })
  .catch(() => {})

export function useRelease(): Release {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l)
      return () => listeners.delete(l)
    },
    () => release,
  )
}

export const githubUrl = 'https://github.com/makors/agency'
