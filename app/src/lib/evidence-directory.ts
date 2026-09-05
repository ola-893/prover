import {
  Contract,
  Interface,
  JsonRpcProvider,
  getAddress,
  id,
  isAddress,
  toBeHex,
} from 'ethers';
import { cc3Deployment } from '@/lib/deployment';

const CC3_RPC_URL = 'https://rpc.cc3-testnet.creditcoin.network';
const ORDERING_COURT = cc3Deployment.contracts[0].address;
const PERFORMANCE_BUREAU = cc3Deployment.contracts[2].address;
const AAVE_ADAPTER = cc3Deployment.contracts[3].address;
const EVIDENCE_SBT = cc3Deployment.contracts[4].address;
const PERFORMANCE_BUREAU_DEPLOYMENT_BLOCK = 5_393_466;
const EVIDENCE_SBT_DEPLOYMENT_BLOCK = 5_413_260;
const LOG_BLOCK_SPAN = 10_000;

const BUREAU_ABI = [
  'function profileOf(address subject) view returns (uint32 aaveBorrowFacts, uint32 aaveRepayFacts, uint32 aaveSelfRepaymentObservations, uint32 aaveLiquidationFacts, uint32 sandwichBreaches, uint32 fifoBreaches, uint32 uncompensatedBreaches, uint128 largestObservedBorrowUsdc, uint128 totalSlashedCtc)',
  'function termsOf(address subject) view returns (uint16 collateralBps, uint16 premiumBps, uint32 bondMultiplierBps, uint128 maxBorrowUsdc, uint128 minimumBondCtc, uint256 reasonFlags)',
  'event EvidenceRecorded(bytes32 indexed evidenceId, address indexed subject, address indexed reporter, uint8 kind, uint128 value, bool uncompensated)',
] as const;

const ORDERING_COURT_ABI = [
  'function rulingCount() view returns (uint256)',
  'function rulingAt(uint256 index) view returns (bytes32 rulingId, (bytes32 covenantId, uint8 kind, address operator, address affectedUser, address beneficiary, uint64 breachHeight, uint64 ruledAt, uint256 paid, uint256 shortfall, bool bureauRecorded) ruling)',
] as const;

const SBT_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function snapshotOf(bytes32 evidenceId) view returns (address subject, address claimant, address beneficiary, address reporter, address court, bytes32 covenantId, bytes32 policyId, bytes32 engineSchemaId, bytes32 sourceTransactionEvidenceId, bytes32 sourceEndTransactionEvidenceId, uint8 kind, uint8 verdict, uint64 recordedAt, uint64 ruledAt, uint64 sourceChainKey, uint64 sourceBlockHeight, uint64 sourceTxIndex, uint64 sourceReceiptLogOrdinal, uint64 sourceEndBlockHeight, uint64 sourceEndTxIndex, uint64 sourceEndReceiptLogOrdinal, uint128 evidenceValue, uint128 damagesPaid, uint256 damagesShortfall, bool uncompensated, bool sourceTxIndexKnown, bool sourceEndCoordinateKnown)',
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)',
] as const;

export type EvidenceRole = 'borrower' | 'relayer' | 'vault-operator' | 'validator';

export const evidenceRoles: readonly {
  id: EvidenceRole;
  label: string;
  description: string;
}[] = [
  {
    id: 'borrower',
    label: 'Borrower',
    description: 'Selected Aave repayment observations and Policy V1 terms.',
  },
  {
    id: 'relayer',
    label: 'Relayer',
    description: 'Recorded no-sandwich rulings for this operator.',
  },
  {
    id: 'vault-operator',
    label: 'Vault operator',
    description: 'Recorded FairExit FIFO-inversion rulings for this operator.',
  },
  {
    id: 'validator',
    label: 'Validator',
    description: 'No validator-specific proof engine is deployed yet.',
  },
];

export interface EvidenceProfile {
  aaveBorrowFacts: number;
  aaveRepayFacts: number;
  aaveSelfRepaymentObservations: number;
  aaveLiquidationFacts: number;
  sandwichBreaches: number;
  fifoBreaches: number;
  uncompensatedBreaches: number;
  largestObservedBorrowUsdc: bigint;
  totalSlashedCtc: bigint;
}

export interface PolicyTerms {
  collateralBps: number;
  premiumBps: number;
  bondMultiplierBps: number;
  maxBorrowUsdc: bigint;
  minimumBondCtc: bigint;
  reasonFlags: bigint;
}

