import {
  format,
  formatCount,
  formatMultiplier,
  formatRate,
  multiply,
  multiplyInt,
  roundToCents,
  type Money,
} from './money'
import {
  fallbackMerchant,
  findMerchant,
  sampleCards,
  sampleDiningProgram,
  sampleMerchants,
  sampleOffers,
} from './sampleData'
import type {
  CardEvaluation,
  CardOffer,
  CardRecommendation,
  CreditCard,
  DiningProgram,
  Merchant,
  RewardCategory,
  RewardComponent,
} from './types'

/**
 * The deterministic recommendation engine — the web port of
 * `RecommendationEngine.swift`.
 *
 * Pure: no mutable state, no I/O. Given the same inputs it always returns the
 * same output, which is what makes it testable and lets the two platforms be
 * compared against each other.
 */

export class RecommendationError extends Error {}

export interface MerchantProvider {
  merchants: Merchant[]
  offers: CardOffer[]
  diningProgram: DiningProgram
}

export const defaultProvider: MerchantProvider = {
  merchants: sampleMerchants,
  offers: sampleOffers,
  diningProgram: sampleDiningProgram,
}

const UNKNOWN_MERCHANT_NAME = 'this restaurant'
const UNKNOWN_MERCHANT_ID = '__unknown__'

/** The multiplier a card earns in a category. */
export function multiplierFor(card: CreditCard, category: RewardCategory): number {
  return card.multipliers[category] ?? card.defaultMultiplier
}

/** Short label for the reward rate, e.g. "4× points on dining". */
export function rateDescription(card: CreditCard, category: RewardCategory): string {
  const m = multiplierFor(card, category)
  const multiplier = formatMultiplier(m * 1_000_000)
  return `${multiplier} ${card.rewardUnitName} on ${categoryDisplay(category).toLowerCase()}`
}

function categoryDisplay(category: RewardCategory): string {
  switch (category) {
    case 'dining':
      return 'Dining'
    case 'groceries':
      return 'Groceries'
    case 'travel':
      return 'Travel'
    case 'gas':
      return 'Gas'
    case 'clothing':
      return 'Shopping'
    case 'entertainment':
      return 'Entertainment'
    case 'other':
      return 'Everything else'
  }
}

/** The uncapped dollar value of an offer for a purchase amount. */
function uncappedValue(offer: CardOffer, amount: Money): Money {
  switch (offer.offer.kind) {
    case 'percentage':
      return roundToCents(multiply(amount, offer.offer.rate))
    case 'flatCash':
      return roundToCents(offer.offer.value)
  }
}

/** The offer's value after its cap is applied. */
function cappedValue(offer: CardOffer, amount: Money): Money {
  const uncapped = uncappedValue(offer, amount)
  if (offer.maximumValue === null) return uncapped
  return Math.min(uncapped, offer.maximumValue)
}

/** Short human-readable offer description, e.g. "10% back". */
export function offerShortDescription(offer: CardOffer): string {
  switch (offer.offer.kind) {
    case 'percentage': {
      const percent = (offer.offer.rate / 1_000_000) * 100
      const text = Number.isInteger(percent) ? String(percent) : percent.toFixed(2)
      return `${text}% back`
    }
    case 'flatCash':
      return `${format(offer.offer.value)} back`
  }
}

/** Airline miles earned for a purchase. */
function programMiles(program: DiningProgram, amount: Money): number {
  return (amount / 1_000_000) * program.milesPerDollar
}

/** Dollar value of the airline dining program for a purchase. */
function programValue(program: DiningProgram, amount: Money): Money {
  const milesInMicro = programMiles(program, amount) * 1_000_000
  return roundToCents(multiply(Math.round(milesInMicro), program.mileValue))
}

function isEligible(program: DiningProgram, merchantID: string): boolean {
  return program.eligibleMerchantIDs.includes(merchantID)
}

/**
 * Builds the value breakdown for one card.
 *
 * Components are rounded to cents individually, then summed, so the lines a
 * user reads always add up to the total they read.
 */
