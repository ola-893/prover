#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export const CHAIN_KEY = 3;
export const DEFAULT_PROOF_BUILDER_URL =
  'https://prover.cc3-testnet.creditcoin.network';
export const DEFAULT_CREDITCOIN_RPC_URL =
  'https://rpc.cc3-testnet.creditcoin.network';
export const DEFAULT_AAVE_ADAPTER =
  '0xDff00fde3829fFcA7A1dCAB0AA30602dd9F380A4';

export const AAVE_FACTS = [
  {
    kind: 'borrow',
    txHash:
      '0xbcacb57223f15070dec270cede4eed03deb60ecb117d35d8fe518a66d1c590ff',
    expectedBlock: 25_854_707,
    expectedTxIndex: 201,
    receiptLogOrdinal: 4,
  },
  {
    kind: 'repay',
    txHash:
      '0x84ea8dcff1eedb9973b8cc950d497f271e56c1d80e172187710721bfd02ba344',
    expectedBlock: 25_854_747,
    expectedTxIndex: 120,
    receiptLogOrdinal: 4,
  },
];

const INGEST_SIGNATURE =
  'ingestAaveFact((uint64,uint64,bytes32,bytes32[]),(bytes,bytes32,(bytes32,bool)[]),uint256)(bytes32)';
const HEX_32 = /^0x[0-9a-fA-F]{64}$/;
const HEX_BYTES = /^0x(?:[0-9a-fA-F]{2})+$/;

function requireInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${label} must be a non-negative safe integer`);
  }
}

function requireBytes32(value, label) {
  if (typeof value !== 'string' || !HEX_32.test(value)) {
    throw new Error(`${label} must be a 32-byte 0x-prefixed hex value`);
  }
}

export function validateProof(proof, expected) {
  if (!proof || typeof proof !== 'object') {
    throw new Error(`${expected.kind} proof must be an object`);
  }

  requireInteger(proof.chainKey, `${expected.kind}.chainKey`);
  requireInteger(proof.headerNumber, `${expected.kind}.headerNumber`);
  requireInteger(proof.txIndex, `${expected.kind}.txIndex`);

  if (proof.chainKey !== CHAIN_KEY) {
    throw new Error(
      `${expected.kind} proof returned chain key ${proof.chainKey}`,
    );
  }
  if (proof.headerNumber !== expected.expectedBlock) {
    throw new Error(
      `${expected.kind} proof returned block ${proof.headerNumber}`,
    );
  }
  if (proof.txIndex !== expected.expectedTxIndex) {
    throw new Error(
      `${expected.kind} proof returned transaction index ${proof.txIndex}`,
    );
  }
  if (
    typeof proof.txHash !== 'string' ||
    proof.txHash.toLowerCase() !== expected.txHash.toLowerCase()
  ) {
    throw new Error(`${expected.kind} proof transaction hash mismatch`);
  }
  if (typeof proof.txBytes !== 'string' || !HEX_BYTES.test(proof.txBytes)) {
    throw new Error(
      `${expected.kind}.txBytes must be non-empty byte-aligned hex`,
    );
  }

  requireBytes32(proof.merkleProof?.root, `${expected.kind}.merkleProof.root`);
  if (
    !Array.isArray(proof.merkleProof?.siblings) ||
    proof.merkleProof.siblings.length === 0
  ) {
    throw new Error(`${expected.kind}.merkleProof.siblings must be non-empty`);
  }
  if (proof.merkleProof.siblings.length > 64) {
    throw new Error(
      `${expected.kind}.merkleProof.siblings exceeds uint64 index depth`,
    );
  }
  for (const [index, sibling] of proof.merkleProof.siblings.entries()) {
    requireBytes32(sibling?.hash, `${expected.kind}.siblings[${index}].hash`);
    if (typeof sibling?.isLeft !== 'boolean') {
      throw new Error(
        `${expected.kind}.siblings[${index}].isLeft must be boolean`,
      );
    }
  }
  const structuralIndex = calculateTxIndexFromLaterality(
    proof.merkleProof.siblings,
  );
  if (structuralIndex !== proof.txIndex) {
    throw new Error(
      `${expected.kind} Merkle laterality yields index ${structuralIndex}, not ${proof.txIndex}`,
    );
  }

  requireBytes32(
    proof.continuityProof?.lowerEndpointDigest,
    `${expected.kind}.continuityProof.lowerEndpointDigest`,
  );
  if (
    !Array.isArray(proof.continuityProof?.roots) ||
    proof.continuityProof.roots.length === 0
  ) {
    throw new Error(`${expected.kind}.continuityProof.roots must be non-empty`);
  }
  for (const [index, root] of proof.continuityProof.roots.entries()) {
    requireBytes32(root, `${expected.kind}.continuityProof.roots[${index}]`);
  }

  return proof;
}

export function calculateTxIndexFromLaterality(siblings) {
  if (!Array.isArray(siblings) || siblings.length > 64) {
    throw new Error('siblings must be an array with at most 64 entries');
  }

  let index = 0n;
  for (const [depth, sibling] of siblings.entries()) {
    if (sibling?.isLeft === true) index |= 1n << BigInt(depth);
  }
  if (index > BigInt(Number.MAX_SAFE_INTEGER)) {
    throw new Error(
      'derived transaction index exceeds JavaScript safe integer range',
    );
  }
  return Number(index);
}

export function toCastArguments(proof) {
  const context = `(${proof.chainKey},${proof.headerNumber},${proof.continuityProof.lowerEndpointDigest},[${proof.continuityProof.roots.join(',')}])`;
  const siblings = proof.merkleProof.siblings
    .map((sibling) => `(${sibling.hash},${sibling.isLeft})`)
    .join(',');
  const inclusion = `(${proof.txBytes},${proof.merkleProof.root},[${siblings}])`;

  return { context, inclusion };
}

async function getJson(url) {
  const response = await fetch(url, {
    headers: { accept: 'application/json' },
    signal: AbortSignal.timeout(30_000),
  });
  const body = await response.text();

  if (!response.ok) {
    let detail = body.slice(0, 300);
    try {
      const parsed = JSON.parse(body);
      detail = `${parsed.code ?? response.status}: ${parsed.message ?? detail}`;
    } catch {
      // Keep the bounded response text when the service did not return JSON.
    }
    throw new Error(
      `proof builder request failed (${response.status}): ${detail}`,
    );
  }

  try {
    return JSON.parse(body);
  } catch {
    throw new Error(`proof builder returned invalid JSON for ${url}`);
  }
}

export async function fetchProof(baseUrl, expected) {
  const endpoint = `${baseUrl.replace(/\/$/, '')}/api/v1/proof-by-tx/${CHAIN_KEY}/${expected.txHash}`;
  return validateProof(await getJson(endpoint), expected);
}

export function simulateIngest({ rpcUrl, adapter, proof, receiptLogOrdinal }) {
  const { context, inclusion } = toCastArguments(proof);
  const result = spawnSync(
    'cast',
    [
      'call',
      adapter,
      INGEST_SIGNATURE,
      context,
      inclusion,
      String(receiptLogOrdinal),
      '--rpc-url',
      rpcUrl,
      '--gas-limit',
      '30000000',
    ],
    { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 },
  );

  if (result.error) {
    throw new Error(`could not execute cast: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout).trim().slice(0, 500);
    throw new Error(`live verifier simulation reverted: ${detail}`);
  }

  const factId = result.stdout.trim();
  requireBytes32(factId, 'simulated fact ID');
  return factId.toLowerCase();
}

