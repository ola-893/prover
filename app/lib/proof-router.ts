import {
  proofEngineById,
  type ProofEngineId,
  type ProofInputKey,
} from '@/lib/proof-engines';

export type ProofInputValues = Partial<Record<ProofInputKey, string>>;

export type GateStatus = 'pass' | 'fail' | 'warning' | 'needs_input';

export interface PreflightGate {
  id: string;
  label: string;
  status: GateStatus;
  detail: string;
}

export type PreflightStatus =
  | 'ready_to_verify'
  | 'ready_to_collect'
  | 'needs_input'
  | 'not_enforceable'
  | 'predicate_mismatch'
  | 'default_available'
  | 'already_resolved'
  | 'upstream_unavailable';

export interface ProofPacketSummary {
  role: string;
  txHash: string;
  blockHeight: number;
  txIndex: number;
  merkleSiblingCount: number;
  continuityRootCount: number;
}

export interface PreflightResult {
  engineId: ProofEngineId;
  status: PreflightStatus;
  headline: string;
  summary: string;
  checkedAt: string;
  gates: PreflightGate[];
  requirements: readonly string[];
  consequence: string;
  boundary: string;
  source?: {
    chainKey: number;
    latestAttestedHeight: number;
    contractAddress?: string;
  };
  packets?: ProofPacketSummary[];
}

interface Classification {
  engineId: ProofEngineId | null;
  confidence: 'high' | 'medium' | 'none';
  reason: string;
}

const keywordGroups: Record<
  ProofEngineId,
  readonly { phrase: string; weight: number }[]
> = {
  sandwich: [
    { phrase: 'sandwich', weight: 8 },
    { phrase: 'front run', weight: 6 },
    { phrase: 'frontrun', weight: 6 },
    { phrase: 'back run', weight: 6 },
    { phrase: 'backrun', weight: 6 },
    { phrase: 'bracketed', weight: 4 },
    { phrase: 'mev', weight: 3 },
    { phrase: 'relay', weight: 2 },
    { phrase: 'swap', weight: 1 },
  ],
  'fair-exit': [
    { phrase: 'fair exit', weight: 8 },
    { phrase: 'fifo', weight: 8 },
    { phrase: 'queue inversion', weight: 7 },
    { phrase: 'exit queue', weight: 6 },
    { phrase: 'processed before', weight: 4 },
    { phrase: 'skipped my withdrawal', weight: 5 },
    { phrase: 'vault', weight: 2 },
    { phrase: 'withdrawal', weight: 1 },
  ],
  'aave-performance': [
    { phrase: 'aave', weight: 8 },
    { phrase: 'loan terms', weight: 7 },
    { phrase: 'better collateral', weight: 6 },
    { phrase: 'repayment history', weight: 6 },
    { phrase: 'credit history', weight: 5 },
    { phrase: 'borrow and repay', weight: 5 },
    { phrase: 'borrow', weight: 2 },
    { phrase: 'repay', weight: 3 },
    { phrase: 'lender', weight: 2 },
  ],
  'rfq-execution': [
    { phrase: 'rfq', weight: 8 },
    { phrase: 'request for quote', weight: 8 },
    { phrase: 'quoted terms', weight: 6 },
    { phrase: 'quote', weight: 4 },
    { phrase: 'execution price', weight: 3 },
    { phrase: 'slippage', weight: 2 },
    { phrase: 'trading desk', weight: 2 },
  ],
  settlement: [
    { phrase: 'settlement', weight: 8 },
    { phrase: 'failed to deliver', weight: 6 },
    { phrase: 'wrong recipient', weight: 5 },
    { phrase: 'short payment', weight: 5 },
    { phrase: 'delivery', weight: 3 },
    { phrase: 'counterparty', weight: 2 },
    { phrase: 'payment', weight: 1 },
  ],
};

const engineOrder: readonly ProofEngineId[] = [
  'sandwich',
  'fair-exit',
  'aave-performance',
  'rfq-execution',
  'settlement',
];

export function classifyProofIntent(raw: string): Classification {
  const normalized = raw
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
  if (!normalized) {
    return {
      engineId: null,
      confidence: 'none',
      reason: 'Describe the outcome or choose one of the specialist routes.',
    };
  }

  const scores = engineOrder.map((engineId) => {
    const matches = keywordGroups[engineId].filter(({ phrase }) =>
      normalized.includes(phrase),
    );
    return {
      engineId,
      score: matches.reduce((total, match) => total + match.weight, 0),
      matches: matches.map((match) => match.phrase),
    };
  });
  scores.sort(
    (left, right) =>
      right.score - left.score ||
      engineOrder.indexOf(left.engineId) - engineOrder.indexOf(right.engineId),
  );

  const winner = scores[0];
  const runnerUp = scores[1];
  if (winner.score === 0) {
    return {
      engineId: null,
      confidence: 'none',
      reason:
        'No deterministic route matched yet. Add the protocol, promise or outcome—or choose a specialist directly.',
    };
  }

  const engine = proofEngineById(winner.engineId);
  const confidence =
    winner.score >= 6 && winner.score - runnerUp.score >= 3 ? 'high' : 'medium';
  return {
    engineId: winner.engineId,
    confidence,
    reason: `Matched ${engine.specialist} from: ${winner.matches.slice(0, 3).join(', ')}. Confirm the route before any eligibility check.`,
  };
}

export function emptyInputs(): ProofInputValues {
  return {};
}
