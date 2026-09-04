export interface EvidenceScenario {
  id: string;
  category: 'VIOLATION' | 'POSITIVE_PERFORMANCE';
  title: string;
  subtitle: string;
  chain: string;
  targetProtocol: string;
  bondedCollateral: string;
  slashedAmount: string;
  victimRecovery: string;
  blockNumber: number;
  txHash: string;
  attackerAddress: string;
  victimAddress: string;
  violationRule: string;
  evidenceProofType: string;
  summary: string;
  mempoolTrace: {
    step: number;
    action: string;
    timestampOffset: string;
    gasPrice: string;
    status: 'INSPECTION' | 'BREACH' | 'VERIFIED' | 'SETTLED';
    detail: string;
  }[];
  zkProofMetrics: {
    constraints: string;
    proverTimeMs: number;
    verifierGas: string;
    circuit: string;
    hashRoot: string;
  };
}

export interface ValueProp {
  number: string;
  tag: string;
  title: string;
  description: string;
  accentDetail: string;
  specCode: string;
}
