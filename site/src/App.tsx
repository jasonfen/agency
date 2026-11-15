import {
  BatteryCharging,
  Bot,
  Download,
  KeyRound,
  LayoutDashboard,
  LockKeyhole,
  MonitorPlay,
  RefreshCw,
  Undo2,
  type LucideIcon,
} from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { CopyButton } from '@/components/copy-button'
import { Dither, PixelCheck, PixelCross, PixelCursor, PixelStar } from '@/components/pixel'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { githubUrl, useRelease } from '@/release'

const flashCommand = 'curl -fsSL https://agency.makors.xyz/flash | sh'
const sshCommand = 'ssh agent@agency'
const desktopUrl = 'http://agency:6081/vnc.html'

const questions = ['Network', 'Name and GitHub user', 'Disk to erase', 'Tailscale', 'Apps']

const requirements = [
  'An x86-64 laptop or PC with UEFI and TPM 2.0',
  'A USB stick, 8 GB or more',
  'Secure Boot turned off',
  'Internet during the install',
  'A GitHub account with an SSH key on it',
]

/** What you would do by hand, and what agency does instead. */
const diy = [
  ['Install Linux, encrypt the disk, wire up TPM unlock', 'One USB stick and five questions'],
  ['Set up SSH, Tailscale and your keys', 'Your GitHub keys and Tailscale work at first boot'],
  ['Install each agent CLI and sign it in', 'Pick them during setup, signed in before first boot'],
  ['Write a prompt explaining the machine', 'Every agent already knows how the machine works'],
  ['Glue together Xvfb, a window manager and VNC', 'Desktops to drive, and to watch from a browser tab'],
  ["Hope the next config change doesn't break it", 'Every change is a commit, and one command undoes it'],
]

const features: { icon: LucideIcon; title: string; body: ReactNode }[] = [
  {
    icon: Bot,
    title: 'Agents know the machine',
    body: 'Claude Code, Codex and OpenCode start with skills for the desktop, secrets and changing the system. No briefing needed.',
  },
  {
    icon: Undo2,
    title: 'Root, with an undo',
    body: (
      <>
        Passwordless sudo on NixOS. The whole system is one git repo, so a bad change is one{' '}
        <code className="font-mono text-[0.9em] text-foreground">agency rollback</code> away.
      </>
    ),
  },
  {
    icon: MonitorPlay,
    title: 'Desktops you can watch',
    body: 'GUI apps run on virtual desktops. Watch from any browser, or take over for a login, 2FA or a CAPTCHA.',
  },
  {
    icon: KeyRound,
    title: 'Secrets, kept encrypted',
    body: (
      <>
        <code className="font-mono text-[0.9em] text-foreground">agency secret set</code> encrypts a key to the machine. Agents read it as an environment
        variable, and it never lands in a commit.
      </>
    ),
  },
  {
    icon: RefreshCw,
    title: 'Updates itself',
    body: 'Packages update every week, unattended. A failed build changes nothing, and it never reboots on its own.',
  },
  {
    icon: BatteryCharging,
    title: 'Built for the shelf',
    body: 'Close the lid and it keeps running. It never sleeps, and charging stops at 80% so the battery lasts as a UPS.',
  },
  {
    icon: LockKeyhole,
    title: 'Encrypted, unlocked by TPM',
    body: 'The disk is encrypted and unlocks itself at boot, so it comes back after a power cut with nobody there.',
  },
  {
    icon: LayoutDashboard,
    title: 'A dashboard on your tailnet',
    body: 'Status, desktops, a terminal, apps and secrets on one page, over Tailscale only. Its screen shows a QR code to open it.',
  },
]

/** A small mono label above a section heading. */
function Kicker({ children }: { children: ReactNode }) {
  return (
    <p className="mb-4 flex items-center gap-2.5 font-mono text-sm font-medium tracking-widest text-primary uppercase">
      <span className="size-2 bg-primary" aria-hidden />
      {children}
    </p>
  )
}

