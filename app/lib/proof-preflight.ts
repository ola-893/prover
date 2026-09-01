import {
  isProofEngineId,
  publicAaveCase,
  proofEngineById,
  type ProofEngineId,
  type ProofInputDefinition,
} from '@/lib/proof-engines';
import {
  type PreflightGate,
  type PreflightResult,
  type ProofInputValues,
  type ProofPacketSummary,
} from '@/lib/proof-router';
import { cc3Deployment } from '@/lib/deployment';

const CREDITCOIN_RPC_URL = 'https://rpc.cc3-testnet.creditcoin.network';
const PROOF_BUILDER_URL = 'https://prover.cc3-testnet.creditcoin.network';
const CHAIN_INFO_ADDRESS = '0x0000000000000000000000000000000000000fD3';
const COVENANT_BOOK_ADDRESS = cc3Deployment.contracts[1].address;
const PROMISE_BOOK_ADDRESS = cc3Deployment.promiseContracts[1].address;

const COVENANT_OF_SELECTOR = '0xe38cc66d';
const PROMISE_OF_SELECTOR = '0xd3666681';
const LATEST_ATTESTATION_SELECTOR = '0x809112da';
const RFQ_POLICY_ID =
  '0xb978d3df77626726a2f97ab4868c290230777acacb8838ee73257c7c038e2b61';
const SETTLEMENT_POLICY_ID =
  '0x5155e763850602618ae4be11798d48cc6240a928740cfda92fa295f860c52a83';
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const ZERO_BYTES32 = `0x${'0'.repeat(64)}`;
const UINT128_MAX = (1n << 128n) - 1n;
const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const BYTES32 = /^0x[0-9a-fA-F]{64}$/;
const HEX_BYTES = /^0x(?:[0-9a-fA-F]{2})+$/;
const DECIMAL_INTEGER = /^(0|[1-9][0-9]*)$/;
const UPSTREAM_TIMEOUT_MS = 10_000;
const OVERALL_TIMEOUT_MS = 15_000;
const SMALL_RESPONSE_LIMIT = 32 * 1024;
const PROOF_RESPONSE_LIMIT = 1024 * 1024;
const SUPPORTED_EVM_CHAIN_KEYS = new Set([1, 3]);

const PUBLIC_AAVE_COORDINATES = {
  borrowBlock: 25_854_707,
  borrowIndex: 201,
  repayBlock: 25_854_747,
  repayIndex: 120,
} as const;

type JsonRecord = Record<string, unknown>;

interface ValidatedPreflightRequest {
  engineId: ProofEngineId;
  inputs: ProofInputValues;
}

interface PreflightContext {
  blockTag: string;
  signal: AbortSignal;
  abort: () => void;
}

interface ChainInfo {
  height: number;
  hash: string;
  isAttestation: boolean;
  exists: boolean;
}

interface CovenantRecord {
  operator: string;
  sourceContract: string;
  policyHash: string;
  covenantType: number;
  chainKey: number;
  validFromHeight: number;
  validUntilHeight: number;
  claimDeadlineHeight: number;
  breachCount: number;
  fixedPenalty: bigint;
  initialBond: bigint;
  remainingBond: bigint;
  totalPaid: bigint;
  totalShortfall: bigint;
  bondReleased: boolean;
}

interface PromiseRecord {
  actor: string;
  beneficiary: string;
  sourceContract: string;
  termsHash: string;
  policyId: string;
  kind: number;
  sourceChainKey: number;
  sourcePolicyRevision: number;
  validFromHeight: number;
  fulfillmentDeadlineHeight: number;
  proofDeadlineHeight: number;
  fixedPenalty: bigint;
  bond: bigint;
  outcome: number;
  evidenceId: string;
  evidenceHeight: number;
  resolvedAtAttestedHeight: number;
  draftId: string;
  entropyHash: string;
  activationAttestedHeight: number;
  activationAttestationHash: string;
}

interface InternalProofPacket extends ProofPacketSummary {
  merkleRoot: string;
}

export class PreflightInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PreflightInputError';
  }
}

