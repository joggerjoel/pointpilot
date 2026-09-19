import { format } from '../lib/money'
import { CATEGORY_DISPLAY, subjectForCategory } from '../lib/types'
import type { MetricsSummary } from '../lib/types'
import { Illustration } from '../components/Illustration'
import { CountUpCurrency } from '../components/CountUpCurrency'

/**
 * The rewards dashboard — the web counterpart of `MetricsView.swift`.
 *
 * Every figure comes from `MetricsSummary`, which is computed by the same engine
 * the finder uses, so the totals here can never contradict what the app would
 * tell you at the register.
 */
export function MetricsView({ metrics }: { metrics: MetricsSummary }) {
  const largestCategory = metrics.categoryBreakdown[0]?.amount ?? 1

  return (
    <div className="stack">
      <section className="card">
        <p className="muted">Earned in the last 30 days</p>
        <CountUpCurrency value={metrics.totalEarned} className="display-good" />
        <div className="spread">
          <span className="muted small">
            on {format(metrics.totalSpent)} of tracked spend
          </span>
          <span className="amount-good small">
            {format(metrics.effectiveRate)}% back
          </span>
        </div>
      </section>

      <section className="card">
        <div className="row row-static">
          <Illustration subject="generic" size={56} />
          <span className="row-text">
            <span className="row-title">Left on the table</span>
            <span className="display-warn">{format(metrics.missedValue)}</span>
            <span className="muted tiny">
              You'd have earned this much more by using the card we recommended
              on every purchase.
            </span>
          </span>
        </div>
      </section>

      <section className="stack-tight">
        <h2 className="section-title">Card leaderboard</h2>
        <div className="card list-card">
          {metrics.standings.map((standing, index) => (
            <div key={standing.cardID}>
              <div className="row row-static">
                <span className="rank muted">{index + 1}</span>
                <span
                  className="swatch"
                  style={{ background: standing.cardAccentHex }}
                  aria-hidden="true"
                />
                <span className="row-text">
                  <span className="row-title">{standing.cardName}</span>
                  <span className="muted row-sub">
                    {standing.uses} purchase{standing.uses === 1 ? '' : 's'}
                  </span>
                </span>
                <span className="amount amount-good">
                  {format(standing.earned)}
                </span>
              </div>
              {index < metrics.standings.length - 1 && <div className="divider" />}
            </div>
          ))}
        </div>
      </section>

      <section className="stack-tight">
        <h2 className="section-title">Where you spent</h2>
        <div className="card stack-tight">
          {metrics.categoryBreakdown.map((item) => {
            const fraction =
              largestCategory > 0 ? item.amount / largestCategory : 0
            return (
              <div key={item.category} className="bar-row">
                <div className="spread">
                  <span className="row-title">
                    {CATEGORY_DISPLAY[item.category]}
                  </span>
                  <span className="muted">{format(item.amount)}</span>
                </div>
                <div
                  className="bar"
                  role="img"
                  aria-label={`${CATEGORY_DISPLAY[item.category]}, ${format(item.amount)}`}
                >
                  <span
                    className="bar-fill"
                    style={{
                      width: `${Math.max(2, fraction * 100)}%`,
                      background: categoryTint(item.category),
                    }}
                  />
                </div>
              </div>
            )
          })}
        </div>
      </section>

      <section className="stack-tight">
        <h2 className="section-title">Activity</h2>
        <div className="card list-card">
          {metrics.recentEntries.map((entry, index) => {
            const missed = entry.bestPossible - entry.earned
            return (
              <div key={entry.id}>
                <div className="row row-static">
                  <Illustration
                    subject={subjectForCategory(entry.category)}
                    size={40}
                  />
                  <span className="row-text">
                    <span className="row-title">{entry.merchantName}</span>
                    <span className="muted row-sub">
                      {entry.usedCardName} · {entry.daysAgo}d ago
                    </span>
                  </span>
                  <span className="row-text row-right">
                    <span className="amount amount-good">
                      {format(entry.earned)}
                    </span>
                    {missed > 0 && (
                      <span className="amount-warn tiny">
                        {format(missed)} missed
                      </span>
                    )}
                  </span>
                </div>
                {index < metrics.recentEntries.length - 1 && (
                  <div className="divider" />
                )}
              </div>
            )
          })}
        </div>
      </section>
    </div>
  )
}

function categoryTint(category: string): string {
  switch (category) {
    case 'dining':
      return '#C97B4A'
    case 'groceries':
      return '#5F9E6B'
    case 'travel':
      return '#5B87BE'
    case 'gas':
      return '#C98E3F'
    case 'clothing':
      return '#B2638E'
    case 'entertainment':
      return '#8362B0'
    default:
      return '#6E7F96'
  }
}
