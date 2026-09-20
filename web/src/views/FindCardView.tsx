import { useEffect, useRef, useState } from 'react'
import { format, formatSigned, formatRate, formatMultiplier } from '../lib/money'
import { recommend, offerShortDescription, RecommendationError } from '../lib/engine'
import { parseAmount } from '../lib/sampleData'
import { COMPONENT_DISPLAY, CATEGORY_DISPLAY, subjectForCategory } from '../lib/types'
import type { CardRecommendation } from '../lib/types'
import { type VoiceAgent, type VoiceMessage, type VoiceState } from '../lib/voice'
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
export function FindCardView({ voice }: { voice: VoiceAgent }) {
  const [merchant, setMerchant] = useState('')
  const [amount, setAmount] = useState('')
  const [result, setResult] = useState<CardRecommendation | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [activatedOfferID, setActivatedOfferID] = useState<string | null>(null)
  const [voiceState, setVoiceState] = useState<VoiceState>({ kind: 'idle' })
  const [messages, setMessages] = useState<VoiceMessage[]>([])
  const [utterance, setUtterance] = useState('')
  const [isRecording, setIsRecording] = useState(false)
  const mediaRecorderRef = useRef<MediaRecorder | null>(null)
  const audioChunksRef = useRef<Blob[]>([])

  const resultRef = useRef<HTMLDivElement>(null)

  // Wire the agent's callbacks once. The agent supplies the inputs; this view
  // computes the answer through the engine.
  useEffect(() => {
    voice.onStateChange = (state) => {
      setVoiceState(state)
      // If agent is listening and we are recording, it means agent is ready for audio.
      // We can stop recording now, as the ElevenLabs SDK will handle microphone input itself.
      if (state.kind === 'listening' && voice.isConfigured && isRecording) {
        stopRecording()
      }
    }
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
  }, [voice, isRecording])

  const startRecording = async () => {
    if (!voice.isConfigured || !navigator.mediaDevices) return

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      // In a real scenario, the ElevenLabs SDK handles streaming the microphone input directly.
      // For now, this part is illustrative for local recording purposes if needed.
      mediaRecorderRef.current = new MediaRecorder(stream)
      audioChunksRef.current = []

      mediaRecorderRef.current.ondataavailable = (event) => {
        audioChunksRef.current.push(event.data)
      }

      mediaRecorderRef.current.onstop = () => {
        // Audio chunks can be processed here if not using SDK's direct streaming.
        audioChunksRef.current = []
      }

      mediaRecorderRef.current.start()
      setIsRecording(true)
    } catch (err) {
      console.error('Error accessing microphone:', err)
      voice.onStateChange?.({ kind: 'unavailable', message: 'Microphone access denied.' })
    }
  }

  const stopRecording = () => {
    if (mediaRecorderRef.current?.state === 'recording') {
      mediaRecorderRef.current.stop()
      setIsRecording(false)
    }
  }

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
    // If a real voice agent is configured and active, typed input is sent through it.
    if (voice.isConfigured && voiceState.kind !== 'idle' && voiceState.kind !== 'unavailable') {
      voice.send(utterance)
      setUtterance('')
      return
    }
    // Otherwise, fallback to the traditional typed input submission.
    const parsed = parseAmount(amount)
    if (parsed === null) {
      setError('Enter a purchase amount greater than $0.00.')
      setResult(null)
      return
    }
    run(merchant.trim(), parsed / MICRO)
  }

  function onToggleVoice(): void {
    if (voiceState.kind !== 'idle' && voiceState.kind !== 'unavailable') {
      voice.stop()
      stopRecording()
    } else {
      voice.start()
    }
  }

  function onActivate(offerID: string, label: string): void {
    if (voice.isConfigured) {
      voice.requestActivation(offerID, label)
    } else {
      // Fallback for mock agent, which handles its own confirmation flow.
      voice.onActivationRequest?.(offerID) // Direct activation for mock if no confirmation needed
    }
  }

  function onAskAnother(): void {
    setMerchant('')
    setAmount('')
    setResult(null)
    setError(null)
    setActivatedOfferID(null)
    setMessages([])
    setUtterance('')
    // Do not reset voiceState here, let the agent manage its own state.
  }

  const microphoneStatusText = voiceState.kind === 'unavailable' && voiceState.message.includes('Microphone')
    ? 'Microphone access denied.'
    : voiceState.kind === 'unavailable'
      ? voiceState.message
      : undefined

  // Determine if the microphone icon should be active based on voice state and recording status
  const isMicrophoneActive = voice.isConfigured ? (voiceState.kind === 'listening' || voiceState.kind === 'speaking') : isRecording;

  return (
    <section className="card-finder">
      <h1 className="card-finder-headline">Which card should I use?</h1>

      <div className="voice-input">
        <button
          className="voice-button"
          onClick={onToggleVoice}
          disabled={voiceState.kind === 'unavailable' && !voiceState.message.includes('Microphone')}
          aria-label={voiceState.kind === 'listening' ? 'Stop voice input' : 'Start voice input'}
        >
          {isMicrophoneActive ? (
            <span className="icon-microphone-active" aria-hidden="true"></span>
          ) : (
            <span className="icon-microphone" aria-hidden="true"></span>
          )}
          <span className="voice-status-text">
            {voiceState.kind === 'listening'
              ? 'Speak now…'
              : voiceState.kind === 'thinking'
                ? 'Thinking…'
                : voiceState.kind === 'speaking'
                  ? 'Speaking…'
                  : voiceState.kind === 'unavailable'
                    ? 'Voice unavailable'
                    : 'Tap to speak'}
          </span>
        </button>
        {microphoneStatusText && (
          <p className="voice-notice notice notice-error">
            {microphoneStatusText}
          </p>
        )}

        {!voice.isConfigured && (
          <p className="voice-notice notice notice-info">
            Voice is simulated in the browser — no microphone is used and nothing
            is recorded. Typing below is the full experience.
          </p>
        )}

        {voice.isConfigured && voiceState.kind !== 'idle' && voiceState.kind !== 'unavailable' && (
          <div className="transcript">
            {messages.map((message) => (
              <div
                key={message.id}
                className={`transcript-line speaker-${message.speaker}`}
              >
                <span className="speaker">{message.speaker === 'you' ? 'You' : 'PointPilot'}:</span>
                <span className="text">{message.text}</span>
                <time className="timestamp" dateTime={message.at.toISOString()}>
                  {message.at.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </time>
              </div>
            ))}
          </div>
        )}

        {voice.isConfigured && voiceState.kind !== 'idle' && voiceState.kind !== 'unavailable' && (
          <form onSubmit={submitTyped} className="voice-text-input">
            <input
              type="text"
              value={utterance}
              onChange={(e) => setUtterance(e.target.value)}
              placeholder={voiceState.kind === 'listening' ? 'Say something…' : 'Type your reply…'}
              autoFocus
              disabled={voiceState.kind === 'thinking' || voiceState.kind === 'speaking'}
              aria-label="Type your reply"
            />
            <button
              type="submit"
              disabled={utterance.trim().length === 0 || voiceState.kind === 'thinking' || voiceState.kind === 'speaking'}
            >
              Send
            </button>
          </form>
        )}
      </div>

      <div className="typed-input">
        <p className="typed-input-header">Or pick from nearby, or type it</p>
        <div className="nearby-chips">
          {NEARBY.map((merchant) => (
            <button
              key={merchant.id}
              className="chip"
              onClick={() => setMerchant(merchant.name)}
            >
              {merchant.hasOffer && (
                <span className="chip-tag" aria-hidden="true"></span>
              )}
              {merchant.name}
            </button>
          ))}
        </div>

        <form onSubmit={submitTyped} className="form-fields">
          <label htmlFor="merchant-input" className="sr-only">
            Restaurant, e.g. Nobu
          </label>
          <input
            type="text"
            id="merchant-input"
            placeholder="Restaurant, e.g. Nobu"
            value={merchant}
            onChange={(e) => setMerchant(e.target.value)}
            autoCapitalize="words"
          />

          <label htmlFor="amount-input" className="sr-only">
            Amount, e.g. $200
          </label>
          <input
            type="text"
            id="amount-input"
            placeholder="Amount, e.g. $200"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            inputMode="decimal"
          />

          <button type="submit" className="btn btn-primary btn-block">
            Find My Best Card
          </button>
        </form>

        {error && <p className="notice notice-error">{error}</p>}

        {result && (
          <section ref={resultRef} tabIndex={-1} className="recommendation">
            <h2 className="recommendation-headline">
              Use {result.winner.card.name}
            </h2>
            <Illustration category={result.winner.category} />
            <p className="recommendation-value">
              Estimated value:{' '}
              <CountUpCurrency value={format(result.winner.totalValue)} />
            </p>
            <p className="recommendation-breakdown-toggle">
              <button
                onClick={() => setShowBreakdown(!showBreakdown)}
                aria-expanded={showBreakdown}
                aria-controls="breakdown-details"
              >
                {showBreakdown ? 'Hide breakdown' : 'Show breakdown'}
              </button>
            </p>

            {showBreakdown && (
              <dl id="breakdown-details" className="recommendation-breakdown">
                {result.winner.components.map((component) => (
                  <div
                    key={component.kind + (component.offerID || '')}
                    className="breakdown-item"
                  >
                    <dt className="breakdown-item-label">
                      {COMPONENT_DISPLAY[component.kind]}
                    </dt>
                    <dd className="breakdown-item-value">
                      {formatSigned(component.value)}
                    </dd>
                  </div>
                ))}
                <div className="breakdown-item breakdown-item-total">
                  <dt className="breakdown-item-label">Total</dt>
                  <dd className="breakdown-item-value">
                    {format(result.winner.totalValue)}
                  </dd>
                </div>
              </dl>
            )}

            {result.runnerUp && (
              <section className="recommendation-runner-up">
                <h3>
                  Runner-up: {result.runnerUp.card.name} ({format(result.runnerUp.totalValue)})
                </h3>
                <p className="recommendation-runner-up-advantage">
                  Advantage: {format(result.winner.totalValue - result.runnerUp.totalValue)}
                </p>
              </section>
            )}

            {result.winner.offer && (
              <div className="recommendation-offer">
                <h3>Merchant offer</h3>
                <p>
                  Earn {offerShortDescription(result.winner.offer)}. Up to {format(result.winner.offer.maximumValue ?? result.winner.totalValue)}.
                </p>
                <button
                  className="btn btn-primary btn-block"
                  disabled={activatedOfferID === result.winner.offer.id}
                  onClick={() => onActivate(result.winner.offer!.id, offerShortDescription(result.winner.offer!))}
                >
                  {activatedOfferID === result.winner.offer.id
                    ? '✓ Activated (simulated)'
                    : 'Activate offer'}
                </button>
                <p className="muted tiny">
                  Demo action — this does not activate anything with your card issuer.
                </p>
              </div>
            )}

            {result.warnings.map((warning) => (
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
        )}
      </div>
    </section>
  )
}

function HiddenBreakdownToggle({ showBreakdown, setShowBreakdown }: { showBreakdown: boolean; setShowBreakdown: (show: boolean) => void }) {
  return (
    <p className="recommendation-breakdown-toggle">
      <button
        onClick={() => setShowBreakdown(!showBreakdown)}
        aria-expanded={showBreakdown}
        aria-controls="breakdown-details"
      >
        {showBreakdown ? 'Hide breakdown' : 'Show breakdown'}
      </button>
    </p>
  )
}
