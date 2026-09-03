# CC3 testnet deployment

The production MVP is split across two networks:

- `PerformanceBureau`, both bonded court systems, the native Aave adapter, `PromiseBook`,
  `PromiseSourceRegistry`, `DemoLender`, and the standalone `BureauEvidenceSBT` deploy to Creditcoin
  CC3.
- `DemoExitVault` and `DemoPromiseSource` are source fixtures and must deploy separately to an
  Attestcoin-supported Ethereum network. Deploying either to CC3 would not create valid
  Ethereum-source evidence.

## Security boundary

Never put a private key in a command argument, committed file, deployment manifest, or shell
history. `DeployCc3Mvp.s.sol` reads `CREDITCOIN_PRIVATE_KEY` from the current process environment.
The committed `.env.example` contains names and public endpoints only.

Prefer Foundry's `--interactive` signer prompt for direct deployments. It reads the key without
putting the value in the command line, environment, repository or shell history.

Rotate any credential that has been pasted into a chat or terminal transcript before a production
deployment. The current deployment is testnet-only.

## Pinned CC3 dependencies

- Chain ID: `102031`
- Native transaction verifier: `0x0000000000000000000000000000000000000FD2`
- Native ChainInfo: `0x0000000000000000000000000000000000000fD3`
- Canonical `EvmV1Decoder`: `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f`
- Canonical decoder runtime code hash:
  `0xb549c9d8eaf7d361192f8e363fe98717464441e2dd26e2b3bd1e0725df73a065`

`DeployCc3Mvp.s.sol` is the declarative deployment and wiring specification for the original bureau,
ordering, Aave, and lender path. The promise system follows the separate direct workflow below. The
script rejects the wrong chain or a changed decoder code hash. Creditcoin's raw CC3 HTTP response currently omits the
`mixHash`/`prevRandao` field that Foundry 1.5 expects when building a fork, so `forge script` stops at
header validation against that endpoint before broadcasting. Until the RPC normalizes that header,
use direct `forge create`/`cast send` calls; they estimate and submit transactions without creating a
fork.

Set only public shell variables:

```sh
RPC=https://rpc.cc3-testnet.creditcoin.network
DECODER=0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f
```

Deploy the bureau and copy its public address from Foundry's output:

```sh
forge create --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/PerformanceBureau.sol:PerformanceBureau

BUREAU=<deployed PerformanceBureau address>
```

Deploy the linked court system and native Aave adapter. `--constructor-args` is deliberately last
because it consumes every remaining command argument:

```sh
forge create --libraries "src/attestcoin/EvmV1Decoder.sol:EvmV1Decoder:$DECODER" \
  --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/NativeOrderingCourtDeployer.sol:NativeOrderingCourtDeployer \
  --constructor-args "$BUREAU"

forge create --libraries "src/attestcoin/EvmV1Decoder.sol:EvmV1Decoder:$DECODER" \
  --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/AaveEvidenceAdapter.sol:NativeAaveEvidenceAdapter \
  --constructor-args "$BUREAU"

forge create --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/DemoLender.sol:DemoLender --constructor-args "$BUREAU"
```

Deploy the atomic promise system with the same canonical decoder. The constructor deploys and
permanently wires `PromiseSourceRegistry`, `PromiseBook`, and `PromiseCourt`; its only argument is the
registry governor:

```sh
GOVERNOR=<public testnet governor address>

forge create --libraries "src/attestcoin/EvmV1Decoder.sol:EvmV1Decoder:$DECODER" \
  --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/NativePromiseCourtDeployer.sol:NativePromiseCourtDeployer \
  --constructor-args "$GOVERNOR"
```

Read `SOURCE_REGISTRY()`, `PROMISE_BOOK()`, and `PROMISE_COURT()` from the system deployer. Do not
approve a source emitter merely because it exists on CC3: the emitter must be on the source network
identified by the Attestcoin chain key.

For the test-only fixture, deploy `DemoPromiseSource` to Sepolia, which CC3 identifies as chain key
`1`, then approve only its two exact immutable policy tuples:

```sh
SOURCE_RPC=<Sepolia RPC URL>

forge create --rpc-url "$SOURCE_RPC" --chain 11155111 --interactive --broadcast \
  src/DemoPromiseSource.sol:DemoPromiseSource

SOURCE=<deployed Sepolia DemoPromiseSource address>
REGISTRY=<deployed CC3 PromiseSourceRegistry address>
RFQ_POLICY_ID=$(cast keccak 'PROVER_PROMISE_RFQ_EXECUTED_V1')
SETTLEMENT_POLICY_ID=$(cast keccak 'PROVER_PROMISE_SETTLEMENT_RELEASED_V1')

cast send --rpc-url "$RPC" --chain 102031 --interactive "$REGISTRY" \
  'setSourceApproval(uint8,uint64,address,bytes32,bool)' 0 1 "$SOURCE" "$RFQ_POLICY_ID" true

cast send --rpc-url "$RPC" --chain 102031 --interactive "$REGISTRY" \
  'setSourceApproval(uint8,uint64,address,bytes32,bool)' 1 1 "$SOURCE" "$SETTLEMENT_POLICY_ID" true
```

`DemoPromiseSource` enforces actor-scoped event uniqueness but does not custody or transfer assets.
Its approval is suitable only for the clearly labeled hackathon fixture. A production approval must
target a reviewed adapter whose events are derived from real execution or custody.

Read `COVENANT_BOOK()` and `ORDERING_COURT()` from the system deployer, then grant exactly the two
least-privilege masks:

```sh
cast send --rpc-url "$RPC" --chain 102031 --interactive "$BUREAU" \
  'setReporterPermissions(address,uint256)' "$ORDERING_COURT" 48

cast send --rpc-url "$RPC" --chain 102031 --interactive "$BUREAU" \
  'setReporterPermissions(address,uint256)' "$AAVE_ADAPTER" 7
```

## Standalone ERC-5192 evidence receipt

The final adminless portability layer is deployed independently of the original system:

| Field | Value |
| --- | --- |
| Contract | `BureauEvidenceSBT` |
| Address | `0x59e4aba6868f475D572E0c491d92223F4141D442` |
| Deployment transaction | `0xc4b99c99dedeed78d981fce68d049920cb37e98c3b0e60ae7dcaf4b9d7ca5563` |
| CC3 block | `5,413,260` |
| Deployer nonce | `84` |
| Runtime size | `19,874` bytes |
| Runtime code hash | `0xae4fdd37bcd07512be84ca16cdebfeecae3b1456482d2cfe0eb3b8901e8adea3` |

Its constructor pins the deployed Bureau, Ordering Court, the Court's Covenant Book, and the native
Aave adapter. It checks that both reporters point back to the same canonical Bureau. Deployment is a
single new-contract creation: it does not upgrade, authorize, reconfigure, or write to any existing
contract, and the receipt contract has no owner or administrator.

`mintFromEvidence(bytes32)` is permissionless, but issuance is not. A successful mint requires a
terminal evidence ID already recorded in `PerformanceBureau` and exact agreement with its fixed
originating reporter records. The contract cannot create evidence, verdicts, payouts, permissions,
or profile changes. It supports only:

- a bounded Aave self-repayment observation, minted to its proven subject;
- a sandwich-breach ruling, minted to the proof-derived affected user; and
- a FIFO-breach ruling, minted to the proof-derived affected user.

For breach receipts the operator remains the metadata subject, while claimant is explicitly the
proof-derived affected user—not necessarily the proof submitter or payout beneficiary. Raw Aave
facts and all RFQ/settlement Promise outcomes are rejected. Ordering source transaction indices and
hashes remain `null` because the already-deployed court did not retain those constituent fields;
the SBT does not invent them.

The source includes `DeployCc3EvidenceSbt.s.sol` as a chain- and code-hash-pinned deployment
specification. For a key-safe manual deployment from `contracts/`, use Foundry's interactive signer
instead of placing a secret in the command or repository:

```sh
BUREAU=0x8Ef418F6E740950cAd8C4fa22A4F7B7990B00D74
ORDERING_COURT=0xc01f7E27D4D712241B1cAAD972E0FC589146c5Ff
AAVE_ADAPTER=0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4

forge create --rpc-url "$RPC" --chain 102031 --interactive --broadcast \
  src/BureauEvidenceSBT.sol:BureauEvidenceSBT \
  --constructor-args "$BUREAU" "$ORDERING_COURT" "$AAVE_ADAPTER"
```

Verify the final deployment with read-only calls:

```sh
EVIDENCE_SBT=0x59e4aba6868f475D572E0c491d92223F4141D442

cast codesize "$EVIDENCE_SBT" --rpc-url "$RPC"
cast codehash "$EVIDENCE_SBT" --rpc-url "$RPC"
cast call "$EVIDENCE_SBT" 'PERFORMANCE_BUREAU()(address)' --rpc-url "$RPC"
cast call "$EVIDENCE_SBT" 'ORDERING_COURT()(address)' --rpc-url "$RPC"
cast call "$EVIDENCE_SBT" 'AAVE_ADAPTER()(address)' --rpc-url "$RPC"
cast call "$EVIDENCE_SBT" 'COVENANT_BOOK()(address)' --rpc-url "$RPC"
cast call "$EVIDENCE_SBT" 'supportsInterface(bytes4)(bool)' 0xb45a3c0e --rpc-url "$RPC"
```

Expected results are the three fixed reporter/Bureau addresses above, Covenant Book
`0x66aF3e9Ad07A236b29de7ad07083C037a4244223`, ERC-5192 support `true`, runtime size `19874`, and the
published runtime hash. To mint an eligible record, first confirm it exists, then use any funded CC3
account; the token recipient is derived from canonical evidence rather than the transaction sender:

```sh
EVIDENCE_ID=<already-recorded terminal Bureau evidence ID>

cast call "$BUREAU" 'evidenceRecorded(bytes32)(bool)' "$EVIDENCE_ID" --rpc-url "$RPC"
cast send --rpc-url "$RPC" --chain 102031 --interactive "$EVIDENCE_SBT" \
  'mintFromEvidence(bytes32)' "$EVIDENCE_ID"
```

Run from `contracts/`. Dry-run each `forge create` first by supplying `--from` with the public
deployer address and omitting `--broadcast`. After broadcasting, verify the deployed bytecode,
ownership, native dependency addresses, and reporter masks before publishing a manifest.

## Testnet authority

The broadcasting account remains owner of `PerformanceBureau` and `DemoLender` and governor of
`PromiseSourceRegistry` for the hackathon testnet deployment. It can change reporter permissions,
approve or revoke exact source-policy tuples, and issue demo offers. This is visible, intentional
testnet administration—not proof-derived authority and not a production governance design. A
production release must transfer authority to explicit governance or irreversibly freeze the
approved reporter and source-policy sets.

## Required post-broadcast checks

Use read-only RPC calls to confirm all of the following before publishing addresses:

1. Every manifest address has non-empty runtime bytecode.
2. `PerformanceBureau.owner()` and `DemoLender.owner()` equal the disclosed testnet administrator.
3. Both system deployers' child getters equal every published book, court, and registry address.
4. `OrderingCourt.VERIFIER()` equals `0x…0FD2`, and `CovenantBook.CHAIN_INFO()` equals `0x…0FD3`.
5. `PromiseCourt.VERIFIER()` equals `0x…0FD2`; `PromiseBook.CHAIN_INFO()` equals `0x…0FD3`; and the
   book, court, registry, and deployer point back to the published immutable wiring.
6. The registry governor is the disclosed testnet administrator, and each approved fixture tuple has
   exactly revision `1` and no broader emitter approval.
7. The bureau's court reporter mask is exactly `48`; the Aave adapter mask is exactly `7`.
8. The canonical decoder still has the pinned runtime code hash above.
9. A captured Attestcoin proof succeeds in a separate integration smoke test. Contract deployment
   alone is not evidence that the external proof builder produced a valid proof.
10. `BureauEvidenceSBT` has the published runtime size and code hash, points to the published Bureau,
    Ordering Court, Covenant Book, and Aave adapter, and reports ERC-5192 interface support.

## Keyless live-proof preflight

The repository includes a read-only integration smoke test for the two public Aave receipts. Run it
from the repository root after deployment:

```sh
node scripts/verify-live-aave.mjs
```

It requests fresh proofs from the public proof builder, verifies that Ethereum is attested through at
least the source block plus one, derives each transaction index from sibling laterality, and calls the
deployed `NativeAaveEvidenceAdapter` through `eth_call`. A successful result proves that the hosted
payload reaches the live native verifier and the adapter decoder without reverting. It does not
persist evidence or emit a durable verdict.

The preflight deliberately has no broadcast mode and never reads a private key. When the facts are
ready to be persisted, use a fresh funded CC3 submitter with a hidden interactive prompt or encrypted
keystore. `ingestAaveFact` is permissionless, so the bureau administrator is not required.