class UpstreamError extends Error {
  constructor(
    readonly service: 'Creditcoin RPC' | 'Attestcoin proof builder',
    message: string,
  ) {
    super(message);
    this.name = 'UpstreamError';
  }
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validateInput(definition: ProofInputDefinition, raw: unknown): string {
  if (typeof raw !== 'string' || raw.length === 0 || raw.length > 100) {
    throw new PreflightInputError(`${definition.label} is required.`);
  }
  const value = raw.trim();
  if (definition.kind === 'address' && !ADDRESS.test(value)) {
    throw new PreflightInputError(
      `${definition.label} must be a 20-byte 0x-prefixed address.`,
    );
  }
  if (definition.kind === 'bytes32' && !BYTES32.test(value)) {
    throw new PreflightInputError(
      `${definition.label} must be a 32-byte 0x-prefixed value.`,
    );
  }
  if (definition.kind === 'integer') {
    if (!DECIMAL_INTEGER.test(value) || BigInt(value) > 10_000n) {
      throw new PreflightInputError(
        `${definition.label} must be an integer from 0 to 10,000.`,
      );
    }
  }
  return value;
}

export function validatePreflightRequest(
  payload: unknown,
): ValidatedPreflightRequest {
  if (!isRecord(payload)) {
    throw new PreflightInputError('Request body must be a JSON object.');
  }
  const topLevelKeys = Object.keys(payload);
  if (
    topLevelKeys.length !== 2 ||
    !topLevelKeys.includes('engineId') ||
    !topLevelKeys.includes('inputs')
  ) {
    throw new PreflightInputError(
      'Request body must contain only engineId and inputs.',
    );
  }
  if (!isProofEngineId(payload.engineId)) {
    throw new PreflightInputError('Unsupported proof engine.');
  }
  if (!isRecord(payload.inputs)) {
    throw new PreflightInputError('inputs must be a JSON object.');
  }

  const engine = proofEngineById(payload.engineId);
  const allowedKeys = new Set(engine.inputs.map((input) => input.key));
  const suppliedKeys = Object.keys(payload.inputs);
  if (suppliedKeys.some((key) => !allowedKeys.has(key as never))) {
    throw new PreflightInputError('inputs contains an unsupported field.');
  }
  if (suppliedKeys.length !== engine.inputs.length) {
    throw new PreflightInputError(
      `Exactly ${engine.inputs.length} inputs are required for ${engine.shortLabel}.`,
    );
  }

  const inputs: ProofInputValues = {};
  for (const definition of engine.inputs) {
    inputs[definition.key] = validateInput(
      definition,
      payload.inputs[definition.key],
    );
  }
  return { engineId: payload.engineId, inputs };
}

async function fetchBoundedText(
  url: string,
  init: RequestInit,
  limit: number,
  service: UpstreamError['service'],
  parentSignal?: AbortSignal,
): Promise<string> {
  const controller = new AbortController();
  const abortFromParent = () => controller.abort();
  if (parentSignal?.aborted) controller.abort();
  else parentSignal?.addEventListener('abort', abortFromParent, { once: true });
  const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      ...init,
      signal: controller.signal,
      cache: 'no-store',
    });
    const contentLength = Number(response.headers.get('content-length'));
    if (Number.isFinite(contentLength) && contentLength > limit) {
      await response.body?.cancel();
      throw new UpstreamError(service, 'response exceeded the size limit');
    }
    const reader = response.body?.getReader();
    if (!reader) throw new UpstreamError(service, 'response body was empty');
    const decoder = new TextDecoder();
    let text = '';
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        controller.abort();
        throw new UpstreamError(service, 'response exceeded the size limit');
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    if (!response.ok) {
      throw new UpstreamError(
        service,
        `request returned HTTP ${response.status}`,
      );
    }
    return text;
  } catch (error) {
    if (error instanceof UpstreamError) throw error;
    if (error instanceof Error && error.name === 'AbortError') {
      throw new UpstreamError(service, 'request timed out');
    }
    throw new UpstreamError(service, 'request failed');
  } finally {
    clearTimeout(timeout);
    parentSignal?.removeEventListener('abort', abortFromParent);
  }
}

async function fetchJson(
  url: string,
  limit: number,
  service: UpstreamError['service'],
  signal?: AbortSignal,
): Promise<unknown> {
  const text = await fetchBoundedText(
    url,
    { headers: { accept: 'application/json' } },
    limit,
    service,
    signal,
  );
  try {
    return JSON.parse(text);
  } catch {
    throw new UpstreamError(service, 'returned invalid JSON');
  }
}

let rpcId = 0;

async function rpcCall(
  method: string,
  params: unknown[],
  signal?: AbortSignal,
): Promise<unknown> {
  rpcId += 1;
  const id = rpcId;
  const text = await fetchBoundedText(
    CREDITCOIN_RPC_URL,
    {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
      },
      body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    },
    SMALL_RESPONSE_LIMIT,
    'Creditcoin RPC',
    signal,
  );
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new UpstreamError('Creditcoin RPC', 'returned invalid JSON');
  }
  if (
    !isRecord(payload) ||
    payload.jsonrpc !== '2.0' ||
    payload.id !== id ||
    'error' in payload ||
    !('result' in payload)
  ) {
    throw new UpstreamError('Creditcoin RPC', 'returned an invalid response');
  }
  return payload.result;
}

async function getSnapshotBlockTag(signal: AbortSignal): Promise<string> {
  const result = await rpcCall('eth_blockNumber', [], signal);
  if (typeof result !== 'string' || !/^0x[0-9a-fA-F]+$/.test(result)) {
    throw new UpstreamError('Creditcoin RPC', 'returned an invalid block tag');
  }
  return result;
}

async function ethCall(
  to: string,
  data: string,
  context: PreflightContext,
): Promise<string> {
  const result = await rpcCall(
    'eth_call',
    [{ to, data }, context.blockTag],
    context.signal,
  );
  if (typeof result !== 'string' || !/^0x[0-9a-fA-F]*$/.test(result)) {
    throw new UpstreamError('Creditcoin RPC', 'returned invalid call data');
  }
  return result;
}

async function hasRuntimeCode(
  address: string,
  context: PreflightContext,
): Promise<boolean> {
  const result = await rpcCall(
    'eth_getCode',
    [address, context.blockTag],
    context.signal,
  );
  if (typeof result !== 'string' || !/^0x(?:[0-9a-fA-F]{2})*$/.test(result)) {
    throw new UpstreamError('Creditcoin RPC', 'returned invalid runtime code');
  }
  return result !== '0x' && !/^0x0*$/.test(result);
}

function abiWords(
  encoded: string,
  expectedCount: number,
  label: string,
): string[] {
  if (encoded.length !== 2 + expectedCount * 64) {
    throw new UpstreamError(
      'Creditcoin RPC',
      `${label} returned an unexpected ABI length`,
    );
  }
  const words: string[] = [];
  for (let offset = 2; offset < encoded.length; offset += 64) {
    words.push(encoded.slice(offset, offset + 64).toLowerCase());
  }
  return words;
}

function decodeAddress(word: string, label: string): string {
  if (!/^0{24}[0-9a-f]{40}$/.test(word)) {
    throw new UpstreamError('Creditcoin RPC', `${label} was not an address`);
  }
  return `0x${word.slice(24)}`;
}

