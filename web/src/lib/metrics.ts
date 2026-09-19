import { roundToCents, ratio, type Money } from './money'
import { evaluate, recommend } from './engine'
import { sampleCards, sampleDiningProgram, sampleMerchants } from './sampleData'
import type { HistoryEntry, MetricsSummary, RewardCategory } from './types'

/**
 * The dashboard aggregates — the web port of `Metrics.swift`.
 *
 * The demo history is *replayed through the real engine* rather than
 * hand-written, so the totals on the dashboard can never contradict what the
 * finder computes for the same purchase. That is the same guarantee the iOS app
 * makes, and `parity.test.ts` pins both to the same figures.
 */

interface HistorySpec {
  id: string
  merchantQuery: string
  amount: Money
  usedCardID: string
  daysAgo: number
}

const MICRO = 1_000_000

const HISTORY_SPECS: HistorySpec[] = [
  { id: 'h-01', merchantQuery: 'Nobu', amount: 200 * MICRO, usedCardID: 'amex-gold', daysAgo: 2 },
  { id: 'h-02', merchantQuery: 'Whole Foods', amount: 140 * MICRO, usedCardID: 'chase-sapphire-preferred', daysAgo: 4 },
  { id: 'h-03', merchantQuery: 'Shake Shack', amount: 28 * MICRO, usedCardID: 'chase-sapphire-preferred', daysAgo: 6 },
  { id: 'h-04', merchantQuery: 'Shell', amount: 62 * MICRO, usedCardID: 'capital-one-venture', daysAgo: 9 },
  { id: 'h-05', merchantQuery: 'Chipotle', amount: 19 * MICRO, usedCardID: 'capital-one-venture', daysAgo: 12 },
  { id: 'h-06', merchantQuery: 'Apple Store', amount: 320 * MICRO, usedCardID: 'amex-gold', daysAgo: 15 },
  { id: 'h-07', merchantQuery: 'AMC Theatres', amount: 46 * MICRO, usedCardID: 'chase-sapphire-preferred', daysAgo: 21 },
  { id: 'h-08', merchantQuery: 'Starbucks', amount: 12 * MICRO, usedCardID: 'amex-gold', daysAgo: 26 },
]

/** Demo history, computed by the real engine. */
export function buildHistory(): HistoryEntry[] {
  const entries: HistoryEntry[] = []

  for (const spec of HISTORY_SPECS) {
    const result = recommend(spec.merchantQuery, spec.amount)
    const used = result.ranked.find((e) => e.card.id === spec.usedCardID)
    if (!used) continue

    entries.push({
      id: spec.id,
      merchantName: result.merchantName,
      category: result.category,
      amount: spec.amount,
      usedCardID: used.card.id,
      usedCardName: used.card.name,
      earned: used.totalValue,
      bestPossible: result.winner.totalValue,
      daysAgo: spec.daysAgo,
    })
  }

  return entries
}

const ACCENTS: Record<string, string> = {
  'amex-gold': '#B99A5B',
  'chase-sapphire-preferred': '#2F6BA8',
  'capital-one-venture': '#8C2F39',
}

/** Spend grouped by category, largest first — drives the breakdown bars. */
export function categoryBreakdown(
  entries: HistoryEntry[],
): { category: RewardCategory; amount: Money }[] {
  const totals = new Map<RewardCategory, Money>()
  for (const entry of entries) {
    totals.set(entry.category, (totals.get(entry.category) ?? 0) + entry.amount)
  }
  return [...totals.entries()]
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => {
      if (a.amount !== b.amount) return b.amount - a.amount
      return a.category < b.category ? -1 : 1
    })
}

/** Aggregates a list of history entries into the dashboard summary. */
export function summarize(entries: HistoryEntry[]): MetricsSummary {
  // Newest first so "this month" and the activity list agree on ordering.
  const sorted = [...entries].sort((a, b) => a.daysAgo - b.daysAgo)
  const recent = sorted.filter((e) => e.daysAgo <= 30)

  const totalEarned = recent.reduce((sum, e) => sum + e.earned, 0)
  const totalSpent = recent.reduce((sum, e) => sum + e.amount, 0)
  const missedValue = recent.reduce(
    (sum, e) => sum + Math.max(0, e.bestPossible - e.earned),
    0,
  )

  const earnedByCard = new Map<string, Money>()
  const usesByCard = new Map<string, number>()
  const nameByCard = new Map<string, string>()

  for (const entry of recent) {
    earnedByCard.set(entry.usedCardID, (earnedByCard.get(entry.usedCardID) ?? 0) + entry.earned)
    usesByCard.set(entry.usedCardID, (usesByCard.get(entry.usedCardID) ?? 0) + 1)
    nameByCard.set(entry.usedCardID, entry.usedCardName)
  }

  const standings = [...earnedByCard.entries()]
    .map(([cardID, earned]) => ({
      cardID,
      cardName: nameByCard.get(cardID) ?? cardID,
      cardAccentHex: ACCENTS[cardID] ?? '#6E7F96',
      earned,
      uses: usesByCard.get(cardID) ?? 0,
    }))
    .sort((a, b) => {
      if (a.earned !== b.earned) return b.earned - a.earned
      if (a.uses !== b.uses) return b.uses - a.uses
      return a.cardName < b.cardName ? -1 : 1
    })

  const effectiveRate =
    totalSpent > 0 ? roundToCents(ratio(totalEarned, totalSpent) * 100 * MICRO) : 0

  return {
    entries: sorted,
    recentEntries: recent,
    totalEarned,
    totalSpent,
    missedValue,
    effectiveRate,
    standings,
    categoryBreakdown: categoryBreakdown(recent),
  }
}

/** The app's demo dashboard summary. */
export function demoMetrics(): MetricsSummary {
  return summarize(buildHistory())
}

/**
 * A single card's reward for a purchase at a merchant, with no offer applied.
 *
 * Used where a screen wants to show one card's line without a full
 * recommendation — kept here so callers do not reach into engine internals.
 */
export function cardBaseReward(
  cardID: string,
  amount: Money,
  category: RewardCategory,
): Money | null {
  const card = sampleCards.find((c) => c.id === cardID)
  if (!card) return null
  const evaluation = evaluate(card, amount, '__base__', category, {
    merchants: sampleMerchants,
    offers: [],
    diningProgram: sampleDiningProgram,
  })
  return evaluation.totalValue
}
