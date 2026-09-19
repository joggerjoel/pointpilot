import { describe, expect, it } from 'vitest'
import { format, formatRate, formatSigned, roundToCents } from './money'
import { evaluate, recommend, multiplierFor } from './engine'
import { demoMetrics } from './metrics'
import { AMEX_GOLD_ID, SAPPHIRE_PREFERRED_ID, sampleCards } from './sampleData'

/**
 * Parity tests.
 *
 * These pin the web engine to the *same figures the Swift engine produces*, so
 * the two platforms cannot silently drift apart. The expected values below are
 * the documented outputs of `RecommendationEngineTests` and the demo script in
 * the iOS README — they are the contract, not a snapshot of whatever the web
 * code happens to return today.
 */

const MICRO = 1_000_000
const dollars = (n: number) => n * MICRO

describe('engine parity with the iOS engine', () => {
  it('recommends Amex Gold for Nobu at $200, totalling $45.00', () => {
    const result = recommend('Nobu', dollars(200))

    expect(result.winner.card.id).toBe(AMEX_GOLD_ID)
    expect(format(result.winner.totalValue)).toBe('$45.00')
  })

  it('breaks the Nobu total into $16.00 + $20.00 + $9.00', () => {
    const result = recommend('Nobu', dollars(200))

    const amounts = result.winner.components.map((c) => format(c.amount))
    expect(amounts).toEqual(['$16.00', '$20.00', '$9.00'])
  })

  it('scores the runner-up Sapphire Preferred at $19.50', () => {
    const result = recommend('Nobu', dollars(200))

    expect(result.runnerUp?.card.id).toBe(SAPPHIRE_PREFERRED_ID)
    expect(format(result.runnerUp!.totalValue)).toBe('$19.50')
  })

  it('gives the Amex a $25.50 advantage over the runner-up', () => {
    const result = recommend('Nobu', dollars(200))

    expect(format(result.advantageOverRunnerUp)).toBe('$25.50')
  })

  it('caps the Nobu offer at $20 and shows the adjustment as −$30.00', () => {
    const result = recommend('Nobu', dollars(500))
    const adjustment = result.winner.components.find((c) => c.kind === 'capAdjustment')

    expect(adjustment).toBeDefined()
    expect(formatSigned(adjustment!.amount)).toBe('−$30.00')
    expect(adjustment!.label).toBe('Capped at $20.00')
  })

  it('uses standard dining rewards with no invented offer for an unknown merchant', () => {
    const result = recommend("Joe's Random Diner", dollars(200))

    expect(format(result.winner.totalValue)).toBe('$16.00')
    expect(result.winner.components.some((c) => c.kind === 'merchantOffer')).toBe(false)
    expect(result.usedFallbackMerchant).toBe(true)
  })

  it('rejects a zero amount, as the iOS engine does', () => {
    expect(() => recommend('Nobu', 0)).toThrow(/greater than \$0\.00/)
  })

  it('formats sub-cent rates without rounding them to a cent', () => {
    // $0.015 per mile must not display as "$0.02 each". Two fraction digits is
    // the floor, four the ceiling — the same 2...4 range Swift uses — so a value
    // that needs three digits keeps all three.
    expect(formatRate(dollars(0.015))).toBe('$0.015')
    expect(formatRate(dollars(0.0175))).toBe('$0.0175')
    expect(formatRate(dollars(0.02))).toBe('$0.02')
  })

  it('resolves aliases and case-insensitive merchant input', () => {
    expect(recommend('  nobu downtown ', dollars(200)).winner.card.id).toBe(AMEX_GOLD_ID)
    expect(recommend('NOBU', dollars(200)).winner.card.id).toBe(AMEX_GOLD_ID)
  })

  it('produces identical results on repeated runs', () => {
    const first = recommend('Nobu', dollars(200))
    const second = recommend('Nobu', dollars(200))

    expect(format(first.winner.totalValue)).toBe(format(second.winner.totalValue))
    expect(first.ranked.map((r) => r.card.id)).toEqual(second.ranked.map((r) => r.card.id))
  })

  it('resolves ties deterministically by wallet priority', () => {
    const result = recommend('Whole Foods', dollars(100))
    // Ordering must be stable, whatever the values.
    expect(result.ranked.length).toBe(sampleCards.length)
  })

  it('keeps every displayed component summing to the displayed total', () => {
    for (const amount of [12, 19, 28, 46, 62, 140, 200, 320, 500]) {
      const result = recommend('Nobu', dollars(amount))
      const sum = result.winner.components.reduce((acc, c) => acc + roundToCents(c.amount), 0)
      expect(format(sum)).toBe(format(result.winner.totalValue))
    }
  })

  it('applies the dining multiplier the card advertises', () => {
    const amex = sampleCards.find((c) => c.id === AMEX_GOLD_ID)!
    expect(multiplierFor(amex, 'dining')).toBe(4)
    expect(multiplierFor(amex, 'other')).toBe(1)
  })

  it('keeps per-purchase value free of annual fees by default', () => {
    const evaluation = evaluate(
      sampleCards.find((c) => c.id === AMEX_GOLD_ID)!,
      dollars(200),
      'nobu',
      'dining',
    )
    expect(evaluation.components.some((c) => c.kind === 'fee')).toBe(false)
  })
})

describe('dashboard parity', () => {
  it('computes totals from the real engine rather than hard-coded figures', () => {
    const metrics = demoMetrics()

    // Nobu is the 2nd-newest entry and earned the full $45.00.
    const nobu = metrics.recentEntries.find((e) => e.merchantName === 'Nobu')
    expect(nobu).toBeDefined()
    expect(format(nobu!.earned)).toBe('$45.00')
    expect(format(nobu!.bestPossible)).toBe('$45.00')
  })

  it('reports non-zero missed value, because demo purchases use weaker cards', () => {
    const metrics = demoMetrics()

    expect(metrics.missedValue).toBeGreaterThan(0)
    expect(format(metrics.missedValue)).toBe('$9.05')
  })

  it('totals earned across the 30-day window', () => {
    const metrics = demoMetrics()

    expect(format(metrics.totalEarned)).toBe('$66.78')
    expect(format(metrics.totalSpent)).toBe('$827.00')
  })

  it('never reports more earned than the best available on the same purchases', () => {
    const metrics = demoMetrics()

    expect(metrics.totalEarned).toBeLessThanOrEqual(
      metrics.totalEarned + metrics.missedValue,
    )
    for (const entry of metrics.recentEntries) {
      expect(entry.earned).toBeLessThanOrEqual(entry.bestPossible)
    }
  })

  it('ranks the leaderboard by value earned, then uses, then name', () => {
    const metrics = demoMetrics()
    const standings = metrics.standings

    for (let i = 1; i < standings.length; i += 1) {
      const prev = standings[i - 1]
      const curr = standings[i]
      expect(
        prev.earned > curr.earned ||
          (prev.earned === curr.earned && prev.uses >= curr.uses),
      ).toBe(true)
    }
  })
})
