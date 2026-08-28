# Attestcoin Financial-Breach Proofability Matrix

This matrix audits the 54 actor classes in the supplied list against the current Attestcoin V1 evidence surface.

## Strict classification

- **A — directly provable:** A finite bundle of authenticated source-chain transactions and receipts positively contradicts an objective, pre-existing rule.
- **B — covenant-provable:** Raw history is insufficient, but the product can register an actor, obligation, trigger, source-height deadline, bond, and permitted completion evidence. If no acceptable proof arrives before the Creditcoin deadline, the *registered obligation* defaults. Attestcoin is not claimed to prove source-chain non-occurrence.
- **C — not provable by current Attestcoin:** The claim depends on arbitrary state, complete history/non-inclusion, private messages, consensus-layer data, continuous observation, wall-clock time, offchain facts, subjective truth, intent, or a counterfactual.

For the requested binary split, **A and B are product-buildable/provable financial breaches**. **C is not provable without another trust or proof system.**

## Mandatory preconditions for every A or B claim

1. The promise and actor identity were bound before the alleged breach.
2. Evidence comes from an Attestcoin-supported source chain and an allowlisted contract/ABI version.
3. The exact proof used to calculate transaction position is first authenticated by `verify`/`verifyAndEmit`.
4. The court checks `receiptStatus == 1` where a successful action is material.
5. Every evidence leg has a unique obligation, task, request, quote, deal, or position ID.
6. Deadlines use authenticated source block heights, or an allowlisted contract's own evaluated deadline result—not an assumed wall-clock timestamp.
7. The claimed breach is a deterministic predicate over authenticated fields and ordering.
8. Replay protection binds chain key, height, root/index, transaction bytes, policy ID, and evidence leg.

## Full actor matrix