function decodeUint(word: string): bigint {
  return BigInt(`0x${word}`);
}

function decodeNarrowUint(word: string, bits: number, label: string): number {
  const value = decodeUint(word);
  if (
    value > (1n << BigInt(bits)) - 1n ||
    value > BigInt(Number.MAX_SAFE_INTEGER)
  ) {
    throw new UpstreamError(
      'Creditcoin RPC',
      `${label} exceeded its ABI range`,
    );
  }
  return Number(value);
}

function decodeBool(word: string, label: string): boolean {
  const value = decodeUint(word);
  if (value !== 0n && value !== 1n) {
    throw new UpstreamError('Creditcoin RPC', `${label} was not a boolean`);
  }
  return value === 1n;
}

function bytes32Word(word: string): string {
  return `0x${word}`;
}

function encodeBytes32Call(selector: string, value: string): string {
  return `${selector}${value.slice(2)}`;
}

function encodeUint64Call(selector: string, value: number): string {
  return `${selector}${BigInt(value).toString(16).padStart(64, '0')}`;
}

async function readCovenant(
  covenantId: string,
  context: PreflightContext,
): Promise<CovenantRecord> {
  const words = abiWords(
    await ethCall(
      COVENANT_BOOK_ADDRESS,
      encodeBytes32Call(COVENANT_OF_SELECTOR, covenantId),
      context,
    ),
    15,
    'CovenantBook',
  );
  const covenantType = decodeNarrowUint(words[3], 8, 'covenant type');
  if (covenantType > 1) {
    throw new UpstreamError(
      'Creditcoin RPC',
      'returned an unknown covenant type',
    );
  }
  return {
    operator: decodeAddress(words[0], 'operator'),
    sourceContract: decodeAddress(words[1], 'source contract'),
    policyHash: bytes32Word(words[2]),
    covenantType,
    chainKey: decodeNarrowUint(words[4], 64, 'source chain key'),
    validFromHeight: decodeNarrowUint(words[5], 64, 'valid-from height'),
    validUntilHeight: decodeNarrowUint(words[6], 64, 'valid-until height'),
    claimDeadlineHeight: decodeNarrowUint(words[7], 64, 'claim deadline'),
    breachCount: decodeNarrowUint(words[8], 32, 'breach count'),
    fixedPenalty: decodeUint(words[9]),
    initialBond: decodeUint(words[10]),
    remainingBond: decodeUint(words[11]),
    totalPaid: decodeUint(words[12]),
    totalShortfall: decodeUint(words[13]),
    bondReleased: decodeBool(words[14], 'bond-released flag'),
  };
}

async function readPromise(
  promiseId: string,
  context: PreflightContext,
): Promise<PromiseRecord> {
  const words = abiWords(
    await ethCall(
      PROMISE_BOOK_ADDRESS,
      encodeBytes32Call(PROMISE_OF_SELECTOR, promiseId),
      context,
    ),
    21,
    'PromiseBook',
  );
  const kind = decodeNarrowUint(words[5], 8, 'promise kind');
  const outcome = decodeNarrowUint(words[13], 8, 'promise outcome');
  if (kind > 1 || outcome > 3) {
    throw new UpstreamError(
      'Creditcoin RPC',
      'returned an unknown promise enum',
    );
  }
  return {
    actor: decodeAddress(words[0], 'actor'),
    beneficiary: decodeAddress(words[1], 'beneficiary'),
    sourceContract: decodeAddress(words[2], 'source contract'),
    termsHash: bytes32Word(words[3]),
    policyId: bytes32Word(words[4]),
    kind,
    sourceChainKey: decodeNarrowUint(words[6], 64, 'source chain key'),
    sourcePolicyRevision: decodeNarrowUint(
      words[7],
      64,
      'source policy revision',
    ),
    validFromHeight: decodeNarrowUint(words[8], 64, 'valid-from height'),
    fulfillmentDeadlineHeight: decodeNarrowUint(
      words[9],
      64,
      'fulfillment deadline',
    ),
    proofDeadlineHeight: decodeNarrowUint(words[10], 64, 'proof deadline'),
    fixedPenalty: decodeUint(words[11]),
    bond: decodeUint(words[12]),
    outcome,
    evidenceId: bytes32Word(words[14]),
    evidenceHeight: decodeNarrowUint(words[15], 64, 'evidence height'),
    resolvedAtAttestedHeight: decodeNarrowUint(
      words[16],
      64,
      'resolution height',
    ),
    draftId: bytes32Word(words[17]),
    entropyHash: bytes32Word(words[18]),
    activationAttestedHeight: decodeNarrowUint(
      words[19],
      64,
      'activation attested height',
    ),
    activationAttestationHash: bytes32Word(words[20]),
  };
}

async function readChainInfo(
  chainKey: number,
  context: PreflightContext,
): Promise<ChainInfo> {
  const words = abiWords(
    await ethCall(
      CHAIN_INFO_ADDRESS,
      encodeUint64Call(LATEST_ATTESTATION_SELECTOR, chainKey),
      context,
    ),
    4,
    'ChainInfo',
  );
  return {
    height: decodeNarrowUint(words[0], 64, 'attested height'),
    hash: bytes32Word(words[1]),
    isAttestation: decodeBool(words[2], 'is-attestation flag'),
    exists: decodeBool(words[3], 'exists flag'),
  };
}

async function checkProofBuilderHealth(signal: AbortSignal): Promise<void> {
  const health = await fetchJson(
    `${PROOF_BUILDER_URL}/api/v1/health`,
    SMALL_RESPONSE_LIMIT,
    'Attestcoin proof builder',
    signal,
  );
  if (
    !isRecord(health) ||
    health.status !== 'healthy' ||
    health.cc3_rpc_connected !== true ||
    health.eth_rpc_connected !== true
  ) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'reported an unhealthy upstream',
    );
  }
}

