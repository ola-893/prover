import { cc3Deployment } from '@/lib/deployment';

export type ProofEngineId =
  | 'sandwich'
  | 'fair-exit'
  | 'aave-performance'
  | 'rfq-execution'
  | 'settlement';

export type ProofInputKey =
  | 'wallet'
  | 'covenantId'
  | 'promiseId'
  | 'borrowTxHash'
  | 'repayTxHash'
  | 'borrowReceiptLogOrdinal'
  | 'repayReceiptLogOrdinal'
  | 'frontTxHash'
  | 'victimTxHash'
  | 'backTxHash'
  | 'requestATxHash'
  | 'requestBTxHash'
  | 'processBTxHash'
  | 'processATxHash'
  | 'sourceTxHash'
  | 'receiptLogOrdinal';

export interface ProofInputDefinition {
  key: ProofInputKey;
  label: string;
  placeholder: string;
  kind: 'address' | 'bytes32' | 'integer';
  help: string;
}

export interface ProofEngineDefinition {
  id: ProofEngineId;
  version: string;
  label: string;
  shortLabel: string;
  goal: string;
  mode: 'positive-performance' | 'breach';
  accent: 'orange' | 'blue' | 'lime' | 'violet' | 'teal';
  flagship: boolean;
  specialist: string;
  source: string;
  deployment: {
    network: string;
    contractLabel: string;
    contractAddress: string;
  };
  inputs: readonly ProofInputDefinition[];
  evidence: readonly string[];
  consequence: string;
  boundary: string;
}

const orderingCourt = cc3Deployment.contracts[0];
const aaveAdapter = cc3Deployment.contracts[3];
const promiseCourt = cc3Deployment.promiseContracts[0];

export const publicAaveCase = {
  wallet: '0x5D99551ce4a2c1467aDF632474424E7e22c72C66',
  borrowTxHash:
    '0xbcacb57223f15070dec270cede4eed03deb60ecb117d35d8fe518a66d1c590ff',
  repayTxHash:
    '0x84ea8dcff1eedb9973b8cc950d497f271e56c1d80e172187710721bfd02ba344',
  borrowReceiptLogOrdinal: '4',
  repayReceiptLogOrdinal: '4',
} as const;