| # | Actor | A — directly provable positive breaches | B — requires registered covenant/default machinery | C — not proved by current Attestcoin |
|---:|---|---|---|---|
| 1 | Validators | An onchain `Slashed`/offence result; two conflicting validator-signed messages if both are submitted to an EVM contract and individually attributable. | Forced-inclusion or validator-service duty registered with an objective response window. | Ethereum beacon uptime, participation, missed attestations, raw beacon equivocation, censorship, inclusion-policy compliance and intent. These are consensus/mempool facts, not EVM transaction receipts. |
| 2 | Restaking / AVS operators | Conflicting signed results; rejected response; slash event; submitted response after its due height; wrong task/version/price fields. | Task accepted but no result; heartbeat/response duty; challenge-response SLA. | Generic offchain uptime, subjective service quality or computation correctness without a deterministic verifier. |
| 3 | Oracle node operators | Conflicting attributable reports for one round; late *published* report; explicit rejection/slash; deviation from a separately authenticated, preselected reference feed. | Missing update, maximum-latency or deviation SLA with an objective reference/adjudicator. | “True” real-world price, manipulation intent, source diversity, methodology and general uptime. Aggregate reports may also hide individual node attribution. |
| 4 | Oracle data publishers | Same as #3 when publisher signatures, feed, round, price and confidence are onchain. | Missing report or confidence/deviation duty using a committed reference and timeout. | Offchain dashboard metrics, source methodology and accuracy against unknowable ground truth. |
| 5 | Sequencers | Ordering, adjacency, sandwich/bracketing and bounded reordering when the requests and executions themselves have authenticated canonical coordinates on a supported chain. | Forced-inclusion deadline or FIFO policy after an authenticated request. | Private-mempool arrival order, ordinary censorship, sequencer uptime, intent and vague “fair ordering.” Current Attestcoin does not generally expose L2 blob contents or L2 execution history. |
| 6 | Batchers / data submitters | Positively late batch publication; rejected/malformed submission where the canonical contract adjudicates it; conflicting batch IDs/commitments. | A batch that is never published; publication-response SLA. | Global data availability, blob retrievability/retention and deliberate withholding. Blob commitments are not blob contents. |
| 7 | State proposers | Conflicting proposals for one output index; positively late proposal; dispute-game invalidation or proposer slash. | No proposal ever posted. | Independently proving the proposed L2 state root invalid from V1 transaction/receipt data, or that the proposer acted knowingly. |
| 8 | Challengers | Late move; timeout; lost/rejected challenge; slash or canonical dispute result. | Failure to challenge or respond after an assigned duty. | Continuous monitoring, motive, “frivolousness” inferred only from losing, and maintained bond/state over an interval. |
| 9 | ZK provers | Rejected proof; accepted proof submitted after due height; charged amount above committed quote; wrong proof system/version. | Proof never delivered. | Offchain generation time when no result is submitted, generic availability and correctness without a deterministic verifier. |
| 10 | Data-availability operators | Late commitment publication; failed onchain sampling challenge; slash. | Random challenge-response duty or publication duty with timeout. | Global retrievability, continuous uptime, future retention and availability of every blob. Finite passing samples prove only those samples. |
| 11 | Bridge validators / guardians | Two conflicting signed messages for one nonce/domain; signed message whose token/amount/recipient differs from an authenticated source lock/burn; explicit invalid-message slash. | Non-signing duty, finality/quorum rule with a snapshotted signer set and objective adjudicator. | Private votes, signing time, missing signatures and individual blame when only an anonymous aggregate signature is posted. |
| 12 | Cross-chain message attesters | Equivocation or deterministic field mismatch between source event and attested message. | Response/finality covenant with objective checkpoints and attributable signers. | Generic finality-at-signing, private timing and attribution hidden by an aggregate signature. |
| 13 | Market makers | Accepted signed RFQ filled at worse price, wrong asset/amount or excessive committed slippage; early withdrawal of specifically locked liquidity. | Accepted quote followed by no fill; discrete quote-response SLA. | Continuous spread/depth, 99% quoting uptime, toxic-order discrimination, intent and millisecond last-look based only on source heights. |
| 14 | RFQ quoters | `Quote -> Accepted -> wrong/partial/late Fill`, or explicit `Refused/Defaulted`; quote nonce replay. | Accepted quote with no fill by deadline. | Quote or acceptance that never entered authenticated calldata/logs. |
| 15 | OTC counterparties | Wrong asset, amount or recipient; partial or positively late settlement; explicit default/slash, all tied to a precommitted deal ID. | Non-delivery or missed settlement under registered escrow/deal terms. | Purely legal/offchain settlement, collateral and margin facts. |
| 16 | Derivatives counterparties | Exercise followed by wrong/late payout; wrong periodic cashflow; canonical liquidation/default result. | Missed option, forward or swap payment. | Current margin/health, valuation and counterfactual payoff without authenticated state and price inputs. |
| 17 | Auction bidders | Bonded bid plus winner selection followed by underpayment, wrong settlement or explicit default/bond slash. | Selected bidder never settles. | Offchain bids or winner selection not committed onchain. |
| 18 | Designated liquidators | Objective job/eligibility trigger followed by a late, failed or below-minimum-output liquidation; timeout/slash event. | No liquidation after a registered trigger. | Independently deriving liquidation eligibility/health factor/current capital, vague participation during stress, or slippage versus an unstated market price. |
| 19 | Liquidation backstop providers | Early withdrawal of committed backstop capital; positively late or insufficient draw contribution; explicit shortfall/default. | Triggered draw that receives no contribution. | Continuous readiness/capacity or offchain capital. |
| 20 | Credit underwriters | Rating issued before funding followed by canonical repay/default/recovery outcomes; objective expected-versus-realized metrics for a complete registered cohort. | Monitoring and response duties with canonical triggers. | Proof that an internal methodology was actually followed, subjective rating correctness, offchain loss/recovery and counterfactual underwriting quality. |
| 21 | Pool delegates / credit managers | Funding an explicitly prohibited borrower/asset; executing a forbidden configuration; action before/after an authenticated timelock or impairment trigger. | Missed impairment; concentration/coverage covenant evaluated by a registered risk controller. | Raw current concentration, coverage ratio and collateralization from transaction proofs alone. |
| 22 | Guarantors | Guarantee called then paid late, short or to wrong beneficiary; explicit guarantee default. | Called guarantee with no payment. | Borrower default unless it is itself registered/canonically adjudicated; offchain honour/dishonour. |
| 23 | Surety / bond providers | Invoked claim followed by short/wrong/late payment; explicit surety default. | Invoked claim with no payment. | Offchain claim validity or dishonour. |
| 24 | Insurance / cover underwriters | Accepted objective claim followed by short, wrong or late payout; explicit payout default. | Accepted claim with no payout. | Capital adequacy/reserves and correctness of subjective exclusions or disputed real-world claims. |
| 25 | Claims assessors | Late assessment; double vote; no-show/default event; assessment later canonically overturned. | Assigned claim receives no assessment; deterministic policy-adjudication duty. | Whether a subjective claim was truly valid, fraudulent intent and offchain conflicts. An event proves the accepted adjudicator's verdict, not universal truth. |
| 26 | Arbitration jurors / dispute resolvers | Late vote; contradictory vote; canonical overturn history; slash. | Participation/no-show rates when assignments and epoch closure are complete and registered. | General correctness, fairness, intent and undisclosed conflicts of interest. |
| 27 | Custodians | Authenticated withdrawal completed late, short or to wrong destination; a transfer that positively violates a fixed authorization rule. | Accepted withdrawal never completed. | Asset segregation, non-rehypothecation, reserves, current reserve ratios and offchain custody facts. |
| 28 | Settlement providers | Onchain settlement completed late, short, wrong or out of order; early/incorrect delegation action. | Accepted settlement/delegation request never completed. | Offchain exchange PnL, exchange failure, internal ledger settlement and operational availability. |
| 29 | Centralized exchanges | Narrowly, an onchain withdrawal transfer after an authenticated onchain withdrawal obligation; wrong destination/amount. | CEX voluntarily registers withdrawal/settlement obligations and defaults on them. | Internal deposit crediting, trades, liquidations, liabilities, API uptime, request time and fiat settlement. Proof-of-reserve publication proves a claim was published, not reserves >= liabilities. |
| 30 | Escrow agents | Release/refund to wrong party or amount; release before/after authenticated condition; release during prohibited dispute state. | Failure to release/refund after an objective condition and deadline. | Offchain or subjective condition satisfaction/authorization. |
| 31 | Stablecoin issuers | Onchain redemption/burn followed by short, wrong or late payout in a specified onchain settlement asset. | Accepted onchain redemption never paid. | Fiat redemption, “$1” parity, bank reserves, KYC qualification, business-day timing and reserves >= supply. |
| 32 | Wrapped-asset issuers | Mint larger than a linked authenticated reserve deposit; reuse of one deposit ID for two mints; redemption burn followed by wrong/late onchain release. | Redemption burn with no release. | Mint “with no reserve,” global/current 1:1 backing, unsupported-chain reserves and offchain custodian assets. Absence of a deposit proof is not proof no deposit exists. |
| 33 | RWA issuers / originators | Onchain cashflow forwarded late/short; positively forbidden transfer/use to a fixed address; late/revised report publication. | Registered cashflow not forwarded; reporting obligation missed. | Underlying asset existence/eligibility, offchain use of proceeds, accurate NAV and maintained real-world collateral. |
| 34 | RWA servicers | Onchain collections/recoveries received by a canonical contract but remitted late/short; recovery distribution errors. | Received cashflow not remitted. | Bank collections, true delinquency, legal enforcement, borrower records and completeness of servicing. |
| 35 | NAV / valuation agents | Two publications for one epoch prove revision; publication after due height; deterministic deviation from a linked onchain realization/reference. | Missing report. | Accurate/fair NAV of offchain/current portfolios, methodology and 18:00 wall-clock compliance without a canonical evaluator. |
| 36 | Risk curators | Allocation/configuration to an unapproved protocol/asset; execution before an authenticated timelock; one action above an absolute cap. | Aggregate exposure, collateralization or oracle-risk covenant evaluated by a registered source risk controller. | Current portfolio percentages, aggregate exposure and oracle risk from selected transaction proofs alone. |
| 37 | Capital allocators | Allocation to a forbidden venue; one allocation above an absolute action cap; uniquely keyed rebalance performed late. | Aggregate allocation limits, liquidity buffer, diversification and missed rebalance via a mandate controller. | Broad prose strategy or continuous portfolio state without machine rules/checkpoints. |
| 38 | Fund / strategy managers | Positive trade/allocation into a forbidden asset or venue; late uniquely keyed rebalance. | Leverage cap, cash buffer and periodic strategy rules evaluated by a registered controller. | Broad mandate, current leverage/drawdown/cash state and subjective strategy compliance. |
| 39 | Treasury managers | Use of an unapproved token/protocol; transaction above an absolute cap. | Concentration, stable-liquidity and drawdown limits emitted by a portfolio/risk controller. | Current percentages, USD drawdown without an authenticated price engine and broad risk-budget compliance. |
| 40 | Multisig signers | Safe execution to forbidden target/selector/recipient; proposal-hash mismatch; positive set of proven spends whose lower-bound sum already exceeds a fixed cap; late response if it eventually appears. | Missing response/key challenge. | Legal/subjective authorization, key availability without challenges and undisclosed conflicts. |
| 41 | Security councils | Forbidden emergency selector/executor; governance/timelock bypass; invocation without required justification field; positively late action. | Missing emergency response or justification; objective emergency-condition evaluator. | Whether a subjective/offchain emergency truly existed and broad “never bypass governance.” |
| 42 | Governance delegates | Vote for an objectively prohibited inflation change; vote for transfer to self; vote contradicting a machine-readable proposal predicate. | Participation/no-show percentage with complete proposal assignments and epoch closure. | Broad prose mandate, vote rationale, undisclosed conflicts and non-votes inferred from selected proofs. |
| 43 | Bonded LPs | Decrease/burn/withdraw an identified committed position before expiry; initial provision below commitment. | Depth/liquidity-band checks performed by a position-owning covenant and accepted price oracle. | Genuine continuous depth, spread and quoting uptime from periodic transaction proofs. |
| 44 | Backers / first-loss providers | Funding below final committed amount; withdrawal/redeem before maturity. | Missed funding or post-loss first-loss deficit emitted by the pool controller. | Continuous sufficiency/current risk without a canonical controller. |
| 45 | Stability / insurance-pool providers | Premature withdrawal during an explicit lock. | Triggered loss not absorbed; committed capital insufficient, as adjudicated by the pool controller. | Continuous capacity from raw proof history. Ordinary unlocked depositors have made no future promise. |
| 46 | Payment processors | Settlement/refund completed late, short or to wrong beneficiary; excess fixed fee; conversion outside an accepted quote. | Settlement/refund never completed. | Offchain card acceptance, API uptime, banking completion and FX fairness without a committed reference quote. |
| 47 | Merchant acquirers | Onchain `Cleared -> Settled` late/short/wrong. | Onchain-cleared transaction never settled. | Traditional card/bank T+1 settlement without a trusted external attester. |
| 48 | Payroll providers | Wrong employee, token, amount, early or uniquely late payment against a frozen payroll manifest. | Omitted employee or wholly missing payroll, finalized by the payroll controller. | Employment validity, taxes and offchain payroll facts. A subset of payment proofs cannot show all employees were paid. |
| 49 | Subscription / payment-stream senders | Premature cancellation; wrong recipient/asset; positive underpayment; uniquely late installment. | Missing installment or underfunded stream finalized by escrow. | Offchain service performance underlying the subscription. |
| 50 | Vesting administrators | Early/accelerated unlock; unauthorized schedule mutation; overdistribution; wrong recipient/asset. | Required push distribution missed. | Offchain authorization unless represented by a canonical governance decision. Pull vesting may create no administrator payment duty. |
| 51 | Airdrop / distribution operators | Root change after freeze; payout inconsistent with committed allocation; overdistribution; wrong recipient/amount. | Omitted recipient or incomplete distribution finalized by the distribution controller. | Fairness of the original eligibility/allocation and vague “preferential treatment” without a fixed manifest. |
| 52 | Grant administrators / grantees | Authenticated milestone acceptance followed by wrong/late payout; payment to wrong beneficiary. | Accepted milestone not paid; deterministic milestone-verifier duty. | Actual quality/completion of offchain work without an accepted assessor/verifier. |
| 53 | Bounty issuers | Canonically accepted submission followed by wrong/late payout. | Accepted winner never paid. | Objective validity of subjective/offchain submission without an accepted adjudicator. |
| 54 | Onchain-paid service providers | Submitted result rejected by a deterministic verifier; wrong result/version; positively late delivery. | No result by deadline; canonical job expiry/slash. | Generic quality of auditing, development, storage, compute or other offchain services. A self-emitted completion event proves only the assertion. |

