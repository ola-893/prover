# Prover

**A cross-chain performance court for DeFi promises.** Prover turns authenticated source-chain
transactions into typed evidence, applies deterministic breach predicates, settles bonded
covenants, and publishes an explainable performance record on Creditcoin.

The MVP leads with two claims that transaction ordering can prove particularly well:

1. **Bonded no-sandwich execution.** A relay signs a route authorization and posts a forward-looking
   covenant. Three authenticated, adjacent swaps can prove a sandwich-shaped execution, settle a
   fixed CTC penalty, and record the ruling against the relay.
2. **FairExit FIFO enforcement.** A vault operator posts a FIFO covenant. Four authenticated events
   can prove that request A preceded request B while B was processed before A, settle the bond, and
   pay the earlier requester.

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

Production proof verification is pinned to Creditcoin's native verifier at `0x…0FD2`; covenant
height checks use ChainInfo at `0x…0FD3`. The production ordering deployer pins both addresses. The
vendored EVM decoder requires the canonical CC3 library at
`0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f` when deploying linked production bytecode.

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

## Public Aave proof candidate

The unit suite pins a real public receipt pair for wallet
`0x5D99551ce4a2c1467aDF632474424E7e22c72C66`:

| Event | Transaction | Block | Tx index | Receipt log ordinal | Raw USDC amount |
| --- | --- | ---: | ---: | ---: | ---: |
| Borrow | `0xbcacb57223f15070dec270cede4eed03deb60ecb117d35d8fe518a66d1c590ff` | 25,854,707 | 201 | 4 | 90,000,000,000 |
| Repay | `0x84ea8dcff1eedb9973b8cc950d497f271e56c1d80e172187710721bfd02ba344` | 25,854,747 | 120 | 4 | 90,000,055,729 |

The unit test reconstructs those event facts behind a mock verifier to test decoding and policy logic.
A live verdict still requires fresh canonical EVM-V1 transaction bytes, Merkle paths, and Attestcoin
continuity proofs for both blocks.

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
forge build --sizes

cd ../app
npx oxlint app/page.tsx components/performance-demo.tsx lib/demo.ts app/layout.tsx
npx tsc --noEmit
npm run build
```

## Security boundaries

- Covenants cannot be edited, shortened, or cancelled after opening.
- Coverage must begin at least 64 blocks beyond the latest attested tip; clients must also choose a
  height beyond the live source head because attestations may lag.
- Ruling replay is blocked in both the court and bond book.
- Payouts use pull accounting. A revoked bureau permission cannot roll back an already settled bond.
- Reporter permissions are scoped by evidence kind.
- The demonstration's `1 CTC = 1 USDC` conversion is an explicit fixture, not an oracle claim.
- Contracts have not been independently audited. Use them as hackathon software, not production
  financial infrastructure.

For the longer proofability analysis, see [ATTESTCOIN_BREACH_PROOFABILITY.md](./ATTESTCOIN_BREACH_PROOFABILITY.md).

## License and attribution

Prover is MIT-licensed. Required third-party notices are preserved beside the Attestcoin adapter:

- `contracts/src/attestcoin/EDY_CU_MIT_NOTICE.md` credits Edy Cu for adapted verifier-interface and
  deterministic laterality-test portions.
- `contracts/src/attestcoin/GLUWA_USC_CONTRACTS_NOTICE.md` covers the vendored Gluwa EVM-V1 decoder.