function safeInteger(value: unknown, label: string): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new UpstreamError('Attestcoin proof builder', `${label} was invalid`);
  }
  return Number(value);
}

function asBytes32(value: unknown, label: string): string {
  if (typeof value !== 'string' || !BYTES32.test(value)) {
    throw new UpstreamError('Attestcoin proof builder', `${label} was invalid`);
  }
  return value.toLowerCase();
}

async function readProofPacket(
  role: string,
  chainKey: number,
  txHash: string,
  signal: AbortSignal,
): Promise<InternalProofPacket> {
  const payload = await fetchJson(
    `${PROOF_BUILDER_URL}/api/v1/proof-by-tx/${chainKey}/${txHash}`,
    PROOF_RESPONSE_LIMIT,
    'Attestcoin proof builder',
    signal,
  );
  if (!isRecord(payload)) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'proof packet was not an object',
    );
  }
  const returnedChainKey = safeInteger(payload.chainKey, 'chain key');
  const blockHeight = safeInteger(payload.headerNumber, 'block height');
  const txIndex = safeInteger(payload.txIndex, 'transaction index');
  if (returnedChainKey !== chainKey) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'proof packet used the wrong source chain',
    );
  }
  if (
    typeof payload.txHash !== 'string' ||
    payload.txHash.toLowerCase() !== txHash.toLowerCase()
  ) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'proof transaction hash did not match',
    );
  }
  if (
    typeof payload.txBytes !== 'string' ||
    payload.txBytes.length > PROOF_RESPONSE_LIMIT ||
    !HEX_BYTES.test(payload.txBytes)
  ) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'encoded transaction bytes were invalid',
    );
  }
  if (!isRecord(payload.merkleProof)) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'Merkle proof was missing',
    );
  }
  const merkleRoot = asBytes32(payload.merkleProof.root, 'Merkle root');
  const siblings = payload.merkleProof.siblings;
  if (
    !Array.isArray(siblings) ||
    siblings.length === 0 ||
    siblings.length > 64
  ) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'Merkle siblings were invalid',
    );
  }
  let structuralIndex = 0n;
  siblings.forEach((sibling, depth) => {
    if (!isRecord(sibling) || typeof sibling.isLeft !== 'boolean') {
      throw new UpstreamError(
        'Attestcoin proof builder',
        'Merkle sibling laterality was invalid',
      );
    }
    asBytes32(sibling.hash, 'Merkle sibling hash');
    if (sibling.isLeft) structuralIndex |= 1n << BigInt(depth);
  });
  if (structuralIndex !== BigInt(txIndex)) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'Merkle laterality did not reproduce the transaction index',
    );
  }
  if (!isRecord(payload.continuityProof)) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'continuity proof was missing',
    );
  }
  asBytes32(payload.continuityProof.lowerEndpointDigest, 'continuity endpoint');
  const roots = payload.continuityProof.roots;
  if (!Array.isArray(roots) || roots.length === 0 || roots.length > 4096) {
    throw new UpstreamError(
      'Attestcoin proof builder',
      'continuity roots were invalid',
    );
  }
  roots.forEach((root) => asBytes32(root, 'continuity root'));

  return {
    role,
    txHash: txHash.toLowerCase(),
    blockHeight,
    txIndex,
    merkleSiblingCount: siblings.length,
    continuityRootCount: roots.length,
    merkleRoot,
  };
}

function publicPacket(packet: InternalProofPacket): ProofPacketSummary {
  return {
    role: packet.role,
    txHash: packet.txHash,
    blockHeight: packet.blockHeight,
    txIndex: packet.txIndex,
    merkleSiblingCount: packet.merkleSiblingCount,
    continuityRootCount: packet.continuityRootCount,
  };
}

function comparePosition(
  left: ProofPacketSummary,
  right: ProofPacketSummary,
): number {
  return left.blockHeight - right.blockHeight || left.txIndex - right.txIndex;
}

function ctcAmount(value: bigint): string {
  const whole = value / 10n ** 18n;
  const fraction = (value % 10n ** 18n)
    .toString()
    .padStart(18, '0')
    .slice(0, 4)
    .replace(/0+$/, '');
  return `${whole}${fraction ? `.${fraction}` : ''} CTC`;
}

function resultBase(
  engineId: ProofEngineId,
): Pick<
  PreflightResult,
  'engineId' | 'checkedAt' | 'requirements' | 'consequence' | 'boundary'
> {
  const engine = proofEngineById(engineId);
  return {
    engineId,
    checkedAt: new Date().toISOString(),
    requirements: engine.evidence,
    consequence: engine.consequence,
    boundary: engine.boundary,
  };
}

function unavailableResult(
  engineId: ProofEngineId,
  error: UpstreamError,
): PreflightResult {
  return {
    ...resultBase(engineId),
    status: 'upstream_unavailable',
    headline: 'Live preflight is temporarily unavailable',
    summary: `${error.service} could not complete this read-only check. No conclusion was made about the claim.`,
    gates: [
      {
        id: 'upstream',
        label: 'Live read',
        status: 'warning',
        detail: 'Try again when the public testnet service is available.',
      },
    ],
  };
}