export function evaluate(
  card: CreditCard,
  amount: Money,
  merchantID: string,
  category: RewardCategory,
  provider: MerchantProvider = defaultProvider,
  includeAnnualFeeInValue = false,
): CardEvaluation {
  const components: RewardComponent[] = []

  const multiplier = multiplierFor(card, category)
  const baseReward = roundToCents(
    multiply(multiplyInt(amount, multiplier), card.pointValue),
  )
  components.push({
    kind: 'baseReward',
    label: `${rateDescription(card, category)} on ${format(amount)}`,
    amount: baseReward,
  })

  const offers = provider.offers.filter(
    (o) => o.cardID === card.id && o.merchantID === merchantID,
  )

  let offerRequiringActivation: CardOffer | null = null

  for (const offer of offers) {
    const uncapped = uncappedValue(offer, amount)
    const capped = cappedValue(offer, amount)

    components.push({
      kind: 'merchantOffer',
      label: `${offerShortDescription(offer)} at this merchant`,
      amount: uncapped,
    })

    // The cap is shown as its own negative line so the advertised offer value
    // stays visible and the arithmetic still balances.
    const adjustment = capped - uncapped
    if (adjustment !== 0) {
      components.push({
        kind: 'capAdjustment',
        label: `Capped at ${format(offer.maximumValue ?? capped)}`,
        amount: adjustment,
      })
    }

    if (offer.requiresActivation && offerRequiringActivation === null) {
      offerRequiringActivation = offer
    }
  }

  const program = provider.diningProgram
  if (isEligible(program, merchantID)) {
    const value = programValue(program, amount)
    if (value !== 0) {
      const miles = formatCount(programMiles(program, amount))
      components.push({
        kind: 'diningProgram',
        label: `${miles} airline miles at ${formatRate(program.mileValue)} each`,
        amount: value,
      })
    }
  }

  if (includeAnnualFeeInValue && card.annualFee !== 0) {
    components.push({
      kind: 'fee',
      label: `${card.name} annual fee`,
      amount: -roundToCents(card.annualFee),
    })
  }

  const total = components.reduce((sum, c) => sum + c.amount, 0)

  return {
    card,
    components,
    totalValue: roundToCents(total),
    offerRequiringActivation,
  }
}

/**
 * Ranks by value, then wallet priority, then id.
 *
 * The trailing keys make ties resolve identically on every run rather than
 * depending on input order.
 */
function rank(a: CardEvaluation, b: CardEvaluation): number {
  if (a.totalValue !== b.totalValue) return b.totalValue - a.totalValue
  if (a.card.priority !== b.card.priority) return a.card.priority - b.card.priority
  return a.card.id < b.card.id ? -1 : 1
}

/** Builds a concise, fact-only sentence from the computed values. */
function explain(
  winner: CardEvaluation,
  runnerUp: CardEvaluation | null,
  merchantName: string,
): string {
  const total = format(winner.totalValue)

  if (!runnerUp) {
    return `Use your ${winner.card.name} at ${merchantName} for an estimated ${total} in value.`
  }

  const advantage = winner.totalValue - runnerUp.totalValue
  if (advantage <= 0) {
    return `Your ${winner.card.name} and ${runnerUp.card.name} are tied at ${total} in estimated value at ${merchantName}.`
  }

  return `Use your ${winner.card.name} at ${merchantName} for an estimated ${total} in value — ${format(advantage)} more than your ${runnerUp.card.name}.`
}

export interface RecommendOptions {
  cards?: CreditCard[]
  provider?: MerchantProvider
  includeAnnualFeeInValue?: boolean
}

/** Produces a recommendation for a merchant query and amount. */
export function recommend(
  merchantQuery: string,
  amount: Money,
  options: RecommendOptions = {},
): CardRecommendation {
  const cards = options.cards ?? sampleCards
  const provider = options.provider ?? defaultProvider
  const includeAnnualFeeInValue = options.includeAnnualFeeInValue ?? false

  if (cards.length === 0) {
    throw new RecommendationError('Add a card to your wallet to get a recommendation.')
  }
  if (amount <= 0) {
    throw new RecommendationError('Enter a purchase amount greater than $0.00.')
  }

  const spend = roundToCents(amount)
  const matched = findMerchant(merchantQuery, provider.merchants)

  // An unknown merchant falls back to the dining-category calculation and never
  // invents a merchant offer.
  const merchant = matched ?? fallbackMerchant
  const resolvedName = merchant?.name ?? UNKNOWN_MERCHANT_NAME
  const resolvedID = merchant?.id ?? UNKNOWN_MERCHANT_ID
  const category: RewardCategory = merchant?.category ?? 'dining'
  const isFallback = matched === null

  const evaluated = cards
    .map((card) =>
      evaluate(card, spend, resolvedID, category, provider, includeAnnualFeeInValue),
    )
    .sort(rank)

  const winner = evaluated[0]
  if (!winner) {
    throw new RecommendationError('Add a card to your wallet to get a recommendation.')
  }
  const runnerUp = evaluated.length > 1 ? evaluated[1] : null

  const warnings: string[] = []
  if (isFallback && merchantQuery.trim() !== '') {
    warnings.push(
      `We don't have an offer for “${merchantQuery}”. Showing standard dining rewards.`,
    )
  }
  if (winner.offerRequiringActivation) {
    warnings.push(
      `Activate the ${offerShortDescription(winner.offerRequiringActivation)} offer before you pay to earn it.`,
    )
  }

  return {
    winner,
    runnerUp,
    ranked: evaluated,
    merchantName: resolvedName,
    amount: spend,
    category,
    usedFallbackMerchant: isFallback,
    explanation: explain(winner, runnerUp, resolvedName),
    warnings,
    advantageOverRunnerUp: runnerUp ? winner.totalValue - runnerUp.totalValue : 0,
  }
}
