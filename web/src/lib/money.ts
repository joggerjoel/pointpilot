/**
 * Money arithmetic that mirrors the iOS app's use of `Decimal`.
 *
 * The Swift engine works in `Decimal` and rounds with `NSDecimalRound(.plain)`
 * — half away from zero. Doing the same sums in IEEE floating point would
 * drift: `3 * 200 * 0.0175` is 10.499999999999998 in binary, so a naive
 * `toFixed(2)` produces figures that disagree with the phone. Since the whole
 * point of this app is that a number is trustworthy, money is held as an
 * integer count of millionths of a dollar — "micro-dollars" — so every rate in
 * the sample data is exact and multiplication is integer arithmetic.
 *
 * Scale 1e6 covers the sample rates: point values reach 4 decimals ($0.0175)
 * and mile values 3 ($0.015).
 */

/** Integer micro-dollars. 1_000_000 micro-dollars === $1.00. */
export type Money = number

export const SCALE = 1_000_000
const MICRO_PER_CENT = 10_000

/** Rounds half away from zero, matching NSDecimalRound's `.plain` rule. */
export function roundHalfAway(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value))
}

/** Rounds `value` to a multiple of `unit`, ties away from zero. */
function roundToUnit(value: number, unit: number): number {
  return Math.sign(value) * Math.floor(Math.abs(value) / unit + 0.5) * unit
}

/** Builds Money from a dollar figure in the sample data. */
export function fromDollars(dollars: number): Money {
  return Math.round(dollars * SCALE)
}

/** Builds Money from a decimal string, e.g. "0.0175". */
export function fromString(dollars: string): Money {
  return fromDollars(Number(dollars))
}

/** Exact product of two Money values (amount × rate). */
export function multiply(a: Money, b: Money): Money {
  return roundHalfAway((a * b) / SCALE)
}

/** Product of Money and a plain integer multiplier (amount × multiplier). */
export function multiplyInt(a: Money, factor: number): Money {
  return a * factor
}

/** Exact quotient as a plain number, for display fractions only. */
export function ratio(a: Money, b: Money): number {
  if (b === 0) return 0
  return a / b
}

/** Rounds to cents — the precision every displayed total is stored at. */
export function roundToCents(value: Money): Money {
  return roundToUnit(value, MICRO_PER_CENT)
}

/** Dollars as a float. For layout fractions and formatting only, never totals. */
export function toDollars(value: Money): number {
  return value / SCALE
}

/** Formats as US dollars with exactly two fraction digits. */
export function format(value: Money): string {
  return toDollars(roundToCents(value)).toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

/** Formats as a signed amount, e.g. "−$30.00". */
export function formatSigned(value: Money): string {
  const rounded = roundToCents(value)
  if (rounded < 0) return `−${format(Math.abs(rounded))}`
  if (rounded > 0) return `+${format(rounded)}`
  return format(rounded)
}

/**
 * Formats a per-point or per-mile rate.
 *
 * These need more precision than a cash amount: $0.015 per mile must not
 * display as "$0.02 each", or the stated rate would contradict the total shown
 * on the same screen.
 */
export function formatRate(value: Money): string {
  return toDollars(value).toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 4,
  })
}

/** Formats a loyalty multiplier, e.g. "4×". */
export function formatMultiplier(value: Money): string {
  const dollars = toDollars(value)
  return `${Number.isInteger(dollars) ? dollars : dollars.toFixed(2)}×`
}

/** Formats a plain count with two fraction digits, e.g. "600" or "12.5". */
export function formatCount(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2)
}
