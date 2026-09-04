import { EvidenceScenario, ValueProp } from '../types';

export const EVIDENCE_SCENARIOS: EvidenceScenario[] = [
  {
    id: 'sandwich-arbitrum',
    category: 'VIOLATION',
    title: 'Atomic Sandwich Attack on Arbitrum Pool',
    subtitle: 'Searcher node breached verified zero-MEV execution covenant',
    chain: 'Arbitrum One',
    targetProtocol: 'Camelot / Uniswap v3 Pool',
    bondedCollateral: '$1,250,000 USDC',
    slashedAmount: '$420,000 USDC',
    victimRecovery: '$388,500 USDC',
    blockNumber: 218491024,
    txHash: '0x8f2a93c7210bdf...e481c9',
    attackerAddress: '0x49fA...91B2 (MEV Searcher)',
    victimAddress: '0x32A8...704C (Retail Swapper)',
    violationRule: 'RULE_MEMPOOL_FIFO_NO_SANDWICH [EIP-7540-REV]',
    evidenceProofType: 'ZK-STARK Reordering Witness',
    summary: 'Searcher injected a front-run buy order (tx #14) and back-run sell order (tx #16) surrounding victim swap (tx #15), extracting $48.2K slippage in direct violation of bonded fair-ordering commitment.',
    mempoolTrace: [
      {
        step: 1,
        action: 'Frontrun Ingestion',
        timestampOffset: '+0.000s',
        gasPrice: '38.4 Gwei',
        status: 'BREACH',
        detail: 'Tx 0x8f2a: 180 ETH swap into USDC pool artificially raising spot price by 1.84%.'
      },
      {
        step: 2,
        action: 'Victim Order Execution',
        timestampOffset: '+0.012s',
        gasPrice: '12.1 Gwei',
        status: 'INSPECTION',
        detail: 'Tx 0x7c91: Victim swap executed at max slippage tolerance threshold.'
      },
      {
        step: 3,
        action: 'Backrun Liquidation',
        timestampOffset: '+0.018s',
        gasPrice: '42.0 Gwei',
        status: 'BREACH',
        detail: 'Tx 0x9a10: Searcher dumps USDC back for 194.2 ETH, netting $48,290 extracted profit.'
      },
      {
        step: 4,
        action: 'Autonomous Slashing',
        timestampOffset: '+0.440s',
        gasPrice: 'Contract Call',
        status: 'SETTLED',
        detail: 'Prover contract verifies Merkle exclusion proof. $420,000 slash executed; victim auto-compensated.'
      }
    ],
    zkProofMetrics: {
      constraints: '1,428,912 R1CS',
      proverTimeMs: 382,
      verifierGas: '184,210 gas',
      circuit: 'circom-fifo-order-v2.1',
      hashRoot: '0xd79a401b...99f4301a'
    }
  },
  {
    id: 'fifo-sequencer',
    category: 'VIOLATION',
    title: 'FIFO Block Queue Inversion',
    subtitle: 'Sequencer reordered pending order flow to prioritize internal liquidity pool',
    chain: 'Base / OP Stack',
    targetProtocol: 'Aerodrome Slipstream',
    bondedCollateral: '$2,000,000 OP',
    slashedAmount: '$850,000 OP',
    victimRecovery: '$790,000 OP',
    blockNumber: 19482019,
    txHash: '0x3c18b74a...80f2d1',
    attackerAddress: '0x10E4...002A (Sequencer Relay)',
    victimAddress: '0x88f1...19a4 (Arbitrage Contract)',
    violationRule: 'RULE_SEQUENCER_LATENCY_SLA [EIP-4337-ORD]',
    evidenceProofType: 'P2P Gossip Timestamp Witness',
    summary: 'A delegated sequencer held victim transaction for 210ms in staging buffer to allow sister market maker to adjust delta hedge, causing $112,000 execution degradation.',
    mempoolTrace: [
      {
        step: 1,
        action: 'P2P Gossip Arrival',
        timestampOffset: '+0.000s',
        gasPrice: '14.2 Gwei',
        status: 'INSPECTION',
        detail: 'Tx registered across 48 independent peer nodes at T_0 = 1714829102.148.'
      },
      {
        step: 2,
        action: 'Sequencer Stall Detected',
        timestampOffset: '+0.210s',
        gasPrice: 'Holding Buffer',
        status: 'BREACH',
        detail: 'Tx delayed past 35ms SLA window. 4 concurrent transactions inserted ahead of queue.'
      },
      {
        step: 3,
        action: 'Cryptographic Attestation',
        timestampOffset: '+0.520s',
        gasPrice: 'Zero-Knowledge',
        status: 'VERIFIED',
        detail: 'Threshold signature set from 36 validator witness nodes confirmed intentional queue stall.'
      },
      {
        step: 4,
        action: 'Bond Penalty Slashing',
        timestampOffset: '+1.100s',
        gasPrice: 'Contract Call',
        status: 'SETTLED',
        detail: '$850,000 OP slashed from sequencer bond deposit and routed to Protocol Insurance Reserve.'
      }
    ],
    zkProofMetrics: {
      constraints: '2,109,400 R1CS',
      proverTimeMs: 440,
      verifierGas: '215,800 gas',
      circuit: 'sequencer-attest-halo2',
      hashRoot: '0x4ea88102...bc30182f'
    }
  },
  {
    id: 'aave-self-repayment',
    category: 'POSITIVE_PERFORMANCE',
    title: 'Aave V3 Liquidation Shield Self-Repayment',
    subtitle: 'Automated keeper provably safeguarded $4.8M debt position before liquidation threshold',
    chain: 'Ethereum Mainnet',
    targetProtocol: 'Aave v3 Core Market',
    bondedCollateral: '$500,000 USDC',
    slashedAmount: '$0 (100% Compliant)',
    victimRecovery: '+$24,500 Keeper Yield Bonus',
    blockNumber: 19842109,
    txHash: '0x17d9830f...aa92c8',
    attackerAddress: 'N/A (Compliant Automation)',
    victimAddress: '0x712C...B801 (Institutional Vault)',
    violationRule: 'GUARANTEE_HEALTH_FACTOR_DEFENSE [AAVE-SHIELD]',
    evidenceProofType: 'ZK State Transition Attestation',
    summary: 'Keeper bot executed flash-repay when Health Factor dropped to 1.042, avoiding liquidation penalty fees and fulfilling bonded covenant.',
    mempoolTrace: [
      {
        step: 1,
        action: 'Oracle Price Drop',
        timestampOffset: '+0.000s',
        gasPrice: 'Chainlink Heartbeat',
        status: 'INSPECTION',
        detail: 'ETH/USD oracle update lowered collateral ratio; Health Factor touched 1.042.'
      },
      {
        step: 2,
        action: 'Automated Flash Repay',
        timestampOffset: '+0.014s',
        gasPrice: '52.0 Gwei',
        status: 'VERIFIED',
        detail: 'Keeper borrowed 2,400,000 USDC via Balancer flash loan, paid down debt, restored HF to 1.35.'
      },
      {
        step: 3,
        action: 'Proof of Compliant SLA',
        timestampOffset: '+0.120s',
        gasPrice: 'Zero-Knowledge',
        status: 'VERIFIED',
        detail: 'Prover validates sub-block compliance timestamp and zero liquidation slippage incurred.'
      },
      {
        step: 4,
        action: 'Performance Credit Issued',
        timestampOffset: '+0.600s',
        gasPrice: 'Contract Call',
        status: 'SETTLED',
        detail: 'Keeper receives $24,500 protocol rebate; bond reputation tier elevated to Grade AAA.'
      }
    ],
    zkProofMetrics: {
      constraints: '984,200 R1CS',
      proverTimeMs: 290,
      verifierGas: '162,100 gas',
      circuit: 'aave-shield-snark-v1',
      hashRoot: '0x12bb9401...88dc2107'
    }
  }
];

