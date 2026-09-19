import { useMemo, useState } from 'react'
import { HomeView } from './views/HomeView'
import { FindCardView } from './views/FindCardView'
import { MetricsView } from './views/MetricsView'
import { WalletView } from './views/WalletView'
import { demoMetrics } from './lib/metrics'
import { MockVoiceAgent } from './lib/voice'
import { sampleCards } from './lib/sampleData'

/**
 * The app shell: one place decides which screen is showing and owns the state
 * that outlives a single screen.
 *
 * Routing is deliberately minimal — four screens and a sheet do not need a
 * router, and keeping it as state means the wallet sheet and the active screen
 * can never disagree about what is open.
 */

export type Route = 'home' | 'find' | 'rewards'

export function App() {
  const [route, setRoute] = useState<Route>('home')
  const [walletOpen, setWalletOpen] = useState(false)

  // The metrics are computed once from the engine; they never change at runtime
  // because the demo history is fixed.
  const metrics = useMemo(() => demoMetrics(), [])

  // One voice agent for the session, so its transcript survives navigation.
  const voice = useMemo(() => new MockVoiceAgent(), [])

  return (
    <div className="app">
      <header className="topbar">
        <button
          className="brand"
          onClick={() => setRoute('home')}
          aria-label="PointPilot home"
        >
          <span className="brand-mark" aria-hidden="true">
            ✈
          </span>
          PointPilot
        </button>

        <nav className="topnav" aria-label="Main">
          <button
            className={route === 'find' ? 'navlink is-active' : 'navlink'}
            onClick={() => setRoute('find')}
            aria-current={route === 'find' ? 'page' : undefined}
          >
            Find a card
          </button>
          <button
            className={route === 'rewards' ? 'navlink is-active' : 'navlink'}
            onClick={() => setRoute('rewards')}
            aria-current={route === 'rewards' ? 'page' : undefined}
          >
            Rewards
          </button>
          <button className="navlink" onClick={() => setWalletOpen(true)}>
            Wallet
          </button>
        </nav>
      </header>

      <main className="content">
        {route === 'home' && (
          <HomeView
            metrics={metrics}
            cards={sampleCards}
            onFindCard={() => setRoute('find')}
            onShowRewards={() => setRoute('rewards')}
            onShowWallet={() => setWalletOpen(true)}
          />
        )}
        {route === 'find' && <FindCardView voice={voice} />}
        {route === 'rewards' && <MetricsView metrics={metrics} />}
      </main>

      {walletOpen && <WalletView onClose={() => setWalletOpen(false)} />}

      <footer className="footer">
        Demo data — sample cards, offers and purchase history. Nothing here is
        financial advice.
      </footer>
    </div>
  )
}
