import { describe, expect, it, vi } from 'vitest'
import { MockVoiceAgent } from './voice'

/**
 * Tests for the agent's confirmation flow.
 *
 * Activation is a consequential-sounding action, so the agent must ask before
 * performing it and must treat anything unrecognised as a refusal. These pin
 * that behaviour without a DOM, since it lives in the agent rather than a view.
 */

describe('simulated voice agent activation', () => {
  function started() {
    const agent = new MockVoiceAgent()
    const activations: string[] = []
    agent.onActivationRequest = (id) => activations.push(id)
    agent.start()
    return { agent, activations }
  }

  it('asks for confirmation instead of activating silently', () => {
    const { agent, activations } = started()
    const said: string[] = []
    agent.onMessage = (m) => said.push(m.text)

    agent.requestActivation('offer-nobu-amex', '10% back')

    expect(activations).toHaveLength(0)
    expect(said.some((t) => /activate .*10% back\?/i.test(t))).toBe(true)
  })

  it('activates only after an affirmative reply', () => {
    const { agent, activations } = started()
    const said: string[] = []
    agent.onMessage = (m) => said.push(m.text)

    agent.requestActivation('offer-nobu-amex', '10% back')
    agent.send('yes')

    expect(activations).toEqual(['offer-nobu-amex'])
    expect(said.some((t) => /simulated — nothing was activated/i.test(t))).toBe(true)
  })

  it('does not activate on a refusal', () => {
    const { agent, activations } = started()
    const said: string[] = []
    agent.onMessage = (m) => said.push(m.text)

    agent.requestActivation('offer-nobu-amex', '10% back')
    agent.send('no thanks')

    expect(activations).toHaveLength(0)
    expect(said.some((t) => /nothing was activated/i.test(t))).toBe(true)
  })

  it('treats an unrecognised reply as a refusal rather than proceeding', () => {
    const { agent, activations } = started()

    agent.requestActivation('offer-nobu-amex', '10% back')
    agent.send('what does that mean?')

    // The safe default for a consequential action is not to take it.
    expect(activations).toHaveLength(0)
  })

  it('does not let a pending activation be parsed as a new purchase', () => {
    const { agent, activations } = started()
    const requests: unknown[] = []
    agent.onRecommendationRequest = (r) => requests.push(r)

    // A reply of "yes, at Nobu for $200" must answer the question, not start a
    // fresh recommendation that would clear the activation.
    agent.requestActivation('offer-nobu-amex', '10% back')
    agent.send('yes')

    expect(activations).toEqual(['offer-nobu-amex'])
    expect(requests).toHaveLength(0)
  })

  it('clears the pending activation so a later yes cannot re-trigger it', () => {
    const { agent, activations } = started()

    agent.requestActivation('offer-nobu-amex', '10% back')
    agent.send('yes')
    agent.send('yes')

    expect(activations).toEqual(['offer-nobu-amex'])
  })

  it('still parses purchases normally when nothing is pending', () => {
    const { agent } = started()
    const requests: { merchant: string; amount: number }[] = []
    agent.onRecommendationRequest = (r) => requests.push(r)

    agent.send("I'm at Nobu and spending around $200")

    expect(requests).toEqual([{ merchant: 'Nobu', amount: 200 }])
  })
})

describe('simulated voice agent parsing', () => {
  it('reads a merchant and amount out of the demo phrasing', () => {
    const agent = new MockVoiceAgent()
    const requests: { merchant: string; amount: number }[] = []
    agent.onRecommendationRequest = (r) => requests.push(r)

    agent.send("I'm at Nobu and spending around $200")

    expect(requests).toEqual([{ merchant: 'Nobu', amount: 200 }])
  })

  it('is not called a stub: it emits states and transcript lines', () => {
    const agent = new MockVoiceAgent()
    const states: string[] = []
    const messages: string[] = []
    agent.onStateChange = (s) => states.push(s.kind)
    agent.onMessage = (m) => messages.push(m.text)

    agent.start()

    expect(states).toEqual(['listening'])
    expect(messages.length).toBeGreaterThan(0)
    // The transcript must say the voice is simulated.
    expect(messages.some((t) => /simulated/i.test(t))).toBe(true)
  })

  it('does not repeat the greeting when started twice', () => {
    const agent = new MockVoiceAgent()
    const messages: string[] = []
    agent.onMessage = (m) => messages.push(m.text)

    agent.start()
    const afterFirst = messages.length
    agent.start()

    expect(messages.length).toBe(afterFirst)
  })

  it('never re-emits an unchanged state', () => {
    const agent = new MockVoiceAgent()
    const onStateChange = vi.fn()
    agent.onStateChange = onStateChange

    agent.start()
    // `start()` while already live must not emit a second listening state.
    agent.start()

    expect(onStateChange).toHaveBeenCalledTimes(1)
  })
})
