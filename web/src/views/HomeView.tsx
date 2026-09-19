import { format } from '../lib/money'
import { CATEGORY_DISPLAY, subjectForCategory } from '../lib/types'
import type { MetricsSummary } from '../lib/types'
import type { CreditCard } from '../lib/types'
import { Illustration } from '../components/Illustration'

/**
 * The front door — the web counterpart of `HomeView.swift`: a greeting, a hero
 * call to action, "I want to…" rows, earned/missed totals and recent activity.
 */
export function HomeView({
  metrics,
  cards,
  onFindCard,
  onShowRewards,
  onShowWallet,
}: {
  metrics: MetricsSummary
  cards: CreditCard[]
  onFindCard: () => void
  onShowRewards: () => void
  onShowWallet: () => void
}) {
  return (
    <div className="stack">
      <section className="stack-tight">
        <p className="muted greeting">{timeOfDayGreeting()}</p>
        <h1 className="display">How can I help you today?</h1>
      </section>

      <section className="card hero">
        <div className="hero-top">
          <div>
            <h2 className="hero-title">Pick the right card</h2>
            <p className="muted">
              Tell me where you are and what you'll spend, and I'll pick your
              best card.
            </p>
          </div>
          <Illustration subject="dining" size={84} />
        </div>
        <button className="btn btn-primary btn-block" onClick={onFindCard}>
          ✦ Find my best card
        </button>
      </section>

      <section className="stack-tight">
        <h2 className="section-title">I want to…</h2>
        <div className="card list-card">
          <button className="row" onClick={onShowRewards}>
            <Illustration subject="generic" size={52} />
            <span className="row-text">
              <span className="row-title">See my rewards</span>
              <span className="muted row-sub">What you've earned and missed</span>
            </span>
            <span className="chev" aria-hidden="true">
              ›
            </span>
          </button>
          <div className="divider" />
          <button className="row" onClick={onShowWallet}>
            <Illustration subject="shopping" size={52} />
            <span className="row-text">
              <span className="row-title">My wallet</span>
              <span className="muted row-sub">
                {cards.length} cards in your wallet
              </span>
            </span>
            <span className="chev" aria-hidden="true">
              ›
            </span>
          </button>
        </div>
      </section>

      <section className="stat-strip">
        <div className="stat stat-good">
          <span className="muted stat-cap">Earned</span>
          <span className="stat-value">{format(metrics.totalEarned)}</span>
        </div>
        <div className="stat stat-warn">
          <span className="muted stat-cap">Missed</span>
          <span className="stat-value">{format(metrics.missedValue)}</span>
        </div>
      </section>

      <section className="stack-tight">
        <h2 className="section-title">Recent</h2>
        <div className="card list-card">
          {metrics.recentEntries.slice(0, 3).map((entry, index) => (
            <div key={entry.id}>
              <div className="row row-static">
                <Illustration
                  subject={subjectForCategory(entry.category)}
                  size={40}
                />
                <span className="row-text">
                  <span className="row-title">{entry.merchantName}</span>
                  <span className="muted row-sub">
                    {entry.usedCardName} · {entry.daysAgo}d ago ·{' '}
                    {CATEGORY_DISPLAY[entry.category]}
                  </span>
                </span>
                <span className="amount amount-good">{format(entry.earned)}</span>
              </div>
              {index < Math.min(3, metrics.recentEntries.length) - 1 && (
                <div className="divider" />
              )}
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}

function timeOfDayGreeting(now = new Date()): string {
  const hour = now.getHours()
  if (hour < 12) return 'Good morning'
  if (hour < 17) return 'Good afternoon'
  return 'Good evening'
}
