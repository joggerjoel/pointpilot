import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import type { UserEvent } from '@testing-library/user-event'
import { App } from './App'

/**
 * End-to-end tests of the web app, driving the real UI.
 *
 * The parity suite proves the engine agrees with the iOS app; this proves the
 * screens are actually wired to it — the same division the iOS project uses
 * between `RecommendationEngineTests` and `DemoFlowUITests`.
 */

/**
 * Navigates to the finder, types a purchase, and submits it.
 *
 * The app opens on the home screen, so the first click has to get there. Only
 * one "Find my best card" button is mounted at a time, so the same query finds
 * the hero CTA on Home and the form's submit button on the finder.
 */
async function submitPurchase(
  user: UserEvent,
  merchant: string,
  amount: string,
): Promise<void> {
  await user.click(screen.getByRole('button', { name: /find my best card/i }))
  await user.type(screen.getByLabelText(/restaurant or merchant/i), merchant)
  await user.type(screen.getByLabelText(/purchase amount/i), amount)
  await user.click(screen.getByRole('button', { name: /find my best card/i }))
}

describe('the web app', () => {
  it("opens on the home screen with the engine's own totals", async () => {
    render(<App />)

    expect(
      screen.getByRole('heading', { name: /how can i help you today/i }),
    ).toBeInTheDocument()

    // $66.78 earned / $9.05 missed come from replaying the demo history through
    // the engine, not from a hard-coded string.
    expect(screen.getByText('$66.78')).toBeInTheDocument()
    expect(screen.getByText('$9.05')).toBeInTheDocument()

    // The finder's fields must not exist until the user asks for them.
    expect(screen.queryByLabelText(/restaurant or merchant/i)).not.toBeInTheDocument()
  })

  it('recommends Amex Gold for Nobu at $200, with the full breakdown', async () => {
    const user = userEvent.setup()
    render(<App />)

    await submitPurchase(user, 'Nobu', '200')

    // The winner's card face names the recommended card.
    expect(await screen.findByText('Amex Gold')).toBeInTheDocument()
    expect(screen.getByText('Estimated reward value')).toBeInTheDocument()

    // $45.00 totals $16.00 + $20.00 + $9.00 once the math is expanded.
    await user.click(screen.getByRole('button', { name: /see the math/i }))

    expect(screen.getByText('Card rewards')).toBeInTheDocument()
    expect(screen.getByText('+$16.00')).toBeInTheDocument()
    expect(screen.getByText('Merchant offer')).toBeInTheDocument()
    expect(screen.getByText('+$20.00')).toBeInTheDocument()
    expect(screen.getByText('Airline dining rewards')).toBeInTheDocument()
    expect(screen.getByText('+$9.00')).toBeInTheDocument()
    expect(screen.getByText('Total estimated value')).toBeInTheDocument()

    // The runner-up comparison names the Sapphire and its total.
    expect(screen.getByText('How the others compare')).toBeInTheDocument()
    expect(screen.getByText('Chase Sapphire Preferred')).toBeInTheDocument()
    expect(screen.getByText('$19.50')).toBeInTheDocument()
  })

  it('shows the capped offer as an explicit −$30.00 deduction', async () => {
    const user = userEvent.setup()
    render(<App />)

    await submitPurchase(user, 'Nobu', '500')
    await user.click(await screen.findByRole('button', { name: /see the math/i }))

    // 10% of $500 is $50, capped at $20, so the adjustment is −$30.00.
    expect(screen.getByText('Offer cap adjustment')).toBeInTheDocument()
    expect(screen.getByText('−$30.00')).toBeInTheDocument()
    expect(screen.getByText('Capped at $20.00')).toBeInTheDocument()
  })

  it('invents no offer for an unknown merchant', async () => {
    const user = userEvent.setup()
    render(<App />)

    await submitPurchase(user, "Joe's Random Diner", '200')
    await user.click(await screen.findByRole('button', { name: /see the math/i }))

    expect(screen.getByText('Card rewards')).toBeInTheDocument()
    expect(screen.queryByText('Merchant offer')).not.toBeInTheDocument()
  })

  it('rejects a zero amount without producing a recommendation', async () => {
    const user = userEvent.setup()
    render(<App />)

    await submitPurchase(user, 'Nobu', '0')

    expect(
      await screen.findByText(/enter a purchase amount greater than \$0\.00/i),
    ).toBeInTheDocument()
    expect(screen.queryByText('Estimated reward value')).not.toBeInTheDocument()
  })

  it('simulates offer activation and says so', async () => {
    const user = userEvent.setup()
    render(<App />)

    await submitPurchase(user, 'Nobu', '200')

    const activate = await screen.findByRole('button', { name: /^activate offer$/i })
    await user.click(activate)

    const activated = screen.getByRole('button', { name: /activated \(simulated\)/i })
    expect(activated).toBeDisabled()
    expect(
      screen.getByText(/this does not activate anything with your card issuer/i),
    ).toBeInTheDocument()
  })

  it('opens the rewards dashboard with its headline sections', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /see my rewards/i }))

    expect(await screen.findByText('Card leaderboard')).toBeInTheDocument()
    expect(screen.getByText('Left on the table')).toBeInTheDocument()
    expect(screen.getByText('Where you spent')).toBeInTheDocument()
    expect(screen.getByText('Activity')).toBeInTheDocument()
    // The demo disclosure must always be present.
    expect(screen.getAllByText(/nothing here is financial advice/i).length).toBeGreaterThan(0)
  })

  it('opens the wallet with all three sample cards', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /my wallet/i }))

    const dialog = await screen.findByRole('dialog', { name: /wallet/i })
    expect(within(dialog).getByText('Amex Gold')).toBeInTheDocument()
    expect(within(dialog).getByText('Chase Sapphire Preferred')).toBeInTheDocument()
    expect(within(dialog).getByText('Capital One Venture')).toBeInTheDocument()
  })

  it('runs the simulated voice agent end to end and labels it as simulated', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /find my best card/i }))
    // The label flips between start/stop, so match the part that is stable.
    await user.click(screen.getByRole('button', { name: /simulated voice agent/i }))

    // The greeting appears, and says the voice is simulated.
    expect(await screen.findByText(/demo voice is on/i)).toBeInTheDocument()
    expect(screen.getByText(/no audio is recorded/i)).toBeInTheDocument()

    await user.type(
      screen.getByLabelText(/say something to the simulated voice agent/i),
      "I'm at Nobu and spending around $200",
    )
    await user.click(screen.getByRole('button', { name: /say it/i }))

    // The agent parses the sentence and the engine answers with the same figure
    // the typed path produces. The line appears in the transcript and again as
    // the result's explanation, so more than one match is expected.
    expect(
      (await screen.findAllByText(/Use your Amex Gold at Nobu/i)).length,
    ).toBeGreaterThan(0)

    // The headline figure is a count-up, so the exact total only settles once
    // the animation finishes — wait for it rather than racing it.
    await waitFor(
      () => {
        expect(screen.getAllByText('$45.00').length).toBeGreaterThan(0)
      },
      { timeout: 2500 },
    )
  })

  it('does not duplicate the greeting when the mic is toggled repeatedly', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /find my best card/i }))

    // Start, then stop, using the stable part of the label in both states.
    await user.click(screen.getByRole('button', { name: /simulated voice agent/i }))
    await user.click(screen.getByRole('button', { name: /simulated voice agent/i }))

    expect(screen.getAllByText(/demo voice is on/i)).toHaveLength(1)
  })

  it('auto-fills the merchant field from a nearby chip', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /find my best card/i }))
    await user.click(screen.getByRole('button', { name: /^Nobu/ }))

    expect(screen.getByLabelText(/restaurant or merchant/i)).toHaveValue('Nobu')
  })

  it('activates an offer through the agent only after the user confirms', async () => {
    const user = userEvent.setup()
    render(<App />)

    await user.click(screen.getByRole('button', { name: /find my best card/i }))
    // Start a session so activation has someone to confirm with.
    await user.click(screen.getByRole('button', { name: /simulated voice agent/i }))

    await user.type(screen.getByLabelText(/restaurant or merchant/i), 'Nobu')
    await user.type(screen.getByLabelText(/purchase amount/i), '200')
    await user.click(screen.getByRole('button', { name: /find my best card/i }))

    // Tapping activate while a session is live must ask first, not activate.
    await user.click(await screen.findByRole('button', { name: /^activate offer$/i }))

    expect(await screen.findByText(/activate 10% back\?/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /^activate offer$/i })).toBeEnabled()

    // A refusal leaves it un-activated.
    await user.type(
      screen.getByLabelText(/say something to the simulated voice agent/i),
      'no thanks',
    )
    await user.click(screen.getByRole('button', { name: /say it/i }))

    expect(await screen.findByText(/nothing was activated/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /^activate offer$/i })).toBeEnabled()

    // A confirmation performs it.
    await user.click(screen.getByRole('button', { name: /^activate offer$/i }))
    await user.type(
      screen.getByLabelText(/say something to the simulated voice agent/i),
      'yes',
    )
    await user.click(screen.getByRole('button', { name: /say it/i }))

    const activated = await screen.findByRole('button', {
      name: /activated \(simulated\)/i,
    })
    expect(activated).toBeDisabled()
  })
})
