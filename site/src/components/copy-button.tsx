import { Check, Copy } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { track } from '@/analytics'

export function CopyButton({
  value,
  label,
  event,
  className,
}: {
  value: string
  label: string
  /** Properties for a `command_copied` event; none sends nothing. */
  event?: Record<string, unknown>
  className?: string
}) {
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 1600)
    return () => clearTimeout(timer)
  }, [copied])

  async function copy() {
    try {
      await navigator.clipboard.writeText(value)
      setCopied(true)
      if (event) track('command_copied', event)
    } catch {
      // Clipboard is blocked (old browser or no HTTPS). The text stays selectable.
    }
  }

  return (
    <Button
      type="button"
      variant="ghost"
      size="icon-lg"
      onClick={copy}
      aria-label={copied ? 'Copied' : label}
      title={copied ? 'Copied' : label}
      className={cn('shrink-0', className)}
    >
      {copied ? <Check /> : <Copy />}
    </Button>
  )
}
