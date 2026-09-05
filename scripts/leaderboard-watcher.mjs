#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

import {
  CHAIN_KEY,
  DEFAULT_AAVE_ADAPTER,
  DEFAULT_CREDITCOIN_RPC_URL,
  DEFAULT_PROOF_BUILDER_URL,
  fetchProof,
  simulateIngest,
  toCastArguments,
} from './verify-live-aave.mjs';

export const AAVE_V3_POOL = '0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2';
export const USDC = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
export const AAVE_BORROW_TOPIC =
  '0xb3d084820fb1a9decffb176436bd02558d15fac9b0ddfed8c465bc7359d7dce0';
export const AAVE_REPAY_TOPIC =
  '0xa534c8dbe71f871f9f3530e97a74601fea17b426cae02e1c5aee42c96c784051';
export const MINIMUM_SELF_REPAYMENT_BLOCK_GAP = 32;

const INGEST_SIGNATURE =
  'ingestAaveFact((uint64,uint64,bytes32,bytes32[]),(bytes,bytes32,(bytes32,bool)[]),uint256)(bytes32)';
const FACT_OF_SIGNATURE =
  'factOf(bytes32)((uint8,address,address,address,uint128,uint64,(uint64,uint64,uint64),bytes32))';
const FACT_USED_SIGNATURE = 'factUsedInObservation(bytes32)(bool)';
const LINK_SIGNATURE = 'linkVerifiedSelfRepayment(bytes32,bytes32)(bytes32)';
const HEX_32 = /^0x[0-9a-fA-F]{64}$/;
const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const PRIVATE_KEY = /^0x[0-9a-fA-F]{64}$/;

