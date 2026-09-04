export type ActorKey = 'borrower' | 'relay' | 'vault';

export type EvidenceKind =
  | 'AAVE_BORROW'
  | 'AAVE_REPAY'
  | 'AAVE_SELF_REPAYMENT_OBSERVATION'
  | 'SANDWICH_BREACH'
  | 'FIFO_BREACH';

export type EvidenceMode =
  | 'attestcoin'
  | 'captured-live'
  | 'fixture'
  | 'derived';

export interface PerformanceProfile {
  aaveBorrowFacts: number;
  aaveRepayFacts: number;
  aaveSelfRepaymentObservations: number;
  aaveLiquidationFacts: number;
  liquidationCoverage: 'not-checked';
  sandwichBreaches: number;
  fifoBreaches: number;
  uncompensatedBreaches: number;
  largestObservedBorrowUsdc: number;
  totalSlashedCtc: number;
}

export interface Terms {
  collateralBps: number;
  premiumBps: number;
  maxBorrowUsdc: number;
  minimumBondCtc: number;
  reasons: Array<{
    code: string;
    label: string;
    effect: string;
    tone: 'positive' | 'negative' | 'neutral';
  }>;
}

export interface EvidenceRecord {
  id: string;
  kind: EvidenceKind;
  subject: ActorKey;
  title: string;
  source: string;
  coordinate: string;
  proof: string;
  mode: EvidenceMode;
  visibleAt: number;
  detail: string;
}

export interface DemoStep {
  number: number;
  short: string;
  title: string;
  description: string;
  actor: ActorKey | 'all';
}

export const actors: Record<
  ActorKey,
  {
    name: string;
    role: string;
    address: string;
    accent: string;
  }
> = {
  borrower: {
    name: 'Aave borrower',
    role: 'Ethereum wallet',
    address: '0x5d99…2c66',
    accent: '#b8f34a',
  },
  relay: {
    name: 'Northstar Relay',
    role: 'Bonded execution relay',
    address: '0x4C1A…92B7',
    accent: '#ff9f67',
  },
  vault: {
    name: 'Harbor Exit Vault',
    role: 'Bonded vault operator',
    address: '0xA110…E819',
    accent: '#78bfff',
  },
};

export const demoSteps: DemoStep[] = [
  {
    number: 1,
    short: 'Import',
    title: 'Import Aave facts',
    description:
      'Authenticate one Borrow and one later Repay receipt from Ethereum.',
    actor: 'borrower',
  },
  {
    number: 2,
    short: 'Profile',
    title: 'Build the evidence vector',
    description:
      'Attribute two source facts, then derive one narrowly defined self-repayment observation.',
    actor: 'borrower',
  },
  {
    number: 3,
    short: 'Offer',
    title: 'Reprice a Creditcoin offer',
    description:
      'Experimental Policy V1 applies a bounded benefit and exposes the exact reason code.',
    actor: 'borrower',
  },
  {
    number: 4,
    short: 'Relay bond',
    title: 'Bind a no-sandwich covenant',
    description:
      'The relay locks CTC behind a forward-looking coverage window.',
    actor: 'relay',
  },
  {
    number: 5,
    short: 'Sandwich',
    title: 'Rule on a sandwich',
    description:
      'Three authenticated positions prove front-run < victim < back-run.',
    actor: 'relay',
  },
  {
    number: 6,
    short: 'Vault bond',
    title: 'Bind a FIFO covenant',
    description:
      'The vault operator bonds its promise to process exits in request order.',
    actor: 'vault',
  },
  {
    number: 7,
    short: 'FIFO',
    title: 'Rule on queue inversion',
    description: 'Four positive facts prove request A < B while process B < A.',
    actor: 'vault',
  },
  {
    number: 8,
    short: 'Reprice',
    title: 'Reprice every future promise',
    description:
      'Limits, premiums and minimum bonds update from the same public record.',
    actor: 'all',
  },
];

export const evidenceRecords: EvidenceRecord[] = [
  {
    id: '0xbcac…c590ff',
    kind: 'AAVE_BORROW',
    subject: 'borrower',
    title: 'Debt opened · 90,000 USDC',
    source: 'Aave V3 · Ethereum mainnet',
    coordinate: '#25,854,707 · 0xbcac…c590ff',
    proof: 'fresh Attestcoin proof required',
    mode: 'fixture',
    visibleAt: 1,
    detail:
      'Debt owner is decoded from indexed onBehalfOf—not inferred from tx.from.',
  },
  {
    id: '0x84ea…ba344',
    kind: 'AAVE_REPAY',
    subject: 'borrower',
    title: 'Self-funded debt reduction · 90,000.055729 USDC',
    source: 'Aave V3 · Ethereum mainnet',
    coordinate: '#25,854,747 · 0x84ea…ba344',
    proof: 'fresh Attestcoin proof required',
    mode: 'fixture',
    visibleAt: 1,
    detail:
      'Repay.user and Repay.repayer both resolve to the same wallet in this source event.',
  },
  {
    id: '0xf11e…77c2',
    kind: 'AAVE_SELF_REPAYMENT_OBSERVATION',
    subject: 'borrower',
    title: 'Self-repayment observation',
    source: 'Performance Bureau',
    coordinate: '40 authenticated source blocks apart',
    proof: 'derived from two authenticated facts',
    mode: 'derived',
    visibleAt: 2,
    detail:
      'Derived from an authenticated Borrow plus a later same-address Repay for the same reserve and a same-or-larger amount. It does not prove loan closure, current balance, timeliness or complete history.',
  },
  {
    id: '0x19d4…41a0',
    kind: 'SANDWICH_BREACH',
    subject: 'relay',
    title: 'No-sandwich covenant breached',
    source: 'Ordering Court · Sepolia',
    coordinate: '#7,918,441 · 41 < 42 < 43',
    proof: 'three transaction proofs',
    mode: 'fixture',
    visibleAt: 5,
    detail:
      'The product fixture uses a fixed 50 CTC penalty; no invented ETH/CTC price.',
  },
  {
    id: '0x771a…be04',
    kind: 'FIFO_BREACH',
    subject: 'vault',
    title: 'FIFO exit covenant breached',
    source: 'Ordering Court · Sepolia',
    coordinate: 'request 7 < 8 · process 8 < 7',
    proof: 'four transaction proofs',
    mode: 'fixture',
    visibleAt: 7,
    detail:
      'Completed reverse processing is positive evidence; no pending-state claim is needed.',
  },
];

