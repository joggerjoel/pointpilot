import { useEffect, useRef, useState } from 'react'
import { format, formatSigned, formatRate, formatMultiplier } from '../lib/money'
import { recommend, offerShortDescription, RecommendationError } from '../lib/engine'
import { parseAmount } from '../lib/sampleData'
import { COMPONENT_DISPLAY, CATEGORY_DISPLAY, subjectForCategory } from '../lib/types'
import type { CardRecommendation } from '../lib/types'
import type { MockVoiceAgent, VoiceMessage, VoiceState } from '../lib/voice'
import { Illustration } from '../components/Illustration'
import { CountUpCurrency } from '../components/CountUpCurrency'

const MICRO = 1_000_000

const NEARBY = [
  { id: 'nobu', name: 'Nobu', hasOffer: true },
  { id: 'shake-shack', name: 'Shake Shack', hasOffer: true },
  { id: 'chipotle', name: 'Chipotle', hasOffer: true },
  { id: 'starbucks', name: 'Starbucks', hasOffer: false },
  { id: 'whole-foods', name: 'Whole Foods', hasOffer: false },
]

const SUGGESTIONS = [
  "I'm at Nobu and spending around $200",
  'Shake Shack, about $28',
  'Whole Foods $140',
]

/**
 * The card finder — the web counterpart of `AskView.swift`.
 *
 * The recommended path is typed input, which is the reliable one. Voice is
 * present as a simulated agent so the conversational flow is demonstrable, and
 * its transcript says so plainly.
 */