async function preflightAave(
  inputs: ProofInputValues,
  context: PreflightContext,
): Promise<PreflightResult> {
  const engineId: ProofEngineId = 'aave-performance';
  const engine = proofEngineById(engineId);
  const wallet = inputs.wallet!;
  const borrowTxHash = inputs.borrowTxHash!;
  const repayTxHash = inputs.repayTxHash!;
  const borrowLogOrdinal = inputs.borrowReceiptLogOrdinal!;
  const repayLogOrdinal = inputs.repayReceiptLogOrdinal!;
  const [adapterDeployed, tip, , borrow, repay] = await Promise.all([
    hasRuntimeCode(engine.deployment.contractAddress, context),
    readChainInfo(3, context),
    checkProofBuilderHealth(context.signal),
    readProofPacket('Borrow', 3, borrowTxHash, context.signal),
    readProofPacket('Repay', 3, repayTxHash, context.signal),
  ]).catch((error: unknown) => {
    context.abort();
    throw error;
  });
  const packets = [borrow, repay];
  const isPublicCase =
    wallet.toLowerCase() === publicAaveCase.wallet.toLowerCase() &&
    borrowTxHash.toLowerCase() === publicAaveCase.borrowTxHash &&
    repayTxHash.toLowerCase() === publicAaveCase.repayTxHash;
  const publicCoordinatesMatch =
    !isPublicCase ||
    (borrow.blockHeight === PUBLIC_AAVE_COORDINATES.borrowBlock &&
      borrow.txIndex === PUBLIC_AAVE_COORDINATES.borrowIndex &&
      repay.blockHeight === PUBLIC_AAVE_COORDINATES.repayBlock &&
      repay.txIndex === PUBLIC_AAVE_COORDINATES.repayIndex);
  const publicOrdinalsMatch =
    borrowLogOrdinal === publicAaveCase.borrowReceiptLogOrdinal &&
    repayLogOrdinal === publicAaveCase.repayReceiptLogOrdinal;
  const chronological = comparePosition(borrow, repay) < 0;
  const attested =
    tip.exists &&
    tip.isAttestation &&
    packets.every((packet) => packet.blockHeight < tip.height);
  const gates: PreflightGate[] = [
    {
      id: 'adapter',
      label: 'Aave specialist deployed',
      status: adapterDeployed ? 'pass' : 'fail',
      detail: adapterDeployed
        ? `${engine.deployment.contractLabel} has runtime code on CC3.`
        : 'The configured adapter has no runtime code at the checked CC3 block.',
    },
    {
      id: 'attestation',
      label: 'Ethereum evidence is attested',
      status: attested ? 'pass' : 'fail',
      detail: tip.exists
        ? `CC3 reports Ethereum attested through block ${tip.height.toLocaleString()}; each candidate block is strictly below that tip.`
        : 'CC3 did not report an Ethereum attestation.',
    },
    {
      id: 'packets',
      label: 'Merkle packets available',
      status: 'pass',
      detail:
        'Both packets reproduce their transaction indices from sibling laterality.',
    },
    {
      id: 'chronology',
      label: 'Borrow precedes Repay',
      status: chronological ? 'pass' : 'fail',
      detail: chronological
        ? `Borrow #${borrow.blockHeight.toLocaleString()}:${borrow.txIndex} precedes Repay #${repay.blockHeight.toLocaleString()}:${repay.txIndex}.`
        : 'The supplied Borrow coordinate does not precede the supplied Repay coordinate.',
    },
    {
      id: 'known-case',
      label: 'Known case coordinates',
      status:
        isPublicCase && publicCoordinatesMatch && publicOrdinalsMatch
          ? 'pass'
          : 'warning',
      detail:
        isPublicCase && publicCoordinatesMatch && publicOrdinalsMatch
          ? 'The supplied values match the repository’s public, independently tested Aave case.'
          : 'This is not the repository’s pinned public case; packet structure can still be checked.',
    },
    {
      id: 'subject',
      label: 'Wallet and event semantics',
      status: 'warning',
      detail: `Pending adapter verification at Borrow log ${borrowLogOrdinal} and Repay log ${repayLogOrdinal}. Preflight has not bound the wallet or classified either receipt event.`,
    },
  ];
  const coordinateFailure =
    !chronological || (isPublicCase && !publicCoordinatesMatch);
  const status = !adapterDeployed
    ? 'not_enforceable'
    : coordinateFailure
      ? 'predicate_mismatch'
      : !attested
        ? 'ready_to_collect'
        : 'ready_to_verify';
  return {
    ...resultBase(engineId),
    status,
    headline:
      status === 'ready_to_verify'
        ? 'Proof bundles are available for adapter verification'
        : status === 'ready_to_collect'
          ? 'Wait for the source blocks to clear the attested tip'
          : 'These coordinates do not pass performance preflight',
    summary:
      status === 'ready_to_verify'
        ? 'The packets are fresh and structurally sound. The deployed adapter—not this router—must decode the receipts before any performance record exists.'
        : 'No performance fact was created. Correct the failed or pending gate before adapter verification.',
    gates,
    source: {
      chainKey: 3,
      latestAttestedHeight: tip.height,
      contractAddress: engine.deployment.contractAddress,
    },
    packets: packets.map(publicPacket),
  };
}