export interface StandingReport {
  address: string;
  profile: EvidenceProfile;
  terms: PolicyTerms;
  evidenceCardCount: bigint;
}

export interface RoleStanding {
  label: string;
  detail: string;
  tone: 'positive' | 'negative' | 'neutral';
  hasVerifiedEvidence: boolean;
}

export interface MintedEvidenceCard {
  evidenceId: string;
  tokenId: bigint;
  holder: string;
  subject: string;
  claimant: string;
  kind: number;
  verdict: number;
  recordedAt: number;
  damagesPaid: bigint;
  uncompensated: boolean;
}

export interface CanonicalBorrowerObservation {
  evidenceId: string;
  subject: string;
  observedAmount: bigint;
  recordedInBlock: number;
  transactionHash: string;
}

export interface CanonicalOrderingRuling {
  rulingId: string;
  covenantId: string;
  kind: 'sandwich' | 'fifo';
  operator: string;
  affectedUser: string;
  beneficiary: string;
  breachHeight: number;
  ruledAt: number;
  paid: bigint;
  shortfall: bigint;
}

export interface CanonicalEvidenceDirectory {
  snapshotBlock: number;
  borrowerObservations: CanonicalBorrowerObservation[];
  sandwichRulings: CanonicalOrderingRuling[];
  fifoRulings: CanonicalOrderingRuling[];
}

let provider: JsonRpcProvider | null = null;

function cc3Provider() {
  if (!provider) provider = new JsonRpcProvider(CC3_RPC_URL);
  return provider;
}

function asNumber(value: unknown) {
  return Number(value);
}

function asBigInt(value: unknown) {
  return BigInt(value as bigint);
}

function resultValues(result: unknown) {
  return Array.from(result as ArrayLike<unknown>);
}

async function readLogsInRanges(
  address: string,
  topics: Array<string | null>,
  fromBlock: number,
  toBlock: number,
) {
  if (fromBlock > toBlock) return [];

  const rpc = cc3Provider();
  const logs = [] as Awaited<ReturnType<typeof rpc.getLogs>>;
  for (let start = fromBlock; start <= toBlock; start += LOG_BLOCK_SPAN) {
    const end = Math.min(start + LOG_BLOCK_SPAN - 1, toBlock);
    logs.push(
      ...(await rpc.getLogs({
        address,
        topics,
        fromBlock: start,
        toBlock: end,
      })),
    );
  }
  return logs;
}

function chunk<T>(items: readonly T[], size: number) {
  const chunks: T[][] = [];
  for (let offset = 0; offset < items.length; offset += size) {
    chunks.push([...items.slice(offset, offset + size)]);
  }
  return chunks;
}

export function normalizeAddress(address: string) {
  if (!isAddress(address.trim())) throw new Error('Enter a valid 0x wallet address.');
  return getAddress(address.trim());
}

export function roleStanding(report: StandingReport, role: EvidenceRole): RoleStanding {
  const { profile } = report;

  if (role === 'validator') {
    return {
      label: 'No validator proof engine yet',
      detail:
        'Prover does not currently attest validator performance. A missing record is not a positive result.',
      tone: 'neutral',
      hasVerifiedEvidence: false,
    };
  }

  if (role === 'borrower') {
    if (profile.aaveSelfRepaymentObservations > 0) {
      return {
        label: 'Verified repayment observation',
        detail: `${profile.aaveSelfRepaymentObservations} selected Aave self-repayment observation${profile.aaveSelfRepaymentObservations === 1 ? '' : 's'} recorded. This is not a complete credit history.`,
        tone: 'positive',
        hasVerifiedEvidence: true,
      };
    }
    return {
      label: 'No verified borrower observation',
      detail:
        'No selected Aave self-repayment observation is recorded for this address. That does not establish repayment absence or bad standing.',
      tone: 'neutral',
      hasVerifiedEvidence: false,
    };
  }

  if (role === 'relayer') {
    if (profile.sandwichBreaches > 0) {
      return {
        label: 'Sandwich breach recorded',
        detail: `${profile.sandwichBreaches} no-sandwich ruling${profile.sandwichBreaches === 1 ? '' : 's'} is recorded against this operator.`,
        tone: 'negative',
        hasVerifiedEvidence: true,
      };
    }
    return {
      label: 'No recorded sandwich breach',
      detail:
        'Prover has no supported breach record for this address. It does not certify trustworthy relay behavior.',
      tone: 'neutral',
      hasVerifiedEvidence: false,
    };
  }

  if (profile.fifoBreaches > 0) {
    return {
      label: 'FairExit breach recorded',
      detail: `${profile.fifoBreaches} queue-inversion ruling${profile.fifoBreaches === 1 ? '' : 's'} is recorded against this operator.`,
      tone: 'negative',
      hasVerifiedEvidence: true,
    };
  }

  return {
    label: 'No recorded FIFO breach',
    detail:
      'Prover has no supported FairExit breach record for this address. It does not certify fair queue operation.',
    tone: 'neutral',
    hasVerifiedEvidence: false,
  };
}