export const VALUE_PROPS: ValueProp[] = [
  {
    number: '01',
    tag: 'CROSS-CHAIN WITNESSING',
    title: 'Zero-Knowledge State Attestation',
    description: 'Cryptographically verify state transitions and transaction inclusions across Ethereum, Arbitrum, Monad, and Solana without relying on centralized multi-sig oracles.',
    accentDetail: 'Sub-second consensus light-client proofs',
    specCode: 'PRV_SPEC_ZKWITNESS_EIP7540'
  },
  {
    number: '02',
    tag: 'FORENSIC SEQUENCING',
    title: 'Mempool & FIFO Breach Detection',
    description: 'Reconstruct microsecond ordering violations, front-running sandwiches, and validator queue tampering via deterministic gossip receipts and execution traces.',
    accentDetail: 'Deterministic microsecond timestamp proofs',
    specCode: 'PRV_SPEC_MEMPOOL_TRACE_V2'
  },
  {
    number: '03',
    tag: 'PROGRAMMATIC SETTLEMENT',
    title: 'Autonomous Collateral Slashing',
    description: 'When cryptographic fraud is proven, bonded smart contracts instantly forfeit and disburse staked funds to affected liquidity providers with zero human intervention.',
    accentDetail: 'Zero governance latency or committee votes',
    specCode: 'PRV_SPEC_BOND_SLASH_ENGINE'
  },
  {
    number: '04',
    tag: 'PROOF OF PERFORMANCE',
    title: 'Verifiable SLA & Keeper Rewards',
    description: 'Reward compliant keepers and protocol automations—such as automated Aave self-repayment and vault delta hedges—with immutable performance attestations.',
    accentDetail: 'Cryptographic compliance score & fee rebates',
    specCode: 'PRV_SPEC_PERF_CREDIT_VERIFIER'
  }
];