export function parseOptions(argv, environment = process.env) {
  const options = {
    proofBuilderUrl:
      environment.CREDITCOIN_PROOF_BUILDER_URL ?? DEFAULT_PROOF_BUILDER_URL,
    rpcUrl: environment.CREDITCOIN_RPC_URL ?? DEFAULT_CREDITCOIN_RPC_URL,
    adapter: environment.AAVE_ADAPTER_ADDRESS ?? DEFAULT_AAVE_ADAPTER,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (
      !['--proof-builder-url', '--rpc-url', '--adapter'].includes(flag) ||
      !value
    ) {
      throw new Error(`unknown or incomplete argument: ${flag}`);
    }
    index += 1;
    if (flag === '--proof-builder-url') options.proofBuilderUrl = value;
    if (flag === '--rpc-url') options.rpcUrl = value;
    if (flag === '--adapter') options.adapter = value;
  }

  if (!/^https?:\/\//.test(options.proofBuilderUrl)) {
    throw new Error('proof builder URL must use http or https');
  }
  if (!/^https?:\/\//.test(options.rpcUrl)) {
    throw new Error('Creditcoin RPC URL must use http or https');
  }
  if (!/^0x[0-9a-fA-F]{40}$/.test(options.adapter)) {
    throw new Error('Aave adapter must be a 20-byte address');
  }

  return options;
}

export async function verifyLiveAave(options) {
  const baseUrl = options.proofBuilderUrl.replace(/\/$/, '');
  const [health, attestedHeightResponse] = await Promise.all([
    getJson(`${baseUrl}/api/v1/health`),
    getJson(`${baseUrl}/api/v1/attested-height/${CHAIN_KEY}`),
  ]);

  if (
    health?.status !== 'healthy' ||
    health.cc3_rpc_connected !== true ||
    health.eth_rpc_connected !== true
  ) {
    throw new Error('proof builder upstream health check is not healthy');
  }

  const attestedHeight = attestedHeightResponse?.attestedHeight;
  requireInteger(attestedHeight, 'attestedHeight');
  const requiredHeight =
    Math.max(...AAVE_FACTS.map((fact) => fact.expectedBlock)) + 1;
  if (attestedHeight < requiredHeight) {
    throw new Error(
      `Ethereum is attested only through ${attestedHeight}; need ${requiredHeight}`,
    );
  }

  const proofs = await Promise.all(
    AAVE_FACTS.map((fact) => fetchProof(options.proofBuilderUrl, fact)),
  );
  const facts = proofs.map((proof, index) => {
    const expected = AAVE_FACTS[index];
    return {
      kind: expected.kind,
      txHash: expected.txHash,
      block: proof.headerNumber,
      txIndex: proof.txIndex,
      receiptLogOrdinal: expected.receiptLogOrdinal,
      merkleSiblingCount: proof.merkleProof.siblings.length,
      continuityRootCount: proof.continuityProof.roots.length,
      generatedAt: proof.generatedAt ?? null,
      simulatedFactId: simulateIngest({
        rpcUrl: options.rpcUrl,
        adapter: options.adapter,
        proof,
        receiptLogOrdinal: expected.receiptLogOrdinal,
      }),
    };
  });

  return {
    mode: 'eth_call',
    persisted: false,
    chainKey: CHAIN_KEY,
    attestedHeight,
    adapter: options.adapter,
    facts,
  };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const result = await verifyLiveAave(options);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

const isMain =
  process.argv[1] &&
  fileURLToPath(import.meta.url) === resolve(process.argv[1]);

if (isMain) {
  main().catch((error) => {
    process.stderr.write(`Live proof verification failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
