import { fromDollars, fromString, roundToCents, type Money } from './money'
import type {
  CardOffer,
  CreditCard,
  DiningProgram,
  Merchant,
} from './types'
import { multiply, multiplyInt } from './money'

/**
 * The web app's copy of the iOS sample data.
 *
 * Kept deliberately in one file and in the same shape as
 * `SampleDataRepository.swift`, so a change on one platform is easy to mirror
 * on the other. `parity.test.ts` asserts the figures agree with the Swift
 * engine's documented output.
 *
 * All content is fictional sample data.
 */

export const AMEX_GOLD_ID = 'amex-gold'
export const SAPPHIRE_PREFERRED_ID = 'chase-sapphire-preferred'
export const VENTURE_ID = 'capital-one-venture'

export const NOBU_ID = 'nobu'
export const SHAKE_SHACK_ID = 'shake-shack'
export const CHIPOTLE_ID = 'chipotle'
export const STARBUCKS_ID = 'starbucks'
export const WHOLE_FOODS_ID = 'whole-foods'
export const SHELL_ID = 'shell'
export const APPLE_STORE_ID = 'apple-store'
export const AMC_ID = 'amc-theatres'
export const GENERIC_RESTAURANT_ID = 'generic-restaurant'

export const sampleCards: CreditCard[] = [
  {
    id: AMEX_GOLD_ID,
    name: 'Amex Gold',
    issuer: 'Sample Bank',
    rewardUnitName: 'points',
    multipliers: { dining: 4, groceries: 4, travel: 3 },
    defaultMultiplier: 1,
    pointValue: fromString('0.02'),
    annualFee: fromDollars(250),
    priority: 0,
    accentHex: '#B99A5B',
  },
  {
    id: SAPPHIRE_PREFERRED_ID,
    name: 'Chase Sapphire Preferred',
    issuer: 'Sample Bank',
    rewardUnitName: 'points',
    multipliers: { dining: 3, travel: 2, groceries: 1 },
    defaultMultiplier: 1,
    pointValue: fromString('0.0175'),
    annualFee: fromDollars(95),
    priority: 1,
    accentHex: '#2F6BA8',
  },
  {
    id: VENTURE_ID,
    name: 'Capital One Venture',
    issuer: 'Sample Bank',
    rewardUnitName: 'miles',
    multipliers: {},
    defaultMultiplier: 2,
    pointValue: fromString('0.01'),
    annualFee: fromDollars(95),
    priority: 2,
    accentHex: '#8C2F39',
  },
]

export const sampleMerchants: Merchant[] = [
  { id: NOBU_ID, name: 'Nobu', category: 'dining', aliases: ['nobu downtown', 'nobu malibu', 'nobu sushi'], isFallback: false },
  { id: SHAKE_SHACK_ID, name: 'Shake Shack', category: 'dining', aliases: ['shakeshack', 'shake shack burger'], isFallback: false },
  { id: CHIPOTLE_ID, name: 'Chipotle', category: 'dining', aliases: ['chipotle mexican grill'], isFallback: false },
  { id: STARBUCKS_ID, name: 'Starbucks', category: 'dining', aliases: ['starbucks coffee'], isFallback: false },
  { id: WHOLE_FOODS_ID, name: 'Whole Foods', category: 'groceries', aliases: ['whole foods market'], isFallback: false },
  { id: SHELL_ID, name: 'Shell', category: 'gas', aliases: ['shell gas', 'shell station'], isFallback: false },
  { id: APPLE_STORE_ID, name: 'Apple Store', category: 'clothing', aliases: ['apple', 'apple store retail'], isFallback: false },
  { id: AMC_ID, name: 'AMC Theatres', category: 'entertainment', aliases: ['amc', 'amc theaters'], isFallback: false },
  {
    id: GENERIC_RESTAURANT_ID,
    name: 'Restaurant',
    category: 'dining',
    aliases: ['restaurant', 'dinner', 'lunch', 'generic restaurant'],
    isFallback: true,
  },
]

export const sampleOffers: CardOffer[] = [
  {
    id: 'offer-nobu-amex',
    cardID: AMEX_GOLD_ID,
    merchantID: NOBU_ID,
    offer: { kind: 'percentage', rate: fromString('0.10') },
    maximumValue: fromDollars(20),
    requiresActivation: true,
  },
  {
    id: 'offer-shakeshack-sapphire',
    cardID: SAPPHIRE_PREFERRED_ID,
    merchantID: SHAKE_SHACK_ID,
    offer: { kind: 'flatCash', value: fromDollars(5) },
    maximumValue: fromDollars(5),
    requiresActivation: true,
  },
  {
    id: 'offer-chipotle-venture',
    cardID: VENTURE_ID,
    merchantID: CHIPOTLE_ID,
    offer: { kind: 'percentage', rate: fromString('0.05') },
    maximumValue: fromDollars(10),
    requiresActivation: false,
  },
]

export const sampleDiningProgram: DiningProgram = {
  id: 'airline-dining',
  name: 'Airline Dining Rewards',
  milesPerDollar: 3,
  mileValue: fromString('0.015'),
  eligibleMerchantIDs: [NOBU_ID, SHAKE_SHACK_ID, CHIPOTLE_ID],
}

export const fallbackMerchant =
  sampleMerchants.find((m) => m.isFallback) ?? null

/**
 * Normalizes a query so matching is case-, punctuation- and
 * whitespace-insensitive: "  The NOBU! " becomes "nobu".
 */
export function normalize(query: string): string {
  return query
    .toLowerCase()
    .split('')
    .filter((ch) => /[a-z0-9 ]/.test(ch))
    .join('')
    .split(' ')
    .filter((part) => part.length > 0)
    .join(' ')
}

/**
 * Resolves free-text input to a known merchant, or null when unknown.
 *
 * Exact name, then alias, then containment — the same order the Swift
 * `MerchantProviding` extension uses, so both platforms resolve "nobu downtown"
 * the same way.
 */
export function findMerchant(
  query: string,
  merchants: Merchant[] = sampleMerchants,
): Merchant | null {
  const needle = normalize(query)
  if (needle === '') return null

  const candidates = merchants.filter((m) => !m.isFallback)

  for (const merchant of candidates) {
    if (normalize(merchant.name) === needle) return merchant
  }
  for (const merchant of candidates) {
    const names = [merchant.name, ...merchant.aliases]
    if (names.some((n) => normalize(n) === needle)) return merchant
  }

  const contained = candidates
    .filter((merchant) => {
      const names = [merchant.name, ...merchant.aliases]
      return names.some((name) => {
        const normalized = normalize(name)
        return normalized !== '' && needle.includes(normalized)
      })
    })
    .sort((a, b) => {
      if (a.name.length !== b.name.length) return a.name.length - b.name.length
      return a.id < b.id ? -1 : 1
    })

  return contained[0] ?? null
}

/** Parses typed currency input, tolerating "$" and thousands separators. */
export function parseAmount(text: string): Money | null {
  const cleaned = text.trim().replace(/\$/g, '').replace(/,/g, '')
  if (cleaned === '') return null
  const value = Number(cleaned)
  if (!Number.isFinite(value) || value <= 0) return null
  return roundToCents(fromDollars(value))
}

/**
 * Recomputes a card's reward for a past purchase, for the dashboard.
 *
 * Mirrors the engine's base-reward line so the dashboard totals and the finder
 * agree.
 */
export function baseRewardFor(
  card: CreditCard,
  amount: Money,
  multiplier: number,
): Money {
  return roundToCents(multiply(multiplyInt(amount, multiplier), card.pointValue))
}

export { multiply, multiplyInt }