export function FindCardView({ voice }: { voice: MockVoiceAgent }) {
  const [merchant, setMerchant] = useState('')
  const [amount, setAmount] = useState('')
  const [result, setResult] = useState<CardRecommendation | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [activatedOfferID, setActivatedOfferID] = useState<string | null>(null)
  const [voiceState, setVoiceState] = useState<VoiceState>({ kind: 'idle' })
  const [messages, setMessages] = useState<VoiceMessage[]>([])
  const [utterance, setUtterance] = useState('')

  const resultRef = useRef<HTMLDivElement>(null)

  // Wire the agent's callbacks once. The agent supplies the inputs; this view
  // computes the answer through the engine.
  useEffect(() => {
    voice.onStateChange = setVoiceState
    voice.onMessage = (message) => {
      // Newest first, and drop an immediate repeat of the same line.
      setMessages((prev) => {
        const newest = prev[0]
        if (newest && newest.speaker === message.speaker && newest.text === message.text) {
          return prev
        }
        return [message, ...prev]
      })
    }
    voice.onRecommendationRequest = ({ merchant: m, amount: a }) => {
      setMerchant(m)
      setAmount(String(a))
      run(m, a)
    }
    // The agent asks the app to activate; the app owns the state.
    voice.onActivationRequest = (offerID) => {
      setActivatedOfferID(offerID)
    }
    return () => {
      voice.onStateChange = undefined
      voice.onMessage = undefined
      voice.onRecommendationRequest = undefined
      voice.onActivationRequest = undefined
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [voice])

  function run(merchantQuery: string, amountValue: number): void {
    try {
      const recommendation = recommend(merchantQuery, Math.round(amountValue * MICRO))
      setResult(recommendation)
      setError(null)
      setActivatedOfferID(null)
      requestAnimationFrame(() => resultRef.current?.focus())
    } catch (err) {
      setError(
        err instanceof RecommendationError
          ? err.message
          : 'Something went wrong working that out.',
      )
      setResult(null)
    }
  }

  function submitTyped(event: React.FormEvent): void {
    event.preventDefault()
    const parsed = parseAmount(amount)
    if (parsed === null) {
      setError('Enter a purchase amount greater than $0.00.')
      setResult(null)
      return
    }
    run(merchant.trim(), parsed / MICRO)
  }

  /**
   * Activates an offer — through the agent when one is running.
   *
   * With voice live this must go via the agent so the user is asked to confirm,
   * matching the iOS `requestActivationConfirmation` behaviour. With voice idle
   * there is nobody to ask, so it happens directly.
   */
  function activateOffer(offerID: string): void {
    if (voiceState.kind !== 'idle') {
      const offer = result?.winner.offerRequiringActivation
      voice.requestActivation(
        offerID,
        offer ? offerShortDescription(offer) : 'this offer',
      )
      return
    }
    setActivatedOfferID(offerID)
  }

  function askAnother(): void {
    setResult(null)
    setError(null)
    setMerchant('')
    setAmount('')
    setActivatedOfferID(null)
    setMessages([])
  }

  const isBusy = voiceState.kind !== 'idle'

  return (
    <div className="stack">
      <section className="stack-tight">
        <h1 className="display">Which card should I use?</h1>
        <p className="muted">
          Tell me where you are and what you'll spend, and I'll pick your best
          card.
        </p>
      </section>

      {/* Voice — simulated, keyless, and labelled as such. */}
      <section className="card stack-tight center-stack">
        <button
          className={isBusy ? 'mic is-live' : 'mic'}
          onClick={() => (isBusy ? voice.stop() : voice.start())}
          aria-label={isBusy ? 'Stop the simulated voice agent' : 'Start the simulated voice agent'}
        >
          <span aria-hidden="true">{isBusy ? '◉' : '🎙'}</span>
        </button>
        <p className="voice-status">{voiceStatusText(voiceState)}</p>

        <p className="notice notice-info">
          Voice is simulated in the browser — no microphone is used and nothing
          is recorded. Typing below is the full experience.
        </p>

        {isBusy && (
          <form
            className="voice-input"
            onSubmit={(e) => {
              e.preventDefault()
              if (utterance.trim() === '') return
              voice.send(utterance)
              setUtterance('')
            }}
          >
            <input
              className="field"
              value={utterance}
              onChange={(e) => setUtterance(e.target.value)}
              placeholder="Type what you'd say, e.g. I'm at Nobu and spending $200"
              aria-label="Say something to the simulated voice agent"
            />
            <button className="btn" type="submit">
              Say it
            </button>
          </form>
        )}

        {messages.length > 0 && (
          <div className="transcript" aria-label="Conversation history, most recent first">
            {messages.slice(0, 4).map((message) => (
              <div key={message.id} className="transcript-line">
                <div className="spread">
                  <span className="muted tiny">
                    {message.speaker === 'you' ? 'You' : 'PointPilot'}
                  </span>
                  <span className="muted tiny mono">
                    {message.at.toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </span>
                </div>
                <p className="small">{message.text}</p>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Typed path — the reliable one. */}
      <section className="card stack-tight">
        <h2 className="section-title">Or choose / type</h2>

        <div className="chips" role="group" aria-label="Nearby restaurants">
          {NEARBY.map((m) => (
            <button
              key={m.id}
              className={merchant.toLowerCase() === m.name.toLowerCase() ? 'chip is-active' : 'chip'}
              onClick={() => setMerchant(m.name)}
              aria-label={`${m.name}${m.hasOffer ? ', active card offer available' : ''}`}
            >
              {m.hasOffer && <span aria-hidden="true">🏷 </span>}
              {m.name}
            </button>
          ))}
        </div>

        <form className="stack-tight" onSubmit={submitTyped}>
          <label className="field-label" htmlFor="merchant">
            Restaurant or merchant
          </label>
          <input
            id="merchant"
            className="field"
            value={merchant}
            onChange={(e) => setMerchant(e.target.value)}
            placeholder="Restaurant, e.g. Nobu"
          />
          <label className="field-label" htmlFor="amount">
            Purchase amount
          </label>
          <input
            id="amount"
            className="field"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="e.g. 200"
          />
          <button className="btn btn-primary btn-block" type="submit">
            Find my best card
          </button>
        </form>

        {error && (
          <p className="notice notice-warn" role="alert">
            {error}
          </p>
        )}
      </section>

      {result && (
        <ResultCard
          recommendation={result}
          activatedOfferID={activatedOfferID}
          onActivate={activateOffer}
          onAskAnother={askAnother}
          ref={resultRef}
        />
      )}

      <section className="stack-tight">
        <h2 className="section-title">Try saying</h2>
        <div className="chips">
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              className="chip"
              onClick={() => {
                if (!isBusy) voice.start()
                voice.send(s)
              }}
            >
              “{s}”
            </button>
          ))}
        </div>
      </section>
    </div>
  )
}

function voiceStatusText(state: VoiceState): string {
  switch (state.kind) {
    case 'idle':
      return 'Tap to talk (simulated)'
    case 'listening':
      return 'Listening…'
    case 'thinking':
      return 'Working that out…'
    case 'speaking':
      return 'Speaking…'
    case 'unavailable':
      return state.message
  }
}

function ResultCard({
  recommendation,
  activatedOfferID,
  onActivate,
  onAskAnother,
  ref,
}: {
  recommendation: CardRecommendation
  activatedOfferID: string | null
  onActivate: (id: string) => void
  onAskAnother: () => void
  ref: React.RefObject<HTMLDivElement>
}) {
  const [showMath, setShowMath] = useState(false)
  const winner = recommendation.winner
  const offer = winner.offerRequiringActivation

  return (
    <section className="stack" ref={ref} tabIndex={-1} aria-live="polite">
      <div className={`cardface accent-${winner.card.id}`}>
        <span className="cardface-name">{winner.card.name}</span>
        <span className="cardface-rate">
          {formatMultiplier(
            (winner.card.multipliers[recommendation.category] ??
              winner.card.defaultMultiplier) * 1_000_000,
          )}{' '}
          {winner.card.rewardUnitName} on{' '}
          {CATEGORY_DISPLAY[recommendation.category].toLowerCase()}
        </span>
        <span className="cardface-note">Sample card</span>
      </div>

      <div className="card">
        <div className="row row-static row-top">
          <span className="row-text">
            <span className="muted">Estimated reward value</span>
            <CountUpCurrency value={winner.totalValue} className="display" />
            <span className="muted small">
              at {recommendation.merchantName} on {format(recommendation.amount)}
            </span>
            {recommendation.runnerUp && (
              <span
                className={
                  recommendation.advantageOverRunnerUp > 0
                    ? 'amount-good'
                    : 'muted small'
                }
              >
                {recommendation.advantageOverRunnerUp > 0
                  ? `${format(recommendation.advantageOverRunnerUp)} more than your ${recommendation.runnerUp.card.name}`
                  : `Tied with your ${recommendation.runnerUp.card.name}`}
              </span>
            )}
          </span>
          <Illustration
            subject={subjectForCategory(recommendation.category)}
            size={72}
          />
        </div>
      </div>

      {recommendation.ranked.length > 1 && (
        <div className="card list-card">
          <h2 className="section-title">How the others compare</h2>
          {recommendation.ranked.slice(1).map((evaluation, index) => (
            <div key={evaluation.card.id}>
              {index > 0 && <div className="divider" />}
              <div className="spread row-pad">
                <span>{evaluation.card.name}</span>
                <span className="amount mono">{format(evaluation.totalValue)}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="card stack-tight">
        <h2 className="section-title">Why this card?</h2>
        <p className="muted">{recommendation.explanation}</p>
      </div>

      <div className="card stack-tight">
        <button
          className="btn btn-ghost"
          onClick={() => setShowMath((s) => !s)}
          aria-expanded={showMath}
        >
          ƒ See the math
        </button>

        {showMath && (
          <div className="stack-tight">
            {winner.components.map((component, index) => (
              <div key={`${component.kind}-${index}`}>
                <div className="spread row-pad">
                  <span className="row-text">
                    <span className="row-title">
                      {COMPONENT_DISPLAY[component.kind]}
                    </span>
                    <span className="muted tiny">{component.label}</span>
                  </span>
                  <span
                    className={
                      component.amount < 0 ? 'mono muted' : 'mono'
                    }
                  >
                    {formatSigned(component.amount)}
                  </span>
                </div>
                <div className="divider" />
              </div>
            ))}
            <div className="spread strong">
              <span>Total estimated value</span>
              <span className="mono">{format(winner.totalValue)}</span>
            </div>
          </div>
        )}
      </div>

      {offer && (
        <div className="card stack-tight">
          <h2 className="section-title">This offer needs activation</h2>
          <p className="muted">
            {offerShortDescription(offer)} at {recommendation.merchantName}, worth
            up to {format(offer.maximumValue ?? winner.totalValue)}.
          </p>
          <button
            className="btn btn-primary btn-block"
            disabled={activatedOfferID === offer.id}
            onClick={() => onActivate(offer.id)}
          >
            {activatedOfferID === offer.id
              ? '✓ Activated (simulated)'
              : 'Activate offer'}
          </button>
          <p className="muted tiny">
            Demo action — this does not activate anything with your card issuer.
          </p>
        </div>
      )}

      {recommendation.warnings.map((warning) => (
        <p key={warning} className="notice notice-info">
          {warning}
        </p>
      ))}

      <button className="btn btn-block" onClick={onAskAnother}>
        Ask another
      </button>

      <p className="muted tiny center">
        Points and miles are valued at the sample rates: e.g.{' '}
        {formatRate(1_000_000 * 0.0175)} per point on the Sapphire Preferred.
      </p>
    </section>
  )
}
