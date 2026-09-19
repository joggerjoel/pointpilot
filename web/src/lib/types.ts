import type { Money } from './money'

/** The spending category a purchase falls into. */
export type RewardCategory =
  | 'dining'
  | 'groceries'
  | 'travel'
  | 'gas'
  | 'clothing'
  | 'entertainment'
  | 'other'

export const CATEGORY_DISPLAY: Record<RewardCategory, string> = {
  dining: 'Dining',
  groceries: 'Groceries',
  travel: 'Travel',
  gas: 'Gas',
  clothing: 'Shopping',
  entertainment: 'Entertainment',
  other: 'Everything else',
}

/** Visual subject used by the illustration component. */
export type IllustrationSubject =
  | 'dining'
  | 'coffee'
  | 'groceries'
  | 'travel'
  | 'flights'
  | 'gas'
  | 'shopping'
  | 'entertainment'
  | 'generic'

export function subjectForCategory(category: RewardCategory): IllustrationSubject {
  switch (category) {
    case 'dining':
      return 'dining'
    case 'groceries':
      return 'groceries'
    case 'travel':
      return 'travel'
    case 'gas':
      return 'gas'
    case 'clothing':
      return 'shopping'
    case 'entertainment':
      return 'entertainment'
    case 'other':
      return 'generic'
  }
}

export interface CreditCard {
  id: string
  name: string
  issuer: string
  /** "points" or "miles". */
  rewardUnitName: string
  multipliers: Partial<Record<RewardCategory, number>>
  defaultMultiplier: number
  /** Estimated value of one point or mile, in Money. */
  pointValue: Money
  annualFee: Money
  /** Wallet order; also the deterministic tie-breaker. */
  priority: number
  accentHex: string
}

export interface Merchant {
  id: string
  name: string
  category: RewardCategory
  aliases: string[]
  isFallback: boolean
}

export type OfferKind =
  | { kind: 'percentage'; rate: Money }
  | { kind: 'flatCash'; value: Money }

export interface CardOffer {
  id: string
  cardID: string
  merchantID: string
  offer: OfferKind
  /** Cap in Money, or null when uncapped. */
  maximumValue: Money | null
  requiresActivation: boolean
}

export interface DiningProgram {
  id: string
  name: string
  milesPerDollar: number
  mileValue: Money
  eligibleMerchantIDs: string[]
}

export type RewardComponentKind =
  | 'baseReward'
  | 'merchantOffer'
  | 'diningProgram'
  | 'capAdjustment'
  | 'fee'

export const COMPONENT_DISPLAY: Record<RewardComponentKind, string> = {
  baseReward: 'Card rewards',
  merchantOffer: 'Merchant offer',
  diningProgram: 'Airline dining rewards',
  capAdjustment: 'Offer cap adjustment',
  fee: 'Fee',
}

export interface RewardComponent {
  kind: RewardComponentKind
  label: string
  amount: Money
}

export interface CardEvaluation {
  card: CreditCard
  components: RewardComponent[]
  totalValue: Money
  offerRequiringActivation: CardOffer | null
}

export interface CardRecommendation {
  winner: CardEvaluation
  runnerUp: CardEvaluation | null
  ranked: CardEvaluation[]
  merchantName: string
  amount: Money
  category: RewardCategory
  usedFallbackMerchant: boolean
  explanation: string
  warnings: string[]
  advantageOverRunnerUp: Money
}

export interface HistoryEntry {
  id: string
  merchantName: string
  category: RewardCategory
  amount: Money
  usedCardID: string
  usedCardName: string
  earned: Money
  bestPossible: Money
  daysAgo: number
}

export interface MetricsSummary {
  entries: HistoryEntry[]
  recentEntries: HistoryEntry[]
  totalEarned: Money
  totalSpent: Money
  missedValue: Money
  effectiveRate: number
  standings: {
    cardID: string
    cardName: string
    cardAccentHex: string
    earned: Money
    uses: number
  }[]
  categoryBreakdown: { category: RewardCategory; amount: Money }[]
}
