import { useEffect, useRef, useState } from 'react'
import { format, roundToCents, type Money } from '../lib/money'

/**
 * A currency figure that counts up to its value on appear.
 *
 * The animation drives a 0…1 progress scalar rather than the Money value
 * itself, because interpolating money through a float mid-flight would show
 * figures that were never computed. Only the final frame is exact — and the
 * accessible label is pinned to the final amount from the first render, so a
 * screen reader never announces a part-way number.
 */
export function CountUpCurrency({
  value,
  className,
}: {
  value: Money
  className?: string
}) {
  const [progress, setProgress] = useState(prefersReducedMotion() ? 1 : 0)
  const frame = useRef<number>()

  useEffect(() => {
    if (prefersReducedMotion()) {
      setProgress(1)
      return
    }

    const duration = 900
    const start = performance.now()

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration)
      // Ease-out, matching the iOS count-up.
      setProgress(1 - Math.pow(1 - t, 3))
      if (t < 1) frame.current = requestAnimationFrame(tick)
    }

    frame.current = requestAnimationFrame(tick)
    return () => {
      if (frame.current !== undefined) cancelAnimationFrame(frame.current)
    }
  }, [value])

  const shown = roundToCents(value * progress)

  return (
    <span className={className} aria-label={format(value)}>
      {format(shown)}
    </span>
  )
}

function prefersReducedMotion(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true
  )
}