function Github({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className={className}>
      <path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.36-3.88-1.36-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.78 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.83 1.19 3.09 0 4.41-2.69 5.38-5.25 5.67.41.36.78 1.06.78 2.13v3.16c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5Z" />
    </svg>
  )
}

function useStars() {
  const [stars, setStars] = useState<number | null>(null)
  useEffect(() => {
    fetch(githubUrl.replace('github.com', 'api.github.com/repos'))
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((j) => typeof j.stargazers_count === 'number' && setStars(j.stargazers_count))
      .catch(() => {})
  }, [])
  return stars
}

function StarLink() {
  const stars = useStars()
  return (
    <a
      href={githubUrl}
      aria-label={stars === null ? 'agency on GitHub' : `agency on GitHub, ${stars} stars`}
      className="group flex items-center gap-5 text-foreground"
    >
      <Github className="size-8 transition-colors group-hover:text-primary" />
      <span className="flex items-center gap-2">
        <PixelStar className="h-6 text-primary" />
        <span className="font-heading text-3xl leading-none font-bold tabular-nums">{stars ?? '–'}</span>
      </span>
    </a>
  )
}

function DownloadButton({ className }: { className?: string }) {
  const release = useRelease()
  return (
    <a
      href={release.url}
      download={release.fileName}
      className={cn(
        buttonVariants({ size: 'lg' }),
        'h-14 gap-3 border-2 border-ink px-5 text-lg font-semibold hover:bg-primary [&_svg:not([class*=size-])]:size-5',
        className,
      )}
    >
      <Download />
      Download ISO
    </a>
  )
}

type Platform = 'unix' | 'windows' | 'other'

/** macOS and Linux can run the flash command; everything else downloads the ISO. */
function usePlatform(): Platform {
  const [platform] = useState<Platform>(() => {
    const nav = navigator as Navigator & { userAgentData?: { platform?: string } }
    const ua = nav.userAgent
    if (/android|iphone|ipad|ipod|cros/i.test(ua)) return 'other'
    const name = nav.userAgentData?.platform || nav.platform || ua
    if (/win/i.test(name)) return 'windows'
    if (/mac|linux|x11/i.test(name)) return 'unix'
    return 'other'
  })
  return platform
}

function FlashCommand({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-14 items-center gap-3 border-2 border-ink bg-card pr-1.5 pl-4 font-mono text-[0.95rem] text-card-foreground dark:border-edge',
        className,
      )}
    >
      <span className="text-primary select-none" aria-hidden>
        $
      </span>
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap">{flashCommand}</code>
      <CopyButton value={flashCommand} label="Copy the command" />
    </div>
  )
}

function GithubButton({ className }: { className?: string }) {
  return (
    <a
      href={githubUrl}
      className={cn(
        buttonVariants({ variant: 'outline', size: 'lg' }),
        'h-14 gap-3 border-2 border-edge bg-card px-5 text-lg font-medium dark:border-edge dark:bg-card [&_svg:not([class*=size-])]:size-5',
        className,
      )}
    >
      <Github />
      View on GitHub
    </a>
  )
}

function Snippet({ value, label }: { value: string; label: string }) {
  return (
    <div className="flex items-center gap-2 border-2 border-ink bg-card py-1 pr-1 pl-3.5 font-mono text-[0.9rem] text-card-foreground dark:border-edge">
      <code className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap">{value}</code>
      <CopyButton value={value} label={label} />
    </div>
  )
}