function safeInteger(value, label) {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${label} must be a non-negative safe integer`);
  }
  return parsed;
}

function rpcNumber(value, label) {
  if (typeof value === 'number') return safeInteger(value, label);
  if (typeof value !== 'string' || !/^0x[0-9a-fA-F]+$/.test(value)) {
    throw new Error(`${label} must be a hexadecimal RPC quantity`);
  }
  return safeInteger(BigInt(value), label);
}

function normalizeAddress(value, label = 'address') {
  if (typeof value !== 'string' || !ADDRESS.test(value)) {
    throw new Error(`${label} must be a 20-byte 0x-prefixed address`);
  }
  return value.toLowerCase();
}

function normalizeHash(value, label) {
  if (typeof value !== 'string' || !HEX_32.test(value)) {
    throw new Error(`${label} must be a 32-byte 0x-prefixed hash`);
  }
  return value.toLowerCase();
}

function addressTopic(address) {
  return `0x${normalizeAddress(address).slice(2).padStart(64, '0')}`;
}

function addressFromTopic(topic, label) {
  const normalized = normalizeHash(topic, label);
  if (!/^0x0{24}/.test(normalized)) {
    throw new Error(`${label} contains a non-address topic value`);
  }
  return `0x${normalized.slice(-40)}`;
}

function wordAt(data, index, label) {
  if (typeof data !== 'string' || !/^0x(?:[0-9a-fA-F]{2})*$/.test(data)) {
    throw new Error(`${label} must be byte-aligned hex`);
  }
  const start = 2 + index * 64;
  const end = start + 64;
  if (data.length < end) throw new Error(`${label} is shorter than word ${index}`);
  return BigInt(`0x${data.slice(start, end)}`);
}

function positionCompare(left, right) {
  if (left.blockNumber !== right.blockNumber) return left.blockNumber - right.blockNumber;
  if (left.transactionIndex !== right.transactionIndex) return left.transactionIndex - right.transactionIndex;
  return left.logIndex - right.logIndex;
}

function redact(message, secrets) {
  return secrets.filter(Boolean).reduce(
    (redacted, secret) => redacted.replaceAll(secret, '[redacted]'),
    message,
  );
}

function runCast(args, label, secrets = []) {
  const result = spawnSync('cast', args, {
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error) {
    throw new Error(`${label} could not start: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const detail = redact((result.stderr || result.stdout || '').trim().slice(0, 600), secrets);
    throw new Error(`${label} failed${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout.trim();
}

async function rpcRequest(url, method, params) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
    signal: AbortSignal.timeout(30_000),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`source RPC ${method} failed with HTTP ${response.status}`);
  }

  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    throw new Error(`source RPC ${method} returned invalid JSON`);
  }
  if (payload?.error) {
    throw new Error(`source RPC ${method} failed: ${payload.error.message ?? payload.error.code}`);
  }
  return payload?.result;
}

function blockTag(blockNumber) {
  return `0x${blockNumber.toString(16)}`;
}

export function parseWatchlist(value, fallbackStartBlock) {
  if (!value?.trim()) return [];
  return value.split(',').map((entry) => {
    const [rawAddress, rawStartBlock, ...extra] = entry.trim().split('@');
    if (!rawAddress || extra.length > 0) {
      throw new Error('Each watchlist entry must use address@first-source-block.');
    }
    const startBlock = rawStartBlock ? Number(rawStartBlock) : fallbackStartBlock;
    return {
      address: normalizeAddress(rawAddress, 'watchlist address'),
      startBlock: safeInteger(startBlock, 'watchlist start block'),
    };
  });
}

export function parseOptions(argv, environment = process.env) {
  const options = {
    sourceRpcUrl: environment.ETHEREUM_RPC_URL ?? environment.SOURCE_RPC_URL ?? '',
    creditcoinRpcUrl: environment.CREDITCOIN_RPC_URL ?? DEFAULT_CREDITCOIN_RPC_URL,
    proofBuilderUrl:
      environment.CREDITCOIN_PROOF_BUILDER_URL ?? DEFAULT_PROOF_BUILDER_URL,
    adapter: environment.AAVE_ADAPTER_ADDRESS ?? DEFAULT_AAVE_ADAPTER,
    privateKey: environment.CREDITCOIN_PRIVATE_KEY ?? '',
    watchlist: environment.PROVER_BORROWER_WATCHLIST ?? '',
    fallbackStartBlock: environment.PROVER_AAVE_START_BLOCK
      ? Number(environment.PROVER_AAVE_START_BLOCK)
      : undefined,
    logChunkSize: environment.PROVER_AAVE_LOG_CHUNK_SIZE
      ? Number(environment.PROVER_AAVE_LOG_CHUNK_SIZE)
      : 10_000,
    submit: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === '--submit') {
      options.submit = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value) throw new Error(`unknown or incomplete argument: ${flag}`);
    index += 1;
    if (flag === '--source-rpc-url') options.sourceRpcUrl = value;
    else if (flag === '--creditcoin-rpc-url') options.creditcoinRpcUrl = value;
    else if (flag === '--proof-builder-url') options.proofBuilderUrl = value;
    else if (flag === '--adapter') options.adapter = value;
    else if (flag === '--watchlist') options.watchlist = value;
    else if (flag === '--log-chunk-size') options.logChunkSize = Number(value);
    else throw new Error(`unknown or incomplete argument: ${flag}`);
  }

  if (options.sourceRpcUrl && !/^https?:\/\//.test(options.sourceRpcUrl)) {
    throw new Error('Ethereum source RPC URL must use http or https.');
  }
  if (!/^https?:\/\//.test(options.creditcoinRpcUrl)) {
    throw new Error('Creditcoin RPC URL must use http or https.');
  }
  if (!/^https?:\/\//.test(options.proofBuilderUrl)) {
    throw new Error('proof builder URL must use http or https.');
  }
  options.adapter = normalizeAddress(options.adapter, 'Aave adapter');
  options.logChunkSize = safeInteger(options.logChunkSize, 'log chunk size');
  if (options.logChunkSize === 0) throw new Error('log chunk size must be greater than zero.');

  const watchlist = parseWatchlist(options.watchlist, options.fallbackStartBlock);
  if (watchlist.length > 0 && !options.sourceRpcUrl) {
    throw new Error('ETHEREUM_RPC_URL is required when a borrower watchlist is configured.');
  }
  if (options.submit && !PRIVATE_KEY.test(options.privateKey)) {
    throw new Error('CREDITCOIN_PRIVATE_KEY is required only for --submit.');
  }

  return { ...options, watchlist };
}

async function getLogsInRanges(sourceRpcUrl, filter, startBlock, endBlock, chunkSize) {
  const logs = [];
  for (let fromBlock = startBlock; fromBlock <= endBlock; fromBlock += chunkSize) {
    const toBlock = Math.min(fromBlock + chunkSize - 1, endBlock);
    const result = await rpcRequest(sourceRpcUrl, 'eth_getLogs', [
      { ...filter, fromBlock: blockTag(fromBlock), toBlock: blockTag(toBlock) },
    ]);
    if (!Array.isArray(result)) throw new Error('source RPC eth_getLogs returned a non-array result');
    logs.push(...result);
  }
  return logs;
}

export function parseAaveLog(kind, subject, log) {
  const normalizedSubject = normalizeAddress(subject, 'subject');
  if (!log || typeof log !== 'object' || !Array.isArray(log.topics)) {
    throw new Error('Aave log must include topics');
  }
  if (log.topics.length !== 4) throw new Error('Aave log must have exactly four topics');
  if (normalizeAddress(log.address, 'Aave log emitter') !== AAVE_V3_POOL) {
    throw new Error('Aave log has the wrong emitter');
  }
  if (addressFromTopic(log.topics[1], 'reserve topic') !== USDC) {
    throw new Error('Aave log is not a USDC event');
  }
  if (addressFromTopic(log.topics[2], 'subject topic') !== normalizedSubject) {
    throw new Error('Aave log subject does not match the watchlist entry');
  }

  const expectedTopic = kind === 'borrow' ? AAVE_BORROW_TOPIC : AAVE_REPAY_TOPIC;
  if (normalizeHash(log.topics[0], 'Aave event topic') !== expectedTopic) {
    throw new Error(`Aave log is not a ${kind} event`);
  }

  const repayer = kind === 'repay' ? addressFromTopic(log.topics[3], 'repayer topic') : null;
  return {
    kind,
    subject: normalizedSubject,
    txHash: normalizeHash(log.transactionHash, 'transaction hash'),
    blockNumber: rpcNumber(log.blockNumber, 'source block number'),
    transactionIndex: rpcNumber(log.transactionIndex, 'source transaction index'),
    logIndex: rpcNumber(log.logIndex, 'source log index'),
    amount: wordAt(log.data, kind === 'borrow' ? 1 : 0, 'Aave event data'),
    repayer,
  };
}

export function matchSelfRepayments(borrows, repays) {
  const availableRepays = [...repays]
    .filter((repay) => repay.repayer === repay.subject)
    .sort(positionCompare);
  const matches = [];

  for (const borrow of [...borrows].sort(positionCompare)) {
    const repayIndex = availableRepays.findIndex(
      (repay) =>
        repay.blockNumber >= borrow.blockNumber + MINIMUM_SELF_REPAYMENT_BLOCK_GAP &&
        repay.amount >= borrow.amount,
    );
    if (repayIndex === -1) continue;
    matches.push({ borrow, repay: availableRepays[repayIndex] });
    availableRepays.splice(repayIndex, 1);
  }
  return matches;
}

export function findReceiptLogOrdinal(receipt, candidate) {
  if (!receipt || !Array.isArray(receipt.logs)) {
    throw new Error('source transaction receipt did not include logs');
  }
  const candidateLogIndex = candidate.logIndex;
  const ordinal = receipt.logs.findIndex(
    (log) => rpcNumber(log.logIndex, 'receipt log index') === candidateLogIndex,
  );
  if (ordinal < 0) throw new Error('candidate event was not found in its source transaction receipt');
  return ordinal;
}

async function hydrateCandidate(sourceRpcUrl, candidate) {
  const receipt = await rpcRequest(sourceRpcUrl, 'eth_getTransactionReceipt', [candidate.txHash]);
  if (!receipt) throw new Error(`source receipt is unavailable for ${candidate.txHash}`);
  if (receipt.status !== '0x1') throw new Error(`source transaction ${candidate.txHash} reverted`);

  const expectedBlock = rpcNumber(receipt.blockNumber, 'receipt block number');
  const expectedTxIndex = rpcNumber(receipt.transactionIndex, 'receipt transaction index');
  if (expectedBlock !== candidate.blockNumber || expectedTxIndex !== candidate.transactionIndex) {
    throw new Error(`source receipt coordinates changed for ${candidate.txHash}`);
  }
  return {
    ...candidate,
    receiptLogOrdinal: findReceiptLogOrdinal(receipt, candidate),
  };
}

function deriveFactId(proof) {
  const transactionCommitment = runCast(['keccak', proof.txBytes], 'transaction commitment');
  const encoded = runCast(
    [
      'abi-encode',
      'f(uint64,uint64,uint64,bytes32,bytes32)',
      String(proof.chainKey),
      String(proof.headerNumber),
      String(proof.txIndex),
      transactionCommitment,
      proof.merkleProof.root,
    ],
    'fact ID encoding',
  );
  return normalizeHash(runCast(['keccak', encoded], 'fact ID hash'), 'derived fact ID');
}

function factAlreadyRecorded(options, factId) {
  const output = runCast(
    ['call', options.adapter, FACT_OF_SIGNATURE, factId, '--rpc-url', options.creditcoinRpcUrl, '--json'],
    'fact lookup',
  );
  const parsed = JSON.parse(output);
  return Number(parsed?.[0]?.[0] ?? 0) !== 0;
}

function factUsedInObservation(options, factId) {
  const output = runCast(
    ['call', options.adapter, FACT_USED_SIGNATURE, factId, '--rpc-url', options.creditcoinRpcUrl, '--json'],
    'fact-use lookup',
  );
  return JSON.parse(output) === true;
}

function sendIngest(options, proof, receiptLogOrdinal) {
  const { context, inclusion } = toCastArguments(proof);
  return runCast(
    [
      'send',
      options.adapter,
      INGEST_SIGNATURE,
      context,
      inclusion,
      String(receiptLogOrdinal),
      '--rpc-url',
      options.creditcoinRpcUrl,
      '--private-key',
      options.privateKey,
      '--json',
    ],
    'Aave fact submission',
    [options.privateKey],
  );
}

function sendLink(options, borrowFactId, repayFactId) {
  return runCast(
    [
      'send',
      options.adapter,
      LINK_SIGNATURE,
      borrowFactId,
      repayFactId,
      '--rpc-url',
      options.creditcoinRpcUrl,
      '--private-key',
      options.privateKey,
      '--json',
    ],
    'self-repayment link submission',
    [options.privateKey],
  );
}

async function prepareFact(options, candidate) {
  const hydrated = await hydrateCandidate(options.sourceRpcUrl, candidate);
  const expected = {
    kind: hydrated.kind,
    txHash: hydrated.txHash,
    expectedBlock: hydrated.blockNumber,
    expectedTxIndex: hydrated.transactionIndex,
  };
  const proof = await fetchProof(options.proofBuilderUrl, expected);
  const factId = deriveFactId(proof);
  return { ...hydrated, proof, factId };
}

function ensureFact(options, prepared) {
  if (factAlreadyRecorded(options, prepared.factId)) {
    return { factId: prepared.factId, status: 'already-recorded' };
  }

  const simulatedFactId = simulateIngest({
    rpcUrl: options.creditcoinRpcUrl,
    adapter: options.adapter,
    proof: prepared.proof,
    receiptLogOrdinal: prepared.receiptLogOrdinal,
  });
  if (simulatedFactId !== prepared.factId) {
    throw new Error('native adapter fact ID did not match the independently derived ID');
  }
  if (!options.submit) return { factId: prepared.factId, status: 'ready-to-submit' };

  sendIngest(options, prepared.proof, prepared.receiptLogOrdinal);
  return { factId: prepared.factId, status: 'submitted' };
}

async function scanWatchlistEntry(options, entry, sourceHead) {
  const filterFor = (topic) => ({
    address: AAVE_V3_POOL,
    topics: [topic, addressTopic(USDC), addressTopic(entry.address)],
  });
  const [borrowLogs, repayLogs] = await Promise.all([
    getLogsInRanges(
      options.sourceRpcUrl,
      filterFor(AAVE_BORROW_TOPIC),
      entry.startBlock,
      sourceHead,
      options.logChunkSize,
    ),
    getLogsInRanges(
      options.sourceRpcUrl,
      filterFor(AAVE_REPAY_TOPIC),
      entry.startBlock,
      sourceHead,
      options.logChunkSize,
    ),
  ]);
  return {
    borrows: borrowLogs.map((log) => parseAaveLog('borrow', entry.address, log)),
    repays: repayLogs.map((log) => parseAaveLog('repay', entry.address, log)),
  };
}

export async function runWatcher(options) {
  if (options.watchlist.length === 0) {
    return {
      mode: options.submit ? 'submit' : 'dry-run',
      watchedAddresses: 0,
      message: 'No borrower watchlist is configured; no source-chain activity was read.',
      results: [],
    };
  }

  const sourceHead = rpcNumber(
    await rpcRequest(options.sourceRpcUrl, 'eth_blockNumber', []),
    'Ethereum source head',
  );
  const results = [];
  for (const entry of options.watchlist) {
    if (entry.startBlock > sourceHead) {
      results.push({
        address: entry.address,
        status: 'waiting-for-source-height',
        startBlock: entry.startBlock,
        sourceHead,
      });
      continue;
    }

    const events = await scanWatchlistEntry(options, entry, sourceHead);
    const matches = matchSelfRepayments(events.borrows, events.repays);
    const matchResults = [];
    for (const match of matches) {
      try {
        const [borrow, repay] = await Promise.all([
          prepareFact(options, match.borrow),
          prepareFact(options, match.repay),
        ]);
        const borrowResult = ensureFact(options, borrow);
        const repayResult = ensureFact(options, repay);
        let observation = 'ready-to-link';
        if (options.submit) {
          if (
            factUsedInObservation(options, borrowResult.factId) ||
            factUsedInObservation(options, repayResult.factId)
          ) {
            observation = 'already-linked-or-ineligible';
          } else {
            sendLink(options, borrowResult.factId, repayResult.factId);
            observation = 'submitted';
          }
        }
        matchResults.push({
          borrowFactId: borrowResult.factId,
          repayFactId: repayResult.factId,
          borrow: borrowResult.status,
          repay: repayResult.status,
          observation,
        });
      } catch (error) {
        matchResults.push({
          borrowTxHash: match.borrow.txHash,
          repayTxHash: match.repay.txHash,
          status: 'not-ready',
          detail: error instanceof Error ? error.message : 'unknown watcher error',
        });
      }
    }

    results.push({
      address: entry.address,
      startBlock: entry.startBlock,
      sourceHead,
      discoveredBorrowEvents: events.borrows.length,
      discoveredSelfFundedRepayEvents: events.repays.filter(
        (repay) => repay.repayer === repay.subject,
      ).length,
      eligiblePairs: matches.length,
      matches: matchResults,
    });
  }

  return {
    mode: options.submit ? 'submit' : 'dry-run',
    chainKey: CHAIN_KEY,
    sourceHead,
    watchedAddresses: options.watchlist.length,
    results,
  };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  const result = await runWatcher(options);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

const isMain =
  process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1]);

if (isMain) {
  main().catch((error) => {
    process.stderr.write(`Leaderboard watcher failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
