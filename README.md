# Prover

**A cross-chain bureau of fulfilled and breached financial promises.** Prover turns authenticated
source-chain transactions into typed evidence, applies deterministic breach predicates, settles
bonded covenants, and publishes an explainable performance record on Creditcoin.

The MVP leads with two claims that transaction ordering can prove particularly well:

1. **Bonded no-sandwich execution.** A relay signs a route authorization and posts a forward-looking
   covenant. Three authenticated, adjacent swaps can prove a sandwich-shaped execution, settle a
   fixed CTC penalty, and record the ruling against the relay.
2. **FairExit FIFO enforcement.** A vault operator posts a FIFO covenant. Four authenticated events
   can prove that request A preceded request B while B was processed before A, settle the bond, and
   pay the earlier requester.

Two additional contract-tested modules extend the same evidence standard beyond ordering. Their
drafts are mutually authorized and only become promises after a future Creditcoin block hash makes
the final promise ID unavailable at registration:

3. **Bonded RFQ execution terms.** One exact `RFQExecuted` receipt event proves a matching outcome
   or classifies wrong beneficiary, asset, amount, recipient, short output, or positive lateness.
4. **Bonded settlement release.** One exact `SettlementReleased` receipt event proves a matching
   outcome or classifies wrong asset, recipient, short payment, or positive lateness.

Those two modules are locally tested and not deployed. Their current demo emitter records events but
does not transfer assets. The lifecycle now requires beneficiary EIP-712/EIP-1271 authorization and
a governance-approved source-policy revision, but the fixture source is still not an economically
trusted production adapter. RFQ and settlement outcomes therefore remain outside `PerformanceBureau`
until a reviewed source contract derives its events from real custody or execution and a native proof
has been demonstrated end to end.

The same record can also hold narrowly stated borrower evidence. The demonstration imports a public
Ethereum Aave V3 Borrow and later self-funded Repay, derives a **self-repayment observation**, and
shows a deliberately bounded experimental loan-term adjustment. It does not call that pair a closed
loan or a complete credit history.

## Why this is different

Most reputation products summarize wallet activity. Prover instead makes forward-looking promises
enforceable:

```text
operator covenant + CTC bond
            |
authenticated source transactions
            |
typed predicate (adjacency / FIFO inversion)
            |
court ruling -> pull payout -> append-only profile -> future terms
```

The profile stays as an evidence vector rather than collapsing different actors and failures into an
opaque score.

## MVP flow

The interactive demo at `app/` walks through:

1. two public Aave receipt facts and one derived self-repayment observation;
2. an experimental Creditcoin lender quote with every adjustment explained;
3. a relay's bonded no-sandwich covenant and an adjacent-order ruling;
4. a vault operator's bonded FIFO covenant and a completed-inversion ruling; and
5. updated limits, premiums, and future bond requirements for each actor.

The browser fixtures are clearly labeled. A fixture is not presented as a live Attestcoin verdict.

## Contracts

| Contract | Responsibility |
| --- | --- |
| `AttestcoinProofAdapter` | Calls the native verifier and recovers authenticated source positions from Merkle-path laterality. |
| `OrderingCourt` | Applies policy-bound sandwich and FIFO predicates, persists rulings, and asks the bond book to settle them. |
| `CovenantBook` | Holds immutable native-CTC bonds, enforces future coverage windows, and credits pull payments. |
| `PerformanceBureau` | Stores reporter-scoped, replay-safe evidence records and per-address evidence vectors. |
| `AaveEvidenceAdapter` | Decodes exact Aave V3 USDC Borrow/Repay receipt ordinals and derives a narrow self-repayment observation; its production subclass pins the native verifier. |
| `PolicyV1` | Produces transparent experimental terms from the evidence vector. |
| `DemoLender` | Freezes a quoted policy result into a demonstrative Creditcoin loan offer. |
| `DemoExitVault` | Emits the unique, non-cancellable request/process schema required by the FairExit policy. |
| `PromiseSourceRegistry` | Governance-approves exact promise kind, source chain, emitter and immutable policy tuples; every status change advances a revision. |
| `PromiseBook` | Registers mutually authorized funded drafts, derives prospective promise IDs from future CC3 block hashes, enforces evidence windows, resolves outcomes, and credits pull payments. |
| `PromiseCourt` | Authenticates one exact RFQ or settlement receipt event, requires its policy ID, and deterministically classifies matching, wrong, short, or late outcomes. |
| `DemoPromiseSource` | Fixture-only event emitter with actor-scoped terminal-event uniqueness; it does not custody or transfer assets. |

