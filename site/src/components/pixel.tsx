import { useId } from 'react'
import { cn } from '@/lib/utils'

/** The cursor from the logo. The body takes the text color. */
export function PixelCursor({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 54 81" shapeRendering="crispEdges" aria-hidden className={className}>
      <path className="fill-primary" d="M0 0h9v9h-9z" />
      <path
        fill="currentColor"
        d="M0 9h18v9h-18zM0 18h27v9h-27zM0 27h36v9h-36zM0 36h45v9h-45zM0 45h54v9h-54zM0 54h36v9h-36zM0 63h9v9h-9zM27 63h18v9h-18zM36 72h18v9h-18z"
      />
    </svg>
  )
}

/** A pixel check mark on a 7 x 6 grid. */
export function PixelCheck({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 7 6" shapeRendering="crispEdges" fill="currentColor" aria-hidden className={className}>
      <path d="M6 0h1v2h-1zM5 1h1v2h-1zM4 2h1v2h-1zM3 3h1v2h-1zM2 4h1v2h-1zM1 3h1v2h-1zM0 2h1v2h-1z" />
    </svg>
  )
}

/** A dithered edge, three pixel rows tall, dense at the bottom. Takes the text color. */
export function Dither({ className, flip }: { className?: string; flip?: boolean }) {
  const id = useId()
  return (
    <svg
      aria-hidden
      shapeRendering="crispEdges"
      className={cn('block h-6 w-full', flip && '-scale-y-100', className)}
    >
      <defs>
        <pattern id={id} width="32" height="24" patternUnits="userSpaceOnUse">
          <path fill="currentColor" d="M0 0h8v8h-8zM8 8h8v8h-8zM24 8h8v8h-8zM0 16h8v8h-8zM16 16h8v8h-8z" />
        </pattern>
      </defs>
      <rect width="100%" height="24" fill={`url(#${id})`} />
    </svg>
  )
}

export function PixelStar({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 9 9" shapeRendering="crispEdges" fill="currentColor" aria-hidden className={className}>
      <path d="M4 0h1v2h-1zM3 2h3v1h-3zM0 3h9v1h-9zM1 4h7v1h-7zM2 5h5v1h-5zM2 6h2v1h-2zM5 6h2v1h-2zM1 7h2v1h-2zM6 7h2v1h-2zM1 8h1v1h-1zM7 8h1v1h-1z" />
    </svg>
  )
}

/** A pixel cross on a 6 x 6 grid. */
export function PixelCross({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 6 6" shapeRendering="crispEdges" fill="currentColor" aria-hidden className={className}>
      <path d="M0 0h2v1h-2zM1 1h2v1h-2zM3 1h2v1h-2zM4 0h2v1h-2zM2 2h2v2h-2zM1 4h2v1h-2zM3 4h2v1h-2zM0 5h2v1h-2zM4 5h2v1h-2z" />
    </svg>
  )
}