## Sorted result: strongest A-grade direct transaction-order breaches

These require only positive authenticated evidence and objective pre-existing terms:

1. **Order violations:** sandwich/bracketing, FIFO inversion, forbidden adjacency, premature execution and timelock bypass.
2. **Equivocation:** two conflicting oracle, bridge, AVS, proposer or attester messages tied to the same round/nonce/task.
3. **Wrong settlement:** RFQ, OTC, derivative, auction, escrow, guarantee, insurance, payroll, grant, bounty or payment with wrong amount/asset/recipient.
4. **Positive lateness:** a uniquely identified result, proposal, proof, batch, settlement or payment eventually appears after its source-height deadline.
5. **Rejected/invalid results:** canonical verifier, dispute game or policy contract attributes a rejection/slash to the actor.
6. **Forbidden actions:** multisig, council, curator, allocator, fund/treasury manager or delegate performs an explicitly prohibited transaction/vote.
7. **Premature capital removal:** bonded LP, first-loss provider, stability provider or vesting administrator withdraws/unlocks before expiry.
8. **Commitment reuse/over-issuance:** wrapped issuer reuses a deposit ID, mints too much, or distributor exceeds a frozen allocation.

The best actor classes from the supplied list for a current MVP are:

- Restaking/AVS operators
- Attributable oracle publishers
- Sequencing/order-policy operators on supported evidence
- ZK prover marketplaces
- Bridge guardians/message attesters
- RFQ/OTC/auction counterparties
- Guarantors/sureties/insurance payout providers
- Escrow and payment-settlement providers
- Multisigs/security councils/governance delegates
- Bonded LPs/first-loss providers
- Payroll/vesting/distribution/grant/bounty administrators

