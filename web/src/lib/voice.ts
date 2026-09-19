import { recommend, type RecommendOptions } from './engine'
import { parseAmount } from './sampleData'
import type { CardRecommendation } from './types'

/**
 * A keyless voice agent for the browser.
 *
 * This is the web counterpart of `MockVoiceAgentService`: it is not a stub. It
 * runs a real state machine, emits real transcript lines, and parses sentences
 * like "I'm at Nobu and spending around $200" into a tool call through the same
 * boundary a real agent would use. The transcript says plainly that the voice is
 * simulated.
 *
 * Voice is typed-only in this version: there is no microphone and no audio. The
 * `VoiceAgent` interface is the seam a WebRTC/ElevenLabs adapter would fill,
 * without any view needing to change.
 */

export type VoiceState =
  | { kind: 'idle' }
  | { kind: 'listening' }
  | { kind: 'thinking' }
  | { kind: 'speaking' }
  | { kind: 'unavailable'; message: string }

export interface VoiceMessage {
  id: string
  speaker: 'you' | 'agent'
  text: string
  at: Date
}

export interface VoiceRecommendationRequest {
  merchant: string
  amount: number
}

export interface VoiceAgent {
  isConfigured: boolean
  onStateChange?: (state: VoiceState) => void
  onMessage?: (message: VoiceMessage) => void
  onRecommendationRequest?: (request: VoiceRecommendationRequest) => void
  /**
   * Asks the app to simulate activating an offer.
   *
   * The agent never activates anything itself — it reports the intent and the
   * app performs it, the same division the iOS `VoiceAgentProviding` uses.
   * Activation is never silent: the user confirms first.
   */
  onActivationRequest?: (offerID: string) => void
  start(): void
  stop(): void
  send(text: string): void
  /** Asks the agent to confirm an activation with the user before performing it. */
  requestActivation(offerID: string, label: string): void
}

/** Reads a merchant and an amount out of a free-text sentence. */
export function parseUtterance(text: string): VoiceRecommendationRequest | null {
  const amount = extractAmount(text)
  const merchant = extractMerchant(text)
  if (amount === null || merchant === null) return null
  return { merchant, amount }
}

/**
 * Pulls a dollar amount out of a sentence.
 *
 * Handles "around $200", "200 dollars", "spending 42.50". Returns null when no
 * amount is present, so the caller can ask a follow-up rather than guessing.
 */
export function extractAmount(text: string): number | null {
  const match = text.match(/\$?\s*(\d+(?:\.\d{1,2})?)/)
  if (!match) return null
  const value = Number(match[1])
  return Number.isFinite(value) && value > 0 ? value : null
}

const KNOWN_MERCHANTS = [
  'Nobu',
  'Shake Shack',
  'Chipotle',
  'Starbucks',
  'Whole Foods',
  'Shell',
  'Apple Store',
  'AMC Theatres',
]

/**
 * Pulls a merchant name out of a sentence.
 *
 * Prefers a known sample merchant mentioned anywhere in the text, then falls
 * back to the words after "at"/"I'm at"/"spending at". Returns null when
 * nothing usable is found.
 */