function Step({
  number,
  title,
  children,
  below,
}: {
  number: number
  title: string
  children?: ReactNode
  /** Content that runs the full width of the step, under the badge. */
  below?: ReactNode
}) {
  return (
    <li className="grid grid-cols-[3rem_minmax(0,1fr)] gap-x-4 sm:grid-cols-[3.5rem_minmax(0,1fr)] sm:gap-x-5">
      <span
        className="flex size-12 items-center justify-center bg-band-foreground font-heading text-3xl leading-none font-bold text-band sm:size-14 sm:text-4xl"
        aria-hidden
      >
        {number}
      </span>
      <div className="min-w-0">
        <h3 className="font-heading text-2xl leading-tight font-bold">{title}</h3>
        <div className="mt-1.5 space-y-3 leading-relaxed text-band-muted">{children}</div>
      </div>
      {below && <div className="col-span-2 mt-4 space-y-3 leading-relaxed text-band-muted">{below}</div>}
    </li>
  )
}

export default function App() {
  const release = useRelease()
  const platform = usePlatform()
  const sizeLabel = `${(release.sizeBytes / 1e9).toFixed(1)} GB`

  const unixOption = (
    <div>
      <h3 className="font-heading text-2xl font-bold">macOS or Linux</h3>
      <p className="mt-1.5 mb-4 text-muted-foreground">
        Plug in a USB stick and run this. It downloads the installer, checks it, and writes the stick.
      </p>
      <FlashCommand />
    </div>
  )
  const windowsOption = (
    <div>
      <h3 className="font-heading text-2xl font-bold">Windows</h3>
      <p className="mt-1.5 mb-4 text-muted-foreground">
        Download the ISO, then write it with balenaEtcher, or with Rufus in DD Image mode.
      </p>
      <DownloadButton />
    </div>
  )

  return (
    <div className="min-h-svh">
      <div className="relative">

        <header className="relative mx-auto flex max-w-6xl items-center justify-between px-5 pt-6 sm:px-8">
          <a href="/" aria-label="agency home">
            <picture>
              <source media="(prefers-color-scheme: dark)" srcSet="/agency-dark.svg" />
              <img src="/agency.svg" alt="agency" width={413} height={96} className="h-10 w-auto sm:h-11" />
            </picture>
          </a>
          <StarLink />
        </header>

        <main>
          <section className="relative mx-auto max-w-6xl px-5 pt-12 sm:px-8 sm:pt-16 lg:pt-20">
            <div className="flex items-start justify-between gap-6">
              <h1 className="min-w-0 font-heading text-[3.4rem] leading-[0.92] font-bold tracking-tight sm:text-[5.5rem] lg:text-[6.75rem]">
                A computer
                <br />
                for your agents.
              </h1>
              <PixelCursor className="mt-1 hidden h-40 shrink-0 text-foreground sm:block lg:mr-10 lg:h-52" />
            </div>

            <div className="mt-8 pb-20 lg:mt-12 lg:pb-28">
              <div>
                <p className="max-w-xl text-xl leading-relaxed">
                  Got an old laptop? Boot it from a USB stick and it becomes a machine your agents run as
                  root, with their own desktop. It takes just 5 minutes.
                </p>
                {platform === 'unix' ? (
                  <>
                    <FlashCommand className="mt-8 max-w-xl" />
                    <p className="mt-5 text-sm text-muted-foreground">
                      Writes the installer ({sizeLabel}) to a USB stick. On Windows,{' '}
                      <a href="#download" className="underline underline-offset-4 hover:text-foreground">
                        download the ISO
                      </a>{' '}
                      instead.
                    </p>
                  </>
                ) : (
                  <>
                    <div className="mt-8 flex flex-col gap-4 sm:flex-row sm:flex-wrap">
                      <DownloadButton />
                      <GithubButton />
                    </div>
                    <p className="mt-5 text-sm text-muted-foreground">
                      <span className="font-mono">{release.fileName}</span>, {sizeLabel}, for x86-64. On a Mac or
                      Linux,{' '}
                      <a href="#download" className="underline underline-offset-4 hover:text-foreground">
                        one command
                      </a>{' '}
                      writes the stick for you.
                    </p>
                  </>
                )}
              </div>
            </div>
          </section>
          <section id="why" className="relative mx-auto max-w-6xl px-5 pb-24 sm:px-8 lg:pb-32">
            <div className="grid items-start gap-10 lg:grid-cols-12 lg:gap-12">
              <div className="lg:sticky lg:top-10 lg:col-span-4">
                <Kicker>Why agency</Kicker>
                <h2 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">Why not do it yourself?</h2>
                <p className="mt-5 text-lg leading-relaxed text-muted-foreground">
                  You could. It's a weekend of setup, then it's yours to keep working. agency does all of it in one
                  install, and keeps doing it.
                </p>
              </div>

              <div className="pixel-shadow-lg border-2 border-ink bg-card text-card-foreground lg:col-span-8 dark:border-edge">
                <div className="grid grid-cols-2 border-b-2 border-ink dark:border-edge">
                  <div className="px-4 py-4 sm:px-6">
                    <p className="font-heading text-lg font-bold sm:text-xl">Doing it yourself</p>
                    <p className="mt-0.5 font-mono text-xs text-muted-foreground sm:text-sm">a weekend, then upkeep</p>
                  </div>
                  <div className="border-l-2 border-ink bg-primary px-4 py-4 text-primary-foreground sm:px-6 dark:border-edge">
                    <p className="font-heading text-lg font-bold sm:text-xl">With agency</p>
                    <p className="mt-0.5 font-mono text-xs opacity-85 sm:text-sm">5 minutes, then nothing</p>
                  </div>
                </div>
                <ul>
                  {diy.map(([yourself, agency]) => (
                    <li
                      key={yourself}
                      className="grid grid-cols-2 border-b-2 border-dashed border-foreground/15 last:border-b-0"
                    >
                      <p className="flex gap-2.5 px-4 py-4 text-sm text-muted-foreground sm:gap-3 sm:px-6 sm:text-base">
                        <PixelCross className="mt-1.5 h-3 shrink-0 text-destructive/70" />
                        {yourself}
                      </p>
                      <p className="flex gap-2.5 border-l-2 border-ink bg-accent/50 px-4 py-4 text-sm font-medium sm:gap-3 sm:px-6 sm:text-base dark:border-edge">
                        <PixelCheck className="mt-1.5 h-3.5 shrink-0 text-primary" />
                        {agency}
                      </p>
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            <div className="mt-28 lg:mt-36">
              <div className="grid gap-6 lg:grid-cols-12 lg:items-end lg:gap-12">
                <div className="lg:col-span-7">
                  <Kicker>Features</Kicker>
                  <h2 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">
                    Everything an agent needs, already set up.
                  </h2>
                </div>
                <p className="text-lg leading-relaxed text-muted-foreground lg:col-span-5">
                  Nothing to configure after the install. Your agents get a whole computer, and you get to watch,
                  steer and undo.
                </p>
              </div>

              <ul className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
                {features.map(({ icon: Icon, title, body }) => (
                  <li
                    key={title}
                    className="group pixel-shadow flex flex-col border-2 border-ink bg-card p-6 text-card-foreground transition-[translate,box-shadow] duration-150 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-[6px_6px_0_var(--ink)] dark:border-edge"
                  >
                    <span className="flex size-11 items-center justify-center border-2 border-ink bg-accent text-primary transition-colors group-hover:bg-primary group-hover:text-primary-foreground dark:border-edge">
                      <Icon className="size-5" strokeWidth={2.25} />
                    </span>
                    <h3 className="mt-5 font-heading text-[1.6rem] leading-[1.05] font-bold">{title}</h3>
                    <p className="mt-2.5 leading-relaxed text-muted-foreground">{body}</p>
                  </li>
                ))}
              </ul>
            </div>
          </section>
        </main>
      </div>

      <section className="bg-band text-band-foreground">
        <Dither className="-translate-y-full text-band" />
        <div className="mx-auto grid max-w-6xl gap-12 px-5 pt-12 pb-16 sm:px-8 sm:pt-16 lg:grid-cols-12 lg:gap-12 lg:pb-24">
          <div className="lg:col-span-4">
            <h2 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">
              Setup
            </h2>
          </div>

          <ol className="grid gap-x-10 gap-y-10 sm:grid-cols-2 lg:col-span-8">
            <Step number={1} title="Flash it">
              <p>On a Mac or Linux, one curl command writes the stick for you. On Windows, use balenaEtcher, or Rufus in DD Image mode.</p>
            </Step>
            <Step number={2} title="Boot it">
              <p>You'll need to turn Secure Boot off and TPM on in the BIOS first. Then start the laptop from the stick.</p>
            </Step>
            <Step number={3} title="Answer five questions">
              <ul className="flex flex-wrap gap-2 text-sm text-band-foreground">
                {questions.map((question) => (
                  <li key={question} className="border-2 border-band-muted/50 px-2 py-0.5">
                    {question}
                  </li>
                ))}
              </ul>
              <p>It won't touch the disk until you confirm on the last screen.</p>
            </Step>
            <Step
              number={4}
              title="SSH in"
              below={
                <>
                  <Snippet value={sshCommand} label="Copy the SSH command" />
                  <Snippet value={desktopUrl} label="Copy the desktop address" />
                </>
              }
            >
              <p>Once it restarts, you can log in from your own machine, or watch their desktop from a browser tab over Tailscale.</p>
            </Step>
          </ol>
        </div>
      </section>

      <section id="download" className="relative">
        <Dither flip className="text-band" />
        <div className="mx-auto grid max-w-6xl items-start gap-12 px-5 pt-12 pb-20 sm:px-8 lg:grid-cols-12 lg:pt-16 lg:pb-24">
          <div className="lg:col-span-5">
            <h2 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">What you need</h2>
            <ul className="mt-6 space-y-2.5 text-lg">
              {requirements.map((item) => (
                <li key={item} className="flex gap-3">
                  <PixelCheck className="mt-2 h-3.5 shrink-0 text-primary" />
                  {item}
                </li>
              ))}
            </ul>
          </div>

          <div className="border-2 border-ink bg-accent p-6 sm:p-9 lg:col-span-7 dark:border-edge">
            <h2 className="font-heading text-4xl leading-[1.02] font-bold sm:text-5xl">Download</h2>
            <p className="mt-3 text-lg text-muted-foreground">
              <span className="font-mono text-base">{release.fileName}</span>, {sizeLabel}, built{' '}
              <time dateTime={release.date}>{release.date}</time>
              {release.version !== 'latest' && `, version ${release.version}`}.
            </p>
            <div className="mt-8 space-y-8">
              {platform === 'windows' ? windowsOption : unixOption}
              <div className="border-t-2 border-dashed border-foreground/25" />
              {platform === 'windows' ? unixOption : windowsOption}
            </div>
            {release.sha256 && (
              <div className="mt-6">
                <p className="text-sm font-medium">SHA-256</p>
                <div className="mt-2 flex items-center gap-2 border-2 border-edge bg-card py-1.5 pr-1.5 pl-4">
                  <code className="min-w-0 flex-1 font-mono text-sm break-all">{release.sha256}</code>
                  <CopyButton value={release.sha256} label="Copy the SHA-256 checksum" />
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      <footer className="border-t-2 border-dashed border-foreground/25">
        <div className="mx-auto flex max-w-6xl flex-col gap-3 px-5 py-7 text-sm text-muted-foreground sm:flex-row sm:items-center sm:justify-between sm:px-8">
          <p>Runs NixOS.</p>
          <nav className="flex gap-5">
            <a href={githubUrl} className="underline-offset-4 hover:underline">
              GitHub
            </a>
            <a href={`${githubUrl}/blob/main/docs/install.md`} className="underline-offset-4 hover:underline">
              Install details
            </a>
            <a href={`${githubUrl}/issues`} className="underline-offset-4 hover:underline">
              Report a problem
            </a>
          </nav>
        </div>
      </footer>
    </div>
  )
}