## Sorted result: strongest B-grade covenant-provable breaches

These are non-performance promises. They are buildable only through the product's obligation state machine:

```text
actor signs PromiseRegistered
    -> bond is locked
    -> authenticated Trigger/Acceptance occurs
    -> source-height / Creditcoin evidence window opens
    -> actor supplies valid Fulfilled/Exception proof
    -> otherwise Creditcoin records Defaulted and pays from bond
```

Good B-grade modules include:

- AVS task not completed
- Forced transaction never included
- Batch/state proposal/proof never published
- RFQ/OTC/derivative/auction settlement never delivered
- Designated liquidation/backstop response never performed
- Guarantee, surety or accepted insurance claim never paid
- Custody/settlement/redemption request never completed
- RWA cashflow never remitted
- Required report/rebalance/response never supplied
- Payroll/installment/vesting/distribution/grant/bounty payment omitted
- Service job never delivered

The breach here is **failure to satisfy a registered Creditcoin obligation with valid evidence by its deadline**. It is not “Attestcoin proved the source transaction never happened.”

## Sorted result: C-grade claims that are not provable

The following claims from the supplied list should be removed from the current product or explicitly routed to another proof/oracle system:

1. **Continuous uptime/availability:** validator participation, oracle uptime, sequencer uptime, market-maker quoting uptime, API availability and continuous data retention.
2. **Generic censorship/non-inclusion:** “the transaction was never included,” “the publisher never reported,” or “no conflicting transaction exists.”
3. **Private arrival order:** mempool order, offchain RFQ timing and private guardian votes.
4. **Arbitrary current state:** balances, health factors, reserve ratios, margin, code/storage, liquidity depth, portfolio exposure, leverage and cash buffers.
5. **Real-world accuracy:** true price, NAV accuracy, asset existence, collateral quality, use of proceeds, bank reserves, fiat settlement and business-day compliance.
6. **Global data availability:** retrievability or retention of every blob from a finite proof bundle.
7. **Subjective correctness:** good underwriting, valid claim, fair ruling, justified emergency, mandate quality, conflict of interest and service quality.
8. **Intent and counterfactuals:** manipulation intent, deliberate withholding, “would have executed at X,” or exact economic harm.
9. **Complete history:** “these are all of the actor's loans/votes/payments/violations.” Selected inclusion proofs establish a lower bound, not completeness.
10. **Unsupported-chain native behavior:** L2 execution, beacon-consensus duties or another chain's state unless the relevant evidence is committed into an Attestcoin-supported EVM transaction and deterministically decodable.

## Product conclusion

The supplied list contains many viable actors, but its “Easy / five-star” ratings are not reliable. The most defensible product scope is:

> **A court for positive contradictions plus a bonded obligation registry for non-performance.**

Attestcoin remains the evidence authenticator. The product must supply the missing promise semantics, actor identity, deadlines, allowed evidence, default machinery and economic settlement.