export function extractMerchant(text: string): string | null {
  const lower = text.toLowerCase()

  for (const name of KNOWN_MERCHANTS) {
    if (lower.includes(name.toLowerCase())) return name
  }

  const atMatch = text.match(/\bat\s+([A-Za-z0-9'&.\- ]{2,40})/i)
  if (atMatch) {
    // Trim a trailing amount clause: "Nobu and spending around" -> "Nobu".
    const cleaned = atMatch[1]
      .split(/\s+(?:and|for|spending|around|about|on)\b/i)[0]
      .trim()
      .replace(/[.,!?]+$/, '')
    if (cleaned.length >= 2) return cleaned
  }

  return null
}

let counter = 0
function nextId(prefix: string): string {
  counter += 1
  return `${prefix}-${counter}`
}

/** The local, keyless voice agent. */
export class MockVoiceAgent implements VoiceAgent {
  readonly isConfigured = true

  onStateChange?: (state: VoiceState) => void
  onMessage?: (message: VoiceMessage) => void
  onRecommendationRequest?: (request: VoiceRecommendationRequest) => void
  onActivationRequest?: (offerID: string) => void

  private state: VoiceState = { kind: 'idle' }

  /**
   * An offer the agent is waiting for the user to confirm before "activating".
   *
   * Activation is never silent: the user is asked, and only an affirmative
   * reply proceeds.
   */
  private pendingActivation: { offerID: string; label: string } | null = null

  private readonly options: RecommendOptions

  constructor(options: RecommendOptions = {}) {
    this.options = options
  }

  private setState(state: VoiceState): void {
    // Defensive: never re-emit a state that has not changed, so the UI (and a
    // screen reader) is not re-rendered for nothing.
    if (JSON.stringify(state) === JSON.stringify(this.state)) return
    this.state = state
    this.onStateChange?.(state)
  }

  private say(text: string): void {
    this.onMessage?.({
      id: nextId('agent'),
      speaker: 'agent',
      text,
      at: new Date(),
    })
  }

  start(): void {
    // Ignore a start while a session is already live, so repeated taps cannot
    // stack duplicate greetings.
    if (this.state.kind !== 'idle') return

    this.setState({ kind: 'listening' })
    this.say(
      "Demo voice is on. Tell me the restaurant and roughly how much you'll spend.",
    )
    this.say(
      'Heads up: this voice is simulated in the browser — no audio is recorded.',
    )
  }

  stop(): void {
    this.setState({ kind: 'idle' })
  }

  /**
   * Asks the user to confirm an activation before performing it.
   *
   * Activation is a consequential-sounding action, so it is never silent even
   * in a demo — the agent asks, and interprets the next reply as the answer.
   */
  requestActivation(offerID: string, label: string): void {
    this.pendingActivation = { offerID, label }
    this.setState({ kind: 'speaking' })
    this.say(`Activate ${label}? This is simulated — say yes or no.`)
  }

  /**
   * Resolves a pending activation from the user's reply.
   *
   * Only an affirmative proceeds. Anything unrecognised is treated as a no,
   * because the safe default for a consequential action is not to take it.
   */
  private resolveActivation(reply: string): void {
    const pending = this.pendingActivation
    if (!pending) return
    this.pendingActivation = null

    const text = reply.toLowerCase()
    const yes = /\b(yes|yeah|yep|sure|ok|okay|activate|do it|please)\b/.test(text)
    const no = /\b(no|nope|don't|dont|stop|cancel|never)\b/.test(text)

    if (yes && !no) {
      // The agent reports the intent; the app performs the activation.
      this.onActivationRequest?.(pending.offerID)
      this.setState({ kind: 'speaking' })
      this.say(
        'Activated in the demo. This is simulated — nothing was activated with the issuer.',
      )
      return
    }

    this.setState({ kind: 'listening' })
    this.say('No problem — nothing was activated.')
  }

  send(text: string): void {
    const trimmed = text.trim()
    if (trimmed === '') return

    this.onMessage?.({
      id: nextId('you'),
      speaker: 'you',
      text: trimmed,
      at: new Date(),
    })

    // A pending activation takes precedence: this reply answers "should I
    // activate it?", so it must not be parsed as a new purchase.
    if (this.pendingActivation) {
      this.resolveActivation(trimmed)
      return
    }

    this.setState({ kind: 'thinking' })

    const parsed = parseUtterance(trimmed)
    if (!parsed) {
      this.setState({ kind: 'listening' })
      this.say(
        parsed === null && extractAmount(trimmed) === null
          ? 'How much do you plan to spend?'
          : 'Which restaurant or merchant are you at?',
      )
      return
    }

    // The agent supplies the inputs; the app computes the answer.
    this.onRecommendationRequest?.(parsed)

    let result: CardRecommendation
    try {
      result = recommend(parsed.merchant, parsed.amount * 1_000_000, this.options)
    } catch {
      this.setState({ kind: 'listening' })
      this.say("I couldn't work that out. Try naming the merchant and an amount.")
      return
    }

    this.setState({ kind: 'speaking' })
    this.say(result.explanation)
  }
}

/** Formats a typed amount for display without a currency symbol. */
export function amountText(value: string): string {
  const parsed = parseAmount(value)
  if (parsed === null) return value
  return String(parsed / 1_000_000)
}