async function preflightOrdering(
  engineId: 'sandwich' | 'fair-exit',
  inputs: ProofInputValues,
  context: PreflightContext,
): Promise<PreflightResult> {
  const engine = proofEngineById(engineId);
  const covenant = await readCovenant(inputs.covenantId!, context);
  if (covenant.operator === ZERO_ADDRESS) {
    return {
      ...resultBase(engineId),
      status: 'not_enforceable',
      headline: 'No enforceable covenant was found',
      summary:
        'This ID does not identify a prospectively opened covenant. Prover will not publish an unverified accusation.',
      gates: [
        {
          id: 'covenant',
          label: 'Pre-existing covenant',
          status: 'fail',
          detail: 'CovenantBook returned no operator for this ID.',
        },
      ],
    };
  }
  if (!SUPPORTED_EVM_CHAIN_KEYS.has(covenant.chainKey)) {
    return {
      ...resultBase(engineId),
      status: 'not_enforceable',
      headline: 'This source chain is outside the MVP router',
      summary:
        'The covenant exists, but this router only generates EVM-V1 proof packets for Ethereum mainnet and Sepolia. No conclusion was made about the claim.',
      gates: [
        {
          id: 'source-chain',
          label: 'Supported EVM source',
          status: 'fail',
          detail: `Source chain key ${covenant.chainKey} is not on the MVP allowlist.`,
        },
      ],
    };
  }

  const rolesAndHashes =
    engineId === 'sandwich'
      ? [
          ['Front-run', inputs.frontTxHash!],
          ['Victim', inputs.victimTxHash!],
          ['Back-run', inputs.backTxHash!],
        ]
      : [
          ['Request A', inputs.requestATxHash!],
          ['Request B', inputs.requestBTxHash!],
          ['Process B', inputs.processBTxHash!],
          ['Process A', inputs.processATxHash!],
        ];
  const [courtDeployed, tip, , ...packets] = await Promise.all([
    hasRuntimeCode(engine.deployment.contractAddress, context),
    readChainInfo(covenant.chainKey, context),
    checkProofBuilderHealth(context.signal),
    ...rolesAndHashes.map(([role, txHash]) =>
      readProofPacket(role, covenant.chainKey, txHash, context.signal),
    ),
  ]).catch((error: unknown) => {
    context.abort();
    throw error;
  });
  const expectedType = engineId === 'sandwich' ? 0 : 1;
  const covered = packets.every(
    (packet) =>
      packet.blockHeight >= covenant.validFromHeight &&
      packet.blockHeight <= covenant.validUntilHeight,
  );
  const attested =
    tip.exists && packets.every((packet) => packet.blockHeight <= tip.height);
  const claimOpen = tip.exists && tip.height <= covenant.claimDeadlineHeight;
  const commonSandwichRoot =
    engineId !== 'sandwich' ||
    (packets[0].merkleRoot === packets[1].merkleRoot &&
      packets[1].merkleRoot === packets[2].merkleRoot);
  const coordinateOrderPass =
    engineId === 'sandwich'
      ? packets[0].blockHeight === packets[1].blockHeight &&
        packets[1].blockHeight === packets[2].blockHeight &&
        commonSandwichRoot &&
        packets[0].txIndex + 1 === packets[1].txIndex &&
        packets[1].txIndex + 1 === packets[2].txIndex
      : packets.every(
          (packet, index) =>
            index === 0 || comparePosition(packets[index - 1], packet) < 0,
        );
  const bondStatus =
    covenant.remainingBond >= covenant.fixedPenalty ? 'pass' : 'warning';
  const gates: PreflightGate[] = [
    {
      id: 'court',
      label: 'Ordering specialist deployed',
      status: courtDeployed ? 'pass' : 'fail',
      detail: courtDeployed
        ? `${engine.deployment.contractLabel} has runtime code on CC3.`
        : 'The configured Ordering Court has no runtime code at the checked block.',
    },
    {
      id: 'covenant',
      label: 'Pre-existing typed covenant',
      status:
        covenant.covenantType === expectedType &&
        covenant.policyHash !== ZERO_BYTES32 &&
        covenant.sourceContract !== ZERO_ADDRESS
          ? 'pass'
          : 'fail',
      detail:
        covenant.covenantType === expectedType
          ? `Operator ${covenant.operator} posted the expected ${engine.shortLabel} covenant.`
          : `The supplied covenant belongs to a different ordering specialist.`,
    },
    {
      id: 'coverage',
      label: 'Transactions inside coverage',
      status: covered ? 'pass' : 'fail',
      detail: `Coverage is inclusive from ${covenant.validFromHeight.toLocaleString()} through ${covenant.validUntilHeight.toLocaleString()}.`,
    },
    {
      id: 'attestation',
      label: 'Source heights attested',
      status: attested ? 'pass' : 'fail',
      detail: tip.exists
        ? `Source chain ${covenant.chainKey} is attested through ${tip.height.toLocaleString()}.`
        : `CC3 has no attested height for source chain ${covenant.chainKey}.`,
    },
    {
      id: 'claim-window',
      label: 'Claim window open',
      status: !tip.exists
        ? 'needs_input'
        : claimOpen && !covenant.bondReleased
          ? 'pass'
          : 'fail',
      detail: covenant.bondReleased
        ? 'The bond has already been released.'
        : !tip.exists
          ? 'Claim-window status is waiting for a valid source attestation.'
          : `Claims remain open through attested height ${covenant.claimDeadlineHeight.toLocaleString()}.`,
    },
    {
      id: 'penalty-range',
      label: 'Court-compatible penalty',
      status: covenant.fixedPenalty <= UINT128_MAX ? 'pass' : 'fail',
      detail:
        covenant.fixedPenalty <= UINT128_MAX
          ? `Fixed penalty: ${ctcAmount(covenant.fixedPenalty)}.`
          : 'The penalty does not fit the bureau ruling value.',
    },
    {
      id: 'bond',
      label: 'Bond damages remaining',
      status: bondStatus,
      detail:
        covenant.remainingBond >= covenant.fixedPenalty
          ? `${ctcAmount(covenant.remainingBond)} remains—enough for one full fixed penalty.`
          : `${ctcAmount(covenant.remainingBond)} remains. A valid ruling can still record a shortfall, but full damages are unavailable.`,
    },
    {
      id: 'ordering-predicate',
      label:
        engineId === 'sandwich'
          ? 'Candidate same-root adjacency'
          : 'Candidate FIFO coordinate order',
      status: coordinateOrderPass ? 'pass' : 'fail',
      detail: coordinateOrderPass
        ? engineId === 'sandwich'
          ? `${packets[0].txIndex} → ${packets[1].txIndex} → ${packets[2].txIndex} is exactly adjacent under one returned Merkle root.`
          : 'request A < request B < process B < process A across the returned packet coordinates.'
        : engineId === 'sandwich'
          ? 'The three coordinates are not exactly adjacent under one block commitment.'
          : 'The four coordinates do not form request A < request B < process B < process A.',
    },
  ];
  const structuralFailure = !coordinateOrderPass;
  const enforceabilityFailure = gates.some(
    (gate) =>
      gate.status === 'fail' &&
      gate.id !== 'ordering-predicate' &&
      gate.id !== 'attestation',
  );
  return {
    ...resultBase(engineId),
    status: enforceabilityFailure
      ? 'not_enforceable'
      : structuralFailure
        ? 'predicate_mismatch'
        : 'ready_to_collect',
    headline: enforceabilityFailure
      ? 'The claim does not pass enforceability preflight'
      : structuralFailure
        ? 'These coordinates do not pass order preflight'
        : !attested
          ? 'The packets are waiting for the source attestation tip'
          : 'Covenant and proof packets pass eligibility preflight',
    summary:
      structuralFailure || enforceabilityFailure
        ? 'No accusation, payout or bureau record was created.'
        : 'Collect the policy parameters, signer or route authorization listed at left. The native court must authenticate the packets, decode the receipts and verify every policy-specific fact.',
    gates,
    source: {
      chainKey: covenant.chainKey,
      latestAttestedHeight: tip.height,
      contractAddress: covenant.sourceContract,
    },
    packets: packets.map(publicPacket),
  };
}

