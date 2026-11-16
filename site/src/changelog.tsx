// The changelog page: the newest commits on main, read from GitHub when the
// page loads, so it never needs updating by hand.

import { StrictMode, useEffect, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './analytics'
// Not from release.ts, which would also fetch the download details.
const githubUrl = 'https://github.com/makors/agency'

type Commit = { sha: string; subject: string; date: string }

const api = `${githubUrl.replace('github.com', 'api.github.com/repos')}/commits?sha=main&per_page=100`

function useCommits() {
  const [commits, setCommits] = useState<Commit[] | 'failed' | null>(null)
  useEffect(() => {
    fetch(api)
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((list: { sha: string; commit: { message: string; committer: { date: string } } }[]) =>
        setCommits(
          list
            .map((c) => ({ sha: c.sha, subject: c.commit.message.split('\n')[0], date: c.commit.committer.date }))
            .filter((c) => !c.subject.startsWith('Merge ')),
        ),
      )
      .catch(() => setCommits('failed'))
  }, [])
  return commits
}

/** A subject line, with `backticked` words as code. */
function Subject({ text }: { text: string }) {
  return text.split('`').map((part, i) =>
    i % 2 ? (
      <code key={i} className="font-mono text-[0.9em]">
        {part}
      </code>
    ) : (
      part
    ),
  )
}

/** Commits grouped by the day they landed, in the reader's time zone. */
function byDay(commits: Commit[]) {
  const days = new Map<string, Commit[]>()
  for (const c of commits) {
    const day = new Date(c.date).toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' })
    days.set(day, [...(days.get(day) ?? []), c])
  }
  return [...days]
}

function Changelog() {
  const commits = useCommits()
  const allCommits = `${githubUrl}/commits/main`

  return (
    <div className="min-h-svh">
      <header className="mx-auto max-w-3xl px-5 pt-6 sm:px-8">
        <a href="/" aria-label="agency home">
          <picture>
            <source media="(prefers-color-scheme: dark)" srcSet="/agency-dark.svg" />
            <img src="/agency.svg" alt="agency" width={413} height={96} className="h-10 w-auto sm:h-11" />
          </picture>
        </a>
      </header>

      <main className="mx-auto max-w-3xl px-5 pt-12 pb-20 sm:px-8">
        <h1 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">Changelog</h1>

        {commits === null && <p className="mt-8 text-muted-foreground">Loading…</p>}
        {commits === 'failed' && (
          <p className="mt-8 text-muted-foreground">
            Could not reach GitHub. The changes are on{' '}
            <a href={allCommits} className="underline underline-offset-4">
              GitHub
            </a>
            .
          </p>
        )}
        {Array.isArray(commits) && (
          <>
            {byDay(commits).map(([day, list]) => (
              <section key={day} className="mt-10">
                <h2 className="font-heading text-2xl font-bold">{day}</h2>
                <ul className="mt-3 space-y-2">
                  {list.map((c) => (
                    <li key={c.sha} className="flex gap-4 leading-relaxed">
                      <a
                        href={`${githubUrl}/commit/${c.sha}`}
                        className="shrink-0 pt-0.5 font-mono text-sm text-primary underline-offset-4 hover:underline"
                      >
                        {c.sha.slice(0, 7)}
                      </a>
                      <span className="min-w-0 break-words">
                        <Subject text={c.subject} />
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
            <p className="mt-12">
              <a href={allCommits} className="text-muted-foreground underline underline-offset-4 hover:text-foreground">
                Older changes on GitHub
              </a>
            </p>
          </>
        )}
      </main>
    </div>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Changelog />
  </StrictMode>,
)
