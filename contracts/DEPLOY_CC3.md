# CC3 testnet deployment

The production MVP is split across two networks:

- `PerformanceBureau`, the bonded covenant/court system, the native Aave adapter, and
  `DemoLender` deploy to Creditcoin CC3.
- `DemoExitVault` is a source fixture and must deploy separately to an
  Attestcoin-supported Ethereum network. Deploying it to CC3 would not create valid
  Ethereum-source evidence for the FairExit path.

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

`DeployCc3Mvp.s.sol` is the declarative deployment and wiring specification. It rejects the wrong
chain or a changed decoder code hash. Creditcoin's raw CC3 HTTP response currently omits the
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

Read `COVENANT_BOOK()` and `ORDERING_COURT()` from the system deployer, then grant exactly the two
least-privilege masks:

```sh
cast send --rpc-url "$RPC" --chain 102031 --interactive "$BUREAU" \
  'setReporterPermissions(address,uint256)' "$ORDERING_COURT" 48

cast send --rpc-url "$RPC" --chain 102031 --interactive "$BUREAU" \
  'setReporterPermissions(address,uint256)' "$AAVE_ADAPTER" 7
```

Run from `contracts/`. Dry-run each `forge create` first by supplying `--from` with the public
deployer address and omitting `--broadcast`. After broadcasting, verify the deployed bytecode,
ownership, native dependency addresses, and reporter masks before publishing a manifest.

## Testnet authority

The broadcasting account remains owner of `PerformanceBureau` and `DemoLender` for the hackathon
testnet deployment. It can change reporter permissions and issue demo offers. This is visible,
intentional testnet administration—not proof-derived authority and not a production governance
design. A production release must transfer ownership to explicit governance or irreversibly freeze
the approved reporter set.

## Required post-broadcast checks

Use read-only RPC calls to confirm all of the following before publishing addresses:

1. Every manifest address has non-empty runtime bytecode.
2. `PerformanceBureau.owner()` and `DemoLender.owner()` equal the disclosed testnet administrator.
3. The system deployer's child getters equal the published covenant-book and court addresses.
4. `OrderingCourt.VERIFIER()` equals `0x…0FD2`, and `CovenantBook.CHAIN_INFO()` equals `0x…0FD3`.
5. The bureau's court reporter mask is exactly `48`; the Aave adapter mask is exactly `7`.
6. The canonical decoder still has the pinned runtime code hash above.
7. A captured Attestcoin proof succeeds in a separate integration smoke test. Contract deployment
   alone is not evidence that the external proof builder produced a valid proof.

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