export const emptyProfile: PerformanceProfile = {
  aaveBorrowFacts: 0,
  aaveRepayFacts: 0,
  aaveSelfRepaymentObservations: 0,
  aaveLiquidationFacts: 0,
  liquidationCoverage: 'not-checked',
  sandwichBreaches: 0,
  fifoBreaches: 0,
  uncompensatedBreaches: 0,
  largestObservedBorrowUsdc: 0,
  totalSlashedCtc: 0,
};

export function profileAt(actor: ActorKey, step: number): PerformanceProfile {
  const profile = { ...emptyProfile };

  if (actor === 'borrower' && step >= 2) {
    profile.aaveBorrowFacts = 1;
    profile.aaveRepayFacts = 1;
    profile.aaveSelfRepaymentObservations = 1;
    profile.largestObservedBorrowUsdc = 90_000;
  }

  if (actor === 'relay' && step >= 5) {
    profile.sandwichBreaches = 1;
    profile.totalSlashedCtc = 50;
  }

  if (actor === 'vault' && step >= 7) {
    profile.fifoBreaches = 1;
    profile.totalSlashedCtc = 50;
  }

  return profile;
}

export function termsFor(profile: PerformanceProfile): Terms {
  const hasSelfRepaymentObservation = profile.aaveSelfRepaymentObservations > 0;
  const breaches = profile.sandwichBreaches + profile.fifoBreaches;
  const collateralBps = clamp(
    15_000 -
      (hasSelfRepaymentObservation ? 500 : 0) +
      profile.aaveLiquidationFacts * 1_500 +
      breaches * 500,
    10_000,
    20_000,
  );
  const capacity = Math.min(
    100 +
      (hasSelfRepaymentObservation
        ? profile.largestObservedBorrowUsdc / 100
        : 0),
    1_000,
  );
  const limitPenaltyBps = Math.min(
    profile.aaveLiquidationFacts * 2_500 + breaches * 1_000,
    7_500,
  );
  const maxBorrowUsdc = Math.floor(
    (capacity * (10_000 - limitPenaltyBps)) / 10_000,
  );
  const premiumBps = Math.min(
    50 + breaches * 100 + profile.uncompensatedBreaches * 100,
    2_000,
  );
  const minimumBondCtc =
    (100 *
      (10_000 + breaches * 5_000 + profile.uncompensatedBreaches * 5_000)) /
    10_000;
  const reasons: Terms['reasons'] = [];

  if (hasSelfRepaymentObservation) {
    reasons.push({
      code: 'AAVE_SELF_REPAYMENT_OBSERVATION',
      label:
        'Authenticated Borrow plus later same-address Repay of a same-or-larger amount',
      effect:
        '−5 percentage points collateral · +1% of observed amount, $1,000 total limit cap',
      tone: 'positive',
    });
  }
  if (profile.aaveLiquidationFacts > 0) {
    reasons.push({
      code: 'AAVE_LIQUIDATION_PROOF_SURCHARGE',
      label: `${profile.aaveLiquidationFacts} imported Aave liquidation proof${profile.aaveLiquidationFacts === 1 ? '' : 's'}`,
      effect: '+15 percentage points collateral · −25% capacity per proof',
      tone: 'negative',
    });
  }
  if (profile.sandwichBreaches > 0) {
    reasons.push({
      code: 'SANDWICH_BREACH_SURCHARGE',
      label: '1 compensated ordering breach',
      effect: '+1.00% premium · +50 CTC bond',
      tone: 'negative',
    });
  }
  if (profile.fifoBreaches > 0) {
    reasons.push({
      code: 'FIFO_BREACH_SURCHARGE',
      label: '1 compensated queue breach',
      effect: '+1.00% premium · +50 CTC bond',
      tone: 'negative',
    });
  }
  if (reasons.length === 0) {
    reasons.push({
      code: 'BASELINE_NO_VERIFIED_HISTORY',
      label: 'No imported performance facts',
      effect: 'baseline terms',
      tone: 'neutral',
    });
  }

  return { collateralBps, premiumBps, maxBorrowUsdc, minimumBondCtc, reasons };
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}