export async function readStanding(address: string): Promise<StandingReport> {
  const subject = normalizeAddress(address);
  const rpc = cc3Provider();
  const bureau = new Contract(PERFORMANCE_BUREAU, BUREAU_ABI, rpc);
  const sbt = new Contract(EVIDENCE_SBT, SBT_ABI, rpc);

  const [rawProfile, rawTerms, evidenceCardCount] = await Promise.all([
    bureau.profileOf(subject),
    bureau.termsOf(subject),
    sbt.balanceOf(subject),
  ]);
  const profile = resultValues(rawProfile);
  const terms = resultValues(rawTerms);

  return {
    address: subject,
    profile: {
      aaveBorrowFacts: asNumber(profile[0]),
      aaveRepayFacts: asNumber(profile[1]),
      aaveSelfRepaymentObservations: asNumber(profile[2]),
      aaveLiquidationFacts: asNumber(profile[3]),
      sandwichBreaches: asNumber(profile[4]),
      fifoBreaches: asNumber(profile[5]),
      uncompensatedBreaches: asNumber(profile[6]),
      largestObservedBorrowUsdc: asBigInt(profile[7]),
      totalSlashedCtc: asBigInt(profile[8]),
    },
    terms: {
      collateralBps: asNumber(terms[0]),
      premiumBps: asNumber(terms[1]),
      bondMultiplierBps: asNumber(terms[2]),
      maxBorrowUsdc: asBigInt(terms[3]),
      minimumBondCtc: asBigInt(terms[4]),
      reasonFlags: asBigInt(terms[5]),
    },
    evidenceCardCount: asBigInt(evidenceCardCount),
  };
}

/**
 * Reads the canonical public evidence surfaces at one CC3 block snapshot.
 * Receipt minting is intentionally excluded: a portable ERC-5192 receipt is optional,
 * while the bureau record or court ruling is the authoritative public result.
 */