export const proofEngines: readonly ProofEngineDefinition[] = [
  {
    id: 'sandwich',
    version: 'ordering-v3',
    label: 'Claim sandwich damages',
    shortLabel: 'Sandwich',
    goal: 'Prove that an authorized victim swap was immediately bracketed by a relay-controlled front-run and back-run.',
    mode: 'breach',
    accent: 'orange',
    flagship: true,
    specialist: 'Sandwich Ordering Court',
    source: 'Ethereum mainnet or Sepolia · MVP source allowlist',
    deployment: {
      network: cc3Deployment.network,
      contractLabel: orderingCourt.label,
      contractAddress: orderingCourt.address,
    },
    inputs: [
      {
        key: 'covenantId',
        label: 'No-sandwich covenant ID',
        placeholder: '0x…64 hex characters',
        kind: 'bytes32',
        help: 'The relay must have opened this covenant before the incident.',
      },
      {
        key: 'frontTxHash',
        label: 'Front-run transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'Expected to be immediately before the victim transaction.',
      },
      {
        key: 'victimTxHash',
        label: 'Victim transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The exact route authorized by the relay.',
      },
      {
        key: 'backTxHash',
        label: 'Back-run transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'Expected to be immediately after the victim transaction.',
      },
    ],
    evidence: [
      'Three authenticated transaction packets from one source block',
      'Merkle indices with exact adjacency: front + 1 = victim, victim + 1 = back',
      'The relay route authorization and policy-bound pool configuration',
      'One qualifying swap event in each successful receipt',
    ],
    consequence:
      'If the court proves the breach, the same ruling credits bond damages and writes the relay’s typed bureau record.',
    boundary:
      'Preflight checks the covenant, window and Merkle order. Only the CC3 court decodes the receipts, verifies the route authorization and issues a ruling.',
  },
  {
    id: 'fair-exit',
    version: 'fifo-v2',
    label: 'Prove a FairExit breach',
    shortLabel: 'FairExit',
    goal: 'Prove that a later vault exit request was completed before an earlier request.',
    mode: 'breach',
    accent: 'blue',
    flagship: true,
    specialist: 'FairExit FIFO Ordering Court',
    source: 'Ethereum mainnet or Sepolia · MVP source allowlist',
    deployment: {
      network: cc3Deployment.network,
      contractLabel: orderingCourt.label,
      contractAddress: orderingCourt.address,
    },
    inputs: [
      {
        key: 'covenantId',
        label: 'FIFO covenant ID',
        placeholder: '0x…64 hex characters',
        kind: 'bytes32',
        help: 'The vault operator must have opened this covenant before the requests.',
      },
      {
        key: 'requestATxHash',
        label: 'Earlier request A',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The earlier, still enforceable exit request.',
      },
      {
        key: 'requestBTxHash',
        label: 'Later request B',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The later exit request.',
      },
      {
        key: 'processBTxHash',
        label: 'B processed first',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The transaction that completed request B.',
      },
      {
        key: 'processATxHash',
        label: 'A processed second',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The transaction that later completed request A.',
      },
    ],
    evidence: [
      'Four authenticated source transactions, including their Merkle positions',
      'Strict history order: request A < request B < process B < process A',
      'Unique, non-cancellable request IDs bound to the covenant policy',
      'The policy-bound processing signer and exact request/processed events',
    ],
    consequence:
      'If the court proves the completed inversion, the same ruling credits bond damages and writes the operator’s typed bureau record.',
    boundary:
      'Preflight checks the covenant, windows and transaction order. Only the CC3 court decodes request IDs, verifies the processing signer and issues a ruling.',
  },
  {
    id: 'aave-performance',
    version: 'aave-usdc-v1',
    label: 'Improve my loan terms',
    shortLabel: 'Aave performance',
    goal: 'Authenticate selected Aave V3 Borrow and Repay facts for a transparent performance profile and experimental lender quote.',
    mode: 'positive-performance',
    accent: 'lime',
    flagship: false,
    specialist: 'Aave Evidence Adapter',
    source: 'Ethereum mainnet · Attestcoin chain key 3',
    deployment: {
      network: cc3Deployment.network,
      contractLabel: aaveAdapter.label,
      contractAddress: aaveAdapter.address,
    },
    inputs: [
      {
        key: 'wallet',
        label: 'Wallet',
        placeholder: '0x…40 hex characters',
        kind: 'address',
        help: 'The subject encoded in the Aave receipt events—not merely tx.from.',
      },
      {
        key: 'borrowTxHash',
        label: 'Borrow transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'A selected Aave V3 Borrow receipt to authenticate.',
      },
      {
        key: 'repayTxHash',
        label: 'Repay transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'A later Aave V3 Repay receipt to authenticate.',
      },
      {
        key: 'borrowReceiptLogOrdinal',
        label: 'Borrow receipt log ordinal',
        placeholder: '4',
        kind: 'integer',
        help: 'Zero-based position of the Borrow event in its receipt.',
      },
      {
        key: 'repayReceiptLogOrdinal',
        label: 'Repay receipt log ordinal',
        placeholder: '4',
        kind: 'integer',
        help: 'Zero-based position of the Repay event in its receipt.',
      },
    ],
    evidence: [
      'Two fresh Attestcoin proof packets from Ethereum mainnet',
      'One exact Aave V3 USDC Borrow event and one later Repay event',
      'Receipt-topic subject and repayer binding performed by the adapter',
      'A narrowly defined self-repayment observation—not a complete credit history',
    ],
    consequence:
      'Verified facts can update a transparent performance vector and produce an explained experimental loan quote.',
    boundary:
      'Packet readiness does not prove loan closure, current balance, timeliness, solvency or an exhaustive liquidation history. The adapter must still decode the authenticated receipts.',
  },
  {
    id: 'rfq-execution',
    version: 'rfq-v4',
    label: 'Enforce an RFQ quote',
    shortLabel: 'RFQ execution',
    goal: 'Prove whether an exact, mutually authorized RFQ was executed on time and on its committed terms.',
    mode: 'breach',
    accent: 'violet',
    flagship: false,
    specialist: 'RFQ Promise Court',
    source: 'Ethereum mainnet or Sepolia · pinned by the promise',
    deployment: {
      network: cc3Deployment.network,
      contractLabel: promiseCourt.label,
      contractAddress: promiseCourt.address,
    },
    inputs: [
      {
        key: 'promiseId',
        label: 'RFQ promise ID',
        placeholder: '0x…64 hex characters',
        kind: 'bytes32',
        help: 'The prospectively activated, beneficiary-authorized promise.',
      },
      {
        key: 'sourceTxHash',
        label: 'RFQ execution transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The transaction containing the terminal RFQExecuted event.',
      },
      {
        key: 'receiptLogOrdinal',
        label: 'Receipt log ordinal',
        placeholder: '0',
        kind: 'integer',
        help: 'Zero-based position of the exact event in the authenticated receipt.',
      },
    ],
    evidence: [
      'An open RFQ promise with the exact supported policy revision',
      'One authenticated RFQExecuted event before the proof deadline',
      'The original quote terms whose hash is committed in the promise',
      'Exact beneficiary, assets, amounts, recipient and timing checks',
    ],
    consequence:
      'The typed outcome releases the bond or credits the fixed penalty to the beneficiary. No bureau record is written while this module remains outside bureau trust.',
    boundary:
      'Preflight proves neither fulfillment nor breach. The CC3 court must authenticate the event and compare every supplied term against the immutable commitment.',
  },
  {
    id: 'settlement',
    version: 'settlement-v4',
    label: 'Prove settlement failure',
    shortLabel: 'Settlement',
    goal: 'Prove whether an exact, mutually authorized settlement released the required asset and amount to the committed recipient.',
    mode: 'breach',
    accent: 'teal',
    flagship: false,
    specialist: 'Settlement Promise Court',
    source: 'Ethereum mainnet or Sepolia · pinned by the promise',
    deployment: {
      network: cc3Deployment.network,
      contractLabel: promiseCourt.label,
      contractAddress: promiseCourt.address,
    },
    inputs: [
      {
        key: 'promiseId',
        label: 'Settlement promise ID',
        placeholder: '0x…64 hex characters',
        kind: 'bytes32',
        help: 'The prospectively activated, beneficiary-authorized promise.',
      },
      {
        key: 'sourceTxHash',
        label: 'Settlement transaction',
        placeholder: '0x…',
        kind: 'bytes32',
        help: 'The transaction containing the terminal SettlementReleased event.',
      },
      {
        key: 'receiptLogOrdinal',
        label: 'Receipt log ordinal',
        placeholder: '0',
        kind: 'integer',
        help: 'Zero-based position of the exact event in the authenticated receipt.',
      },
    ],
    evidence: [
      'An open settlement promise with the exact supported policy revision',
      'One authenticated SettlementReleased event before the proof deadline',
      'The original settlement terms whose hash is committed in the promise',
      'Exact asset, recipient, minimum amount and timing checks',
    ],
    consequence:
      'The typed outcome releases the bond or credits the fixed penalty to the beneficiary. No bureau record is written while this module remains outside bureau trust.',
    boundary:
      'Preflight proves neither fulfillment nor breach. The CC3 court must authenticate the event and compare every supplied term against the immutable commitment.',
  },
] as const;

export function proofEngineById(id: ProofEngineId) {
  const engine = proofEngines.find((candidate) => candidate.id === id);
  if (!engine) throw new Error(`Unknown proof engine: ${id}`);
  return engine;
}

export function isProofEngineId(value: unknown): value is ProofEngineId {
  return (
    typeof value === 'string' &&
    proofEngines.some((engine) => engine.id === value)
  );
}