Production proof verification is pinned to Creditcoin's native verifier at `0x…0FD2`; covenant
height checks use ChainInfo at `0x…0FD3`. The production ordering deployer pins both addresses. The
vendored EVM decoder requires the canonical CC3 library at
`0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` when deploying linked production bytecode.

## Live CC3 testnet deployment

The court infrastructure is deployed on Creditcoin CC3 testnet (chain ID `102031`):

| Contract | Address |
| --- | --- |
| Ordering Court | [`0xc01f7E27D4D712241B1cAAD972E0FC589146c5Ff`](https://creditcoin-testnet.blockscout.com/address/0xc01f7E27D4D712241B1cAAD972E0FC589146c5Ff) |
| Covenant Book | [`0x66aF3e9Ad07A236b29de7ad07083C037a4244223`](https://creditcoin-testnet.blockscout.com/address/0x66aF3e9Ad07A236b29de7ad07083C037a4244223) |
| Performance Bureau | [`0x8Ef418F6E740950cAd8C4fa22A4F7B7990B00D74`](https://creditcoin-testnet.blockscout.com/address/0x8Ef418F6E740950cAd8C4fa22A4F7B7990B00D74) |
| Native Aave Evidence Adapter | [`0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4`](https://creditcoin-testnet.blockscout.com/address/0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4) |
| Demo Lender | [`0xb6A6858C7BBb755c2AD014d07583369278078F71`](https://creditcoin-testnet.blockscout.com/address/0xb6A6858C7BBb755c2AD014d07583369278078F71) |

The sanitized [deployment manifest](./contracts/deployments/cc3-testnet.json) records transaction
hashes, runtime code hashes, child wiring, dependency addresses and reporter masks. Deployment proves
the infrastructure is live; it does not turn browser fixtures into live Attestcoin verdicts. The
keyless preflight below now fetches real proof-builder payloads and passes them through the deployed
native verifier with `eth_call`; persisting those facts is a separate state-changing transaction.

`PromiseBook`, `PromiseCourt`, and `DemoPromiseSource` are not part of this live deployment table.
They currently pass the local contract suite using authenticated-proof mocks; no native RFQ or
settlement proof has been submitted and no live outcome has been recorded for them.

## Exactly what the predicates establish

### No-sandwich ruling

The court requires:

- three transactions authenticated under one source block and one Merkle root;
- exact transaction-index adjacency: front-run, victim, back-run;
- successful receipts with one exact Uniswap V2-style Swap event from the policy-bound pool;
- the same outer sender for the two searcher legs and a distinct victim sender;
- a victim call to the policy-bound entrypoint;
- an operator-authorized route digest bound to the court, covenant, source chain, victim, nonce,
  destination, native value, calldata hash, and expiry; and
- a conserved counter-asset round trip with positive **gross** numeraire output.

It does not prove net profit after gas or every possible multi-pool MEV strategy.

### FairExit FIFO ruling

The court requires four positive facts in fixed roles: request A, request B, process B, process A. It
checks request IDs and owners, authenticates the global order, binds both processing transactions to
the policy signer, and supports cross-block ordering. The policy commits to a vault implementation
with unique, non-cancellable request IDs and single processing.

This proves a **completed inversion** for that policy-bound schema. It is not a generic proof of an
arbitrary vault's pending state.

### Aave observation

The adapter authenticates successful Ethereum-mainnet Aave V3 Pool receipt logs at an exact ordinal.
It attributes Borrow to `onBehalfOf` and Repay to `user`, then permits a derived observation only when
the subject, USDC reserve, ordering, minimum 32-block gap, self-repayer, and same-or-larger amount all
match.

Aave debt is aggregate and Repay does not identify the Borrow or its interest-rate mode. Therefore the
observation does **not** prove a linked loan, full repayment, current balance, timeliness, liquidation
absence, or complete history. A zero imported-liquidation count always means coverage is unknown.

### RFQ and settlement outcome modules

An RFQ or settlement obligation now has a two-stage prospective lifecycle:

1. The beneficiary signs nested EIP-712 `PromiseSource` and `PromiseSchedule` data. Every actor,
   beneficiary, source, policy revision, terms commitment, timing field, penalty, bond and unordered
   beneficiary nonce is covered. Deployed smart wallets are supported through EIP-1271.
2. Governance must have approved the exact `(kind, sourceChainKey, sourceContract, policyId)` tuple.
   A pending draft snapshots that approval revision; revocation or revoke/reapprove neutrally unwinds
   the draft and refunds its bond. An active promise never consults mutable registry state again.
3. The signed anchor is 2–64 Creditcoin blocks in the future. Anyone may activate from two
   confirmations after that block through its signed deadline, never later than the 256-block
   `BLOCKHASH` retention boundary.
4. Activation derives the source-height windows from the latest attested tip and incorporates the
   future block hash, activation attestation and draft commitment into the final promise ID. A source
   terminal event must embed that final ID, so an ordinary actor cannot prepare it before draft
   registration.
5. Only activated promises affect actor statistics. An expired pending draft is a neutral refund,
   not a breach or proof-submission default.

Both paths first authenticate the exact V1 transaction and receipt bytes. The selected log must have
the committed source chain, emitter, event signature, promise ID, reference ID, actor, topic count,
data length, and successful receipt status. A mismatch in those relevance fields rejects the proof;
it does not slash the actor. Only after relevance is established does the court classify wrong,
short, or late event fields as a breach.

The terms commit to actor-scoped unique terminal events. Duplicate relevant events in one receipt are
rejected, while cross-transaction uniqueness remains a source-emitter trust assumption. A production
bureau reporter must therefore pin an audited adapter that enforces this invariant and derives event
values from real custody or execution rather than caller-supplied claims.

The generic proof-submission default is narrower: it says no acceptable fulfillment proof reached
`PromiseBook` before the evidence window closed. It does not prove that no fulfillment transaction
existed on the source chain.

The future block hash is an unpredictability salt, not unbiased randomness or a universal clock. A
Creditcoin block producer may influence or learn it early, and the source event can be emitted after
the anchor is known but before the permissionless activation transaction is mined. The construction
proves that the event could not contain the final ID before the accepted draft and its future anchor;
it does not prove exact cross-chain wall-clock ordering. A later source-side activation event would
provide the stronger handshake.

## Public Aave proof candidate

The unit suite pins a real public receipt pair for wallet
`0x5D99551ce4a2c1467aDF632474424E7e22c72C66`:

| Event | Transaction | Block | Tx index | Receipt log ordinal | Raw USDC amount |
| --- | --- | ---: | ---: | ---: | ---: |
| Borrow | `0xbcacb57223f15070dec270cede4eed03deb60ecb117d35d8fe518a66d1c590ff` | 25,854,707 | 201 | 4 | 90,000,000,000 |
| Repay | `0x84ea8dcff1eedb9973b8cc950d497f271e56c1d80e172187710721bfd02ba344` | 25,854,747 | 120 | 4 | 90,000,055,729 |

The unit test reconstructs those event facts behind a mock verifier to test decoding and policy logic.
The preflight below fetches fresh canonical EVM-V1 transaction bytes, Merkle paths, and Attestcoin
continuity proofs for both blocks. A durable bureau record still requires a mined CC3 transaction.

## Reproduce the live Aave proof preflight

From the repository root, run:

```bash
node scripts/verify-live-aave.mjs
```

The command uses only public endpoints. It checks proof-builder health, waits for an attested height
past the source transactions, fetches both proofs by transaction hash, validates every proof field,
independently recovers each transaction index from Merkle laterality, and submits the exact Solidity
tuples to the deployed adapter through read-only `eth_call` simulations. It prints the two predicted
fact IDs together with `"persisted": false`.

No private key, API key, Ethereum RPC key, Pinata credential or AI service is involved. Node.js 22+
and Foundry's `cast` are required. Public endpoint overrides may be supplied with
`CREDITCOIN_PROOF_BUILDER_URL`, `CREDITCOIN_RPC_URL`, and `AAVE_ADAPTER_ADDRESS`.

The current live preflight returns:

- Borrow fact `0xf6e62563f3caf5066b95731a45f3fdea394982ad96af0feee603eadca1d0e660`;
- Repay fact `0x9feb2581ac40f5b799acbd834e77a624e6bffa4634bc8a437f381bacf3d31483`.

Those IDs are predictions until the calls are broadcast and mined. A fresh funded CC3 submitter can
persist them because ingestion is permissionless; the testnet administrator key is not required.

## Local development

Requirements: Node.js 22+, npm, and Foundry.

```bash
# Frontend
cd app
npm ci
npm run dev

# Contracts (in another terminal)
cd contracts
forge test
```

Validation used by CI:

```bash
cd contracts
forge fmt --check
forge test
forge build --sizes --skip script

cd ../app
npx oxlint app/page.tsx components/performance-demo.tsx lib/demo.ts app/layout.tsx
npx tsc --noEmit
npm run build

cd ..
node --test scripts/verify-live-aave.test.mjs
```

## Security boundaries

- Covenants cannot be edited, shortened, or cancelled after opening.
- RFQ and settlement drafts require exact beneficiary authorization, exact bond funding and an
  approved source-policy revision. Unordered nonces prevent signature replay across concurrent deals;
  EIP-712 domain separation prevents replay across books or settlement chains.
- Activated RFQ and settlement coverage begins at least 64 blocks beyond the activation-time attested
  tip. Their final ID includes a signed future CC3 anchor, preventing ordinary pre-registration event
  backfill while stopping short of claiming exact cross-chain wall-clock ordering.
- Registry changes invalidate pending drafts and permit a full neutral refund. They cannot rewrite or
  strand already active promises.
- Ruling replay is blocked in both the court and bond book.
- Payouts use pull accounting. A revoked bureau permission cannot roll back an already settled bond.
- Reporter permissions are scoped by evidence kind.
- The demonstration's `1 CTC = 1 USDC` conversion is an explicit fixture, not an oracle claim.
- Raw `PromiseBook.actorStats` are mutually authorized ledger statistics but are not automatically
  bureau-grade. Do not use them for credit terms until governance approves an economically sound,
  immutable source adapter and the native proof path is demonstrated.
- Contracts have not been independently audited. Use them as hackathon software, not production
  financial infrastructure.

For the longer proofability analysis, see [ATTESTCOIN_BREACH_PROOFABILITY.md](./ATTESTCOIN_BREACH_PROOFABILITY.md).

## License and attribution

Prover is MIT-licensed. Required third-party notices are preserved beside the Attestcoin adapter:

- `contracts/src/attestcoin/EDY_CU_MIT_NOTICE.md` credits Edy Cu for adapted verifier-interface and
  deterministic laterality-test portions.
- `contracts/src/attestcoin/GLUWA_USC_CONTRACTS_NOTICE.md` covers the vendored Gluwa EVM-V1 decoder.
