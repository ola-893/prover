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

In a fresh `zsh` session, load the key without echoing it or putting its value in shell history:

```sh
read -r -s "CREDITCOIN_PRIVATE_KEY?CC3 private key: "
print
export CREDITCOIN_PRIVATE_KEY
```

Run the deployment in that same session, then immediately run
`unset CREDITCOIN_PRIVATE_KEY`.

Rotate any credential that has been pasted into a chat or terminal transcript before a production
deployment. The current deployment is testnet-only.

## Pinned CC3 dependencies

- Chain ID: `102031`
- Native transaction verifier: `0x0000000000000000000000000000000000000FD2`
- Native ChainInfo: `0x0000000000000000000000000000000000000fD3`
- Canonical `EvmV1Decoder`: `0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f`
- Canonical decoder runtime code hash:
  `0xb549c9d8eaf7d361192f8e363fe98717464441e2dd26e2b3bd1e0725df73a065`

The script rejects the wrong CC3 chain or a changed decoder code hash. The canonical decoder must
also be linked explicitly:

```sh
forge script script/DeployCc3Mvp.s.sol:DeployCc3Mvp \
  --rpc-url "$CREDITCOIN_RPC_URL" \
  --chain-id 102031 \
  --libraries "src/attestcoin/EvmV1Decoder.sol:EvmV1Decoder:0x731c345d79Fb8BbDC541f9DF3b6317585F849F9f" \
  --broadcast --slow --non-interactive
```

Run from `contracts/`. Simulate first by omitting `--broadcast`. After broadcasting, verify the
deployed bytecode, ownership, native dependency addresses, and reporter masks against the chain
before publishing a deployment manifest.

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
