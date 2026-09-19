import { format, formatMultiplier, formatRate } from '../lib/money'
import { multiplierFor, rateDescription } from '../lib/engine'
import { sampleCards, sampleOffers, sampleMerchants, sampleDiningProgram } from '../lib/sampleData'

/**
 * The read-only wallet, shown as a dismissible panel.
 *
 * Cards, rates and offers all come from the shared sample data, so this screen
 * can never disagree with the finder.
 */
export function WalletView({ onClose }: { onClose: () => void }) {
  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-label="Wallet"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="spread sheet-head">
          <h2 className="section-title">Your cards</h2>
          <button className="btn btn-ghost" onClick={onClose}>
            Done
          </button>
        </div>

        <div className="stack">
          {sampleCards.map((card) => {
            const offer = sampleOffers.find((o) => o.cardID === card.id)
            const offerMerchant = offer
              ? sampleMerchants.find((m) => m.id === offer.merchantID)
              : undefined

            return (
              <div key={card.id} className="stack-tight">
                <div className={`cardface accent-${card.id}`}>
                  <span className="cardface-name">{card.name}</span>
                  <span className="cardface-rate">
                    {rateDescription(card, 'dining')}
                  </span>
                  <span className="cardface-note">Sample card</span>
                </div>

                <dl className="spec">
                  <div className="spec-row">
                    <dt>Dining</dt>
                    <dd>{rateDescription(card, 'dining')}</dd>
                  </div>
                  <div className="spec-row">
                    <dt>Everything else</dt>
                    <dd>
                      {formatMultiplier(card.defaultMultiplier * 1_000_000)}{' '}
                      {card.rewardUnitName}
                    </dd>
                  </div>
                  <div className="spec-row">
                    <dt>{card.rewardUnitName} value</dt>
                    <dd>{formatRate(card.pointValue)} each</dd>
                  </div>
                  <div className="spec-row">
                    <dt>Gas</dt>
                    <dd>
                      {multiplierFor(card, 'gas')}× {card.rewardUnitName}
                    </dd>
                  </div>
                  {offer && offerMerchant && (
                    <div className="spec-row">
                      <dt>Merchant offer</dt>
                      <dd>
                        {offer.offer.kind === 'percentage'
                          ? `${(offer.offer.rate / 1_000_000) * 100}% back`
                          : `${format(offer.offer.value)} back`}{' '}
                        at {offerMerchant.name}
                        {offer.maximumValue !== null &&
                          `, up to ${format(offer.maximumValue)}`}
                      </dd>
                    </div>
                  )}
                </dl>
              </div>
            )
          })}

          <div className="stack-tight">
            <h3 className="section-title">Airline dining program</h3>
            <p className="muted small">
              {sampleDiningProgram.name}:{' '}
              {sampleDiningProgram.milesPerDollar} miles per dollar at
              participating restaurants, worth{' '}
              {formatRate(sampleDiningProgram.mileValue)} per mile.
            </p>
          </div>

          <p className="muted tiny">
            Demo data — sample cards and offers. Read-only, and not affiliated
            with any card issuer.
          </p>
        </div>
      </div>
    </div>
  )
}