export async function readCanonicalEvidenceDirectory(): Promise<CanonicalEvidenceDirectory> {
  const rpc = cc3Provider();
  const snapshotBlock = await rpc.getBlockNumber();
  const bureau = new Contract(PERFORMANCE_BUREAU, BUREAU_ABI, rpc);
  const court = new Contract(ORDERING_COURT, ORDERING_COURT_ABI, rpc);
  const evidenceRecordedTopic = id(
    'EvidenceRecorded(bytes32,address,address,uint8,uint128,bool)',
  );

  const [borrowerLogs, rawRulingCount] = await Promise.all([
    readLogsInRanges(
      PERFORMANCE_BUREAU,
      [evidenceRecordedTopic, null, null, null],
      PERFORMANCE_BUREAU_DEPLOYMENT_BLOCK,
      snapshotBlock,
    ),
    court.rulingCount({ blockTag: snapshotBlock }),
  ]);

  const bureauInterface = new Interface(BUREAU_ABI);
  const borrowerObservations = borrowerLogs.flatMap((log) => {
    const event = bureauInterface.parseLog(log);
    if (!event) return [];

    const kind = asNumber(event.args.kind);
    const reporter = getAddress(event.args.reporter).toLowerCase();
    if (kind !== 2 || reporter !== AAVE_ADAPTER.toLowerCase()) return [];

    return [
      {
        evidenceId: event.args.evidenceId.toLowerCase(),
        subject: getAddress(event.args.subject),
        observedAmount: asBigInt(event.args.value),
        recordedInBlock: log.blockNumber,
        transactionHash: log.transactionHash,
      } satisfies CanonicalBorrowerObservation,
    ];
  });

  const rulingCount = asNumber(rawRulingCount);
  const indexes = Array.from({ length: rulingCount }, (_, index) => index);
  const allRulings: CanonicalOrderingRuling[] = [];
  for (const indexesInPage of chunk(indexes, 20)) {
    const page = await Promise.all(
      indexesInPage.map(async (index) => {
        const result = resultValues(await court.rulingAt(index, { blockTag: snapshotBlock }));
        return {
          rulingId: (result[0] as string).toLowerCase(),
          ruling: resultValues(result[1]),
        };
      }),
    );

    for (const { rulingId, ruling } of page) {
      const kind = asNumber(ruling[1]);
      const bureauRecorded = Boolean(ruling[9]);
      if (!bureauRecorded || (kind !== 0 && kind !== 1)) continue;
      allRulings.push({
        rulingId,
        covenantId: (ruling[0] as string).toLowerCase(),
        kind: kind === 0 ? 'sandwich' : 'fifo',
        operator: getAddress(ruling[2] as string),
        affectedUser: getAddress(ruling[3] as string),
        beneficiary: getAddress(ruling[4] as string),
        breachHeight: asNumber(ruling[5]),
        ruledAt: asNumber(ruling[6]),
        paid: asBigInt(ruling[7]),
        shortfall: asBigInt(ruling[8]),
      });
    }
  }

  return {
    snapshotBlock,
    borrowerObservations: borrowerObservations.sort(
      (left, right) => right.recordedInBlock - left.recordedInBlock,
    ),
    sandwichRulings: allRulings
      .filter((ruling) => ruling.kind === 'sandwich')
      .sort((left, right) => right.ruledAt - left.ruledAt),
    fifoRulings: allRulings
      .filter((ruling) => ruling.kind === 'fifo')
      .sort((left, right) => right.ruledAt - left.ruledAt),
  };
}

/**
 * Reads only report cards actually minted by the deployed ERC-5192 contract.
 * The terminal PerformanceBureau record remains canonical; this is its portable display layer.
 */
export async function readMintedEvidenceCards(): Promise<MintedEvidenceCard[]> {
  const rpc = cc3Provider();
  const transferTopic = id('Transfer(address,address,uint256)');
  const logs = await rpc.getLogs({
    address: EVIDENCE_SBT,
    topics: [transferTopic],
    fromBlock: EVIDENCE_SBT_DEPLOYMENT_BLOCK,
    toBlock: 'latest',
  });
  const transferInterface = new Interface(SBT_ABI);
  const sbt = new Contract(EVIDENCE_SBT, SBT_ABI, rpc);

  const parsed = logs.flatMap((log) => {
    const event = transferInterface.parseLog(log);
    if (!event || event.args.from !== '0x0000000000000000000000000000000000000000') return [];
    return [
      {
        tokenId: BigInt(event.args.tokenId),
        holder: getAddress(event.args.to),
      },
    ];
  });

  const cards = await Promise.all(
    parsed.map(async ({ tokenId, holder }) => {
      const evidenceId = toBeHex(tokenId, 32).toLowerCase();
      const snapshot = resultValues(await sbt.snapshotOf(evidenceId));
      return {
        evidenceId,
        tokenId,
        holder,
        subject: getAddress(snapshot[0] as string),
        claimant: getAddress(snapshot[1] as string),
        kind: asNumber(snapshot[10]),
        verdict: asNumber(snapshot[11]),
        recordedAt: asNumber(snapshot[12]),
        damagesPaid: asBigInt(snapshot[22]),
        uncompensated: Boolean(snapshot[24]),
      } satisfies MintedEvidenceCard;
    }),
  );

  return cards.sort((left, right) => right.recordedAt - left.recordedAt);
}

export function formatUsdc(value: bigint) {
  const whole = value / 1_000_000n;
  const fraction = (value % 1_000_000n).toString().padStart(6, '0').slice(0, 2).replace(/0+$/, '');
  return `${whole.toLocaleString()}${fraction ? `.${fraction}` : ''} USDC`;
}

export function formatCtc(value: bigint) {
  const whole = value / 10n ** 18n;
  const fraction = (value % 10n ** 18n).toString().padStart(18, '0').slice(0, 2).replace(/0+$/, '');
  return `${whole.toLocaleString()}${fraction ? `.${fraction}` : ''} CTC`;
}

export function shortEvidenceAddress(address: string) {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}
