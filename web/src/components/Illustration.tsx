import type { IllustrationSubject } from '../lib/types'

/**
 * The app's illustration language, drawn with CSS gradients and inline SVG.
 *
 * The web counterpart of `Illustration.swift`: the same soft-blob-plus-glyph
 * grammar, so the two platforms look like one product. Built from shapes rather
 * than bitmaps so it stays crisp at any size, follows the theme, and needs no
 * asset pipeline.
 */

const TINTS: Record<IllustrationSubject, [string, string]> = {
  dining: ['#E8B27D', '#C97B4A'],
  coffee: ['#C9A17E', '#8C6244'],
  groceries: ['#A8CFA0', '#5F9E6B'],
  travel: ['#9FC4E8', '#5B87BE'],
  flights: ['#A6B4E8', '#5F6FBF'],
  gas: ['#F0C48A', '#C98E3F'],
  shopping: ['#E4A9C4', '#B2638E'],
  entertainment: ['#C2A8E0', '#8362B0'],
  generic: ['#A9B6C9', '#6E7F96'],
}

/** The focal glyph for each subject, as an SVG path. */
const GLYPHS: Record<IllustrationSubject, JSX.Element> = {
  dining: (
    <g>
      <path d="M8 22V10a4 4 0 0 1 8 0v12M12 10v12" />
      <path d="M26 22v-6a5 5 0 0 0-5-5h-1a5 5 0 0 0-5 5v6M20 22v6M20 6v10" />
    </g>
  ),
  coffee: (
    <g>
      <path d="M7 12h18v8a6 6 0 0 1-6 6h-6a6 6 0 0 1-6-6v-8Z" />
      <path d="M25 14h3a3 3 0 0 1 0 6h-3" />
      <path d="M11 7V4M17 7V4" />
    </g>
  ),
  groceries: (
    <g>
      <path d="M6 9h4l3 12h11l3-9H10" />
      <circle cx="13" cy="25" r="1.6" />
      <circle cx="22" cy="25" r="1.6" />
    </g>
  ),
  travel: (
    <g>
      <rect x="8" y="8" width="16" height="18" rx="3" />
      <path d="M13 8V6a3 3 0 0 1 6 0v2M8 16h16" />
    </g>
  ),
  flights: (
    <g>
      <path d="M4 16l24-8-7 20-4-7-9-3Z" />
      <path d="M17 21l11-13" />
    </g>
  ),
  gas: (
    <g>
      <path d="M9 10a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16H9V10Z" />
      <path d="M19 12h3l2 3v7a2 2 0 0 0 2 2" />
      <path d="M12 13h4" />
    </g>
  ),
  shopping: (
    <g>
      <path d="M7 10h18l-1.5 15h-15L7 10Z" />
      <path d="M12 10V8a4 4 0 0 1 8 0v2" />
    </g>
  ),
  entertainment: (
    <g>
      <path d="M5 11a2 2 0 0 1 2-2h18a2 2 0 0 1 2 2v2a3 3 0 0 0 0 6v2a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-2a3 3 0 0 0 0-6v-2Z" />
      <path d="M15 9v14" />
    </g>
  ),
  generic: (
    <g>
      <path d="M16 5l3 8 8 3-8 3-3 8-3-8-8-3 8-3 3-8Z" />
    </g>
  ),
}

export function Illustration({
  subject,
  size = 72,
  decorative = true,
}: {
  subject: IllustrationSubject
  size?: number
  decorative?: boolean
}) {
  const [light, dark] = TINTS[subject]

  return (
    <div
      className="illustration"
      style={{
        width: size,
        height: size,
        background: `radial-gradient(circle at 30% 25%, ${light}4D, ${dark}2E)`,
      }}
      aria-hidden={decorative}
      role={decorative ? 'presentation' : 'img'}
    >
      <div
        className="illustration-blob"
        style={{
          width: size * 0.62,
          height: size * 0.62,
          background: `linear-gradient(160deg, ${light}D9, ${dark}B3)`,
        }}
      />
      <svg
        className="illustration-glyph"
        viewBox="0 0 32 32"
        style={{ width: size * 0.42, height: size * 0.42 }}
        fill="none"
        stroke="#fff"
        strokeWidth={1.9}
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {GLYPHS[subject]}
      </svg>
    </div>
  )
}
