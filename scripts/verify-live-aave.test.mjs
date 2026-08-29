import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AAVE_FACTS,
  DEFAULT_AAVE_ADAPTER,
  calculateTxIndexFromLaterality,
  parseOptions,
  toCastArguments,
  validateProof,
} from './verify-live-aave.mjs';

const hash = (byte) => `0x${byte.repeat(64)}`;

function validProof() {
  const siblings = Array.from({ length: 10 }, (_, depth) => ({
    hash: hash('b'),
    isLeft: (AAVE_FACTS[0].expectedTxIndex & (1 << depth)) !== 0,
  }));
  return {
    chainKey: 3,
    headerNumber: AAVE_FACTS[0].expectedBlock,
    txIndex: AAVE_FACTS[0].expectedTxIndex,
    txHash: AAVE_FACTS[0].txHash,
    txBytes: '0x1234',
    merkleProof: {
      root: hash('a'),
      siblings,
    },
    continuityProof: {
      lowerEndpointDigest: hash('c'),
      roots: [hash('d')],
    },
  };
}

test('validates and serializes a proof for the Solidity tuple ABI', () => {
  const proof = validateProof(validProof(), AAVE_FACTS[0]);
  const args = toCastArguments(proof);

  assert.equal(args.context, `(3,25854707,${hash('c')},[${hash('d')}])`);
  assert.equal(
    args.inclusion,
    `(0x1234,${hash('a')},[${proof.merkleProof.siblings
      .map((sibling) => `(${sibling.hash},${sibling.isLeft})`)
      .join(',')}])`,
  );
});

test('decodes leaf-to-root laterality as least-significant-bit first', () => {
  assert.equal(
    calculateTxIndexFromLaterality([
      { isLeft: true },
      { isLeft: false },
      { isLeft: true },
    ]),
    5,
  );
});

test('rejects a proof whose transaction index does not match the public receipt', () => {
  const proof = validProof();
  proof.txIndex += 1;

  assert.throws(
    () => validateProof(proof, AAVE_FACTS[0]),
    /returned transaction index/,
  );
});

test('reads only public endpoint overrides and never requires a private key', () => {
  const options = parseOptions([], {
    CREDITCOIN_RPC_URL: 'https://rpc.example',
    CREDITCOIN_PROOF_BUILDER_URL: 'https://proof.example',
  });

  assert.deepEqual(options, {
    proofBuilderUrl: 'https://proof.example',
    rpcUrl: 'https://rpc.example',
    adapter: DEFAULT_AAVE_ADAPTER,
  });
});

test('rejects unknown command-line arguments', () => {
  assert.throws(
    () => parseOptions(['--submit']),
    /unknown or incomplete argument/,
  );
});