const outcomeLabels = ['OPEN', 'FULFILLED', 'BREACHED', 'DEFAULTED'] as const;

async function preflightPromise(
  engineId: 'rfq-execution' | 'settlement',
  inputs: ProofInputValues,
  context: PreflightContext,
): Promise<PreflightResult> {
  const engine = proofEngineById(engineId);
  const promise = await readPromise(inputs.promiseId!, context);
  if (promise.actor === ZERO_ADDRESS) {
    return {
      ...resultBase(engineId),
      status: 'not_enforceable',
      headline: 'No enforceable promise was found',
      summary:
        'This ID does not identify a prospectively activated promise. Prover will not publish an unverified accusation.',
      gates: [
        {
          id: 'promise',
          label: 'Activated promise',
          status: 'fail',
          detail: 'PromiseBook returned no actor for this ID.',
        },
      ],
    };
  }
  if (!SUPPORTED_EVM_CHAIN_KEYS.has(promise.sourceChainKey)) {
    return {
      ...resultBase(engineId),
      status: 'not_enforceable',
      headline: 'This source chain is outside the MVP router',
      summary:
        'The promise exists, but this router only generates EVM-V1 proof packets for Ethereum mainnet and Sepolia. No conclusion was made about the promise outcome.',
      gates: [
        {
          id: 'source-chain',
          label: 'Supported EVM source',
          status: 'fail',
          detail: `Source chain key ${promise.sourceChainKey} is not on the MVP allowlist.`,
        },
      ],
    };
  }

  const expectedKind = engineId === 'rfq-execution' ? 0 : 1;
  const expectedPolicy =
    engineId === 'rfq-execution' ? RFQ_POLICY_ID : SETTLEMENT_POLICY_ID;
  if (promise.outcome !== 0) {
    return {
      ...resultBase(engineId),
      status: 'already_resolved',
      headline: `Promise already resolved: ${outcomeLabels[promise.outcome]}`,
      summary:
        'PromiseBook already holds a terminal outcome. This router will not create a second claim.',
      gates: [
        {
          id: 'outcome',
          label: 'Open promise',
          status: 'fail',
          detail: `Recorded outcome: ${outcomeLabels[promise.outcome]} at attested height ${promise.resolvedAtAttestedHeight.toLocaleString()}.`,
        },
      ],
    };
  }

  const [courtDeployed, tip] = await Promise.all([
    hasRuntimeCode(engine.deployment.contractAddress, context),
    readChainInfo(promise.sourceChainKey, context),
  ]).catch((error: unknown) => {
    context.abort();
    throw error;
  });
  const typedActivation =
    promise.kind === expectedKind &&
    promise.policyId === expectedPolicy &&
    promise.sourceContract !== ZERO_ADDRESS &&
    promise.termsHash !== ZERO_BYTES32;
  const commonGates: PreflightGate[] = [
    {
      id: 'court',
      label: 'Promise specialist deployed',
      status: courtDeployed ? 'pass' : 'fail',
      detail: courtDeployed
        ? `${engine.deployment.contractLabel} has runtime code on CC3.`
        : 'The configured Promise Court has no runtime code at the checked block.',
    },
    {
      id: 'promise',
      label: 'Prospectively activated promise',
      status: typedActivation ? 'pass' : 'fail',
      detail: typedActivation
        ? `Actor and beneficiary activated the exact source policy at revision ${promise.sourcePolicyRevision}.`
        : 'The stored kind, policy, emitter or activation anchor does not match this specialist.',
    },
    {
      id: 'attestation',
      label: 'Source attestation available',
      status: tip.exists && tip.isAttestation ? 'pass' : 'fail',
      detail: tip.exists
        ? `Source chain ${promise.sourceChainKey} is attested through ${tip.height.toLocaleString()}.`
        : `CC3 has no attestation for source chain ${promise.sourceChainKey}.`,
    },
    {
      id: 'bond',
      label: 'Penalty funded',
      status: promise.bond >= promise.fixedPenalty ? 'pass' : 'fail',
      detail: `${ctcAmount(promise.bond)} bond secures a ${ctcAmount(promise.fixedPenalty)} fixed penalty.`,
    },
  ];
  if (tip.height > promise.proofDeadlineHeight) {
    const canFinalizeDefault =
      typedActivation && tip.exists && tip.isAttestation;
    return {
      ...resultBase(engineId),
      status: canFinalizeDefault
        ? 'default_available'
        : typedActivation
          ? 'ready_to_collect'
          : 'not_enforceable',
      headline: canFinalizeDefault
        ? 'Proof window closed; default finalization is available'
        : typedActivation
          ? 'Default finalization is waiting for a valid source attestation'
          : 'The promise does not pass enforceability preflight',
      summary: canFinalizeDefault
        ? 'Promise Court cannot accept a new event proof after this height. Anyone may finalize the still-open promise as DEFAULTED; that does not claim that no source transaction ever existed.'
        : 'No terminal outcome was created by this preflight.',
      gates: [
        ...commonGates.filter((gate) => gate.id !== 'court'),
        {
          id: 'proof-window',
          label: 'Event proof window',
          status: 'warning',
          detail: `Latest attested height ${tip.height.toLocaleString()} is past deadline ${promise.proofDeadlineHeight.toLocaleString()}.`,
        },
      ],
      source: {
        chainKey: promise.sourceChainKey,
        latestAttestedHeight: tip.height,
        contractAddress: promise.sourceContract,
      },
    };
  }

  const [, packet] = await Promise.all([
    checkProofBuilderHealth(context.signal),
    readProofPacket(
      'Terminal event',
      promise.sourceChainKey,
      inputs.sourceTxHash!,
      context.signal,
    ),
  ]).catch((error: unknown) => {
    context.abort();
    throw error;
  });
  const inEvidenceWindow =
    packet.blockHeight >= promise.validFromHeight &&
    packet.blockHeight <= promise.proofDeadlineHeight;
  const attested =
    tip.exists && tip.isAttestation && packet.blockHeight <= tip.height;
  const late = packet.blockHeight > promise.fulfillmentDeadlineHeight;
  const gates: PreflightGate[] = [
    ...commonGates,
    {
      id: 'proof-window',
      label: 'Evidence inside proof window',
      status: inEvidenceWindow ? 'pass' : 'fail',
      detail: `Evidence must be between ${promise.validFromHeight.toLocaleString()} and ${promise.proofDeadlineHeight.toLocaleString()}, inclusive.`,
    },
    {
      id: 'evidence-attested',
      label: 'Evidence height attested',
      status: attested ? 'pass' : 'fail',
      detail: `Transaction is at source block ${packet.blockHeight.toLocaleString()}; latest attested height is ${tip.height.toLocaleString()}.`,
    },
    {
      id: 'timing',
      label: 'Fulfillment timing',
      status: late ? 'warning' : 'pass',
      detail: late
        ? `The event is after fulfillment deadline ${promise.fulfillmentDeadlineHeight.toLocaleString()}; if relevant, the court classifies lateness as a breach reason.`
        : `The event is no later than fulfillment deadline ${promise.fulfillmentDeadlineHeight.toLocaleString()}.`,
    },
    {
      id: 'log-ordinal',
      label: 'Selected receipt log',
      status: 'warning',
      detail: `Log ordinal ${inputs.receiptLogOrdinal} is supplied; the court must verify its emitter, signature, promise ID, actor and terms.`,
    },
  ];
  const hardFailure = gates.some(
    (gate) =>
      gate.status === 'fail' &&
      gate.id !== 'attestation' &&
      gate.id !== 'evidence-attested',
  );
  const waitingForAttestation = !attested || !tip.exists || !tip.isAttestation;
  return {
    ...resultBase(engineId),
    status: hardFailure ? 'not_enforceable' : 'ready_to_collect',
    headline: hardFailure
      ? 'The event does not pass promise preflight'
      : waitingForAttestation
        ? 'The event is waiting for the source attestation tip'
        : 'Promise and proof packet pass eligibility preflight',
    summary: hardFailure
      ? 'No promise outcome or payout was created.'
      : 'Collect the original committed terms before court verification. The court must still authenticate the packet, decode the exact event and compare every term before classifying fulfillment or breach.',
    gates,
    source: {
      chainKey: promise.sourceChainKey,
      latestAttestedHeight: tip.height,
      contractAddress: promise.sourceContract,
    },
    packets: [publicPacket(packet)],
  };
}

export async function runProofPreflight(
  request: ValidatedPreflightRequest,
  requestSignal?: AbortSignal,
): Promise<PreflightResult> {
  const controller = new AbortController();
  const abortFromRequest = () => controller.abort();
  if (requestSignal?.aborted) controller.abort();
  else
    requestSignal?.addEventListener('abort', abortFromRequest, { once: true });
  const timeout = setTimeout(() => controller.abort(), OVERALL_TIMEOUT_MS);
  try {
    const blockTag = await getSnapshotBlockTag(controller.signal);
    const context: PreflightContext = {
      blockTag,
      signal: controller.signal,
      abort: () => controller.abort(),
    };
    if (request.engineId === 'aave-performance') {
      return await preflightAave(request.inputs, context);
    }
    if (request.engineId === 'sandwich' || request.engineId === 'fair-exit') {
      return await preflightOrdering(request.engineId, request.inputs, context);
    }
    return await preflightPromise(request.engineId, request.inputs, context);
  } catch (error) {
    if (error instanceof UpstreamError) {
      return unavailableResult(request.engineId, error);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
    requestSignal?.removeEventListener('abort', abortFromRequest);
  }
}
