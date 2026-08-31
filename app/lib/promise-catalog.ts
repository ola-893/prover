export type PromiseCoverage = {
  id: 'sandwich' | 'fair-exit' | 'rfq' | 'settlement';
  eyebrow: string;
  title: string;
  promise: string;
  proof: string;
  consequence: string;
  contractStatus: string;
  evidenceStatus: string;
  maturity: 'flagship' | 'court-module';
  accent: 'orange' | 'blue' | 'lime' | 'violet';
};

export const promiseCatalog: readonly PromiseCoverage[] = [
  {
    id: 'sandwich',
    eyebrow: 'Relay execution',
    title: 'No-sandwich outcome',
    promise:
      'A relay authorizes one exact route and bonds the promise that it will not be sandwiched.',
    proof:
      'Three authenticated, adjacent swaps bracket the victim in one source block.',
    consequence:
      'The bond pays a fixed CTC penalty and the relay receives a typed breach record.',
    contractStatus: 'CC3 court deployed',
    evidenceStatus: 'Fixture verdict · 0 live rulings',
    maturity: 'flagship',
    accent: 'orange',
  },
  {
    id: 'fair-exit',
    eyebrow: 'Vault operations',
    title: 'FairExit FIFO',
    promise:
      'A vault operator bonds unique, non-cancellable requests and FIFO processing.',
    proof:
      'Four positive proofs establish request A before B, but processing B before A.',
    consequence:
      'The earlier requester receives the penalty and the operator receives a typed breach record.',
    contractStatus: 'CC3 court deployed',
    evidenceStatus: 'Fixture verdict · 0 live rulings',
    maturity: 'flagship',
    accent: 'blue',
  },
  {
    id: 'rfq',
    eyebrow: 'Bonded execution',
    title: 'RFQ execution terms',
    promise:
      'Actor and beneficiary authorize exact assets, input, minimum output, recipient, source policy and deadlines.',
    proof:
      'A future-block-hash promise ID binds one authenticated RFQExecuted event to a prospective obligation.',
    consequence:
      'PromiseBook refunds the bond on fulfillment or credits the fixed penalty on breach.',
    contractStatus: 'Authorized lifecycle tested locally',
    evidenceStatus: 'Fixture source policy · not deployed',
    maturity: 'court-module',
    accent: 'lime',
  },
  {
    id: 'settlement',
    eyebrow: 'Deal settlement',
    title: 'Settlement release',
    promise:
      'Actor and beneficiary authorize an exact asset, minimum amount, recipient, source policy and deadlines.',
    proof:
      'A future-block-hash promise ID binds one authenticated SettlementReleased event to the accepted draft.',
    consequence:
      'PromiseBook refunds the bond on fulfillment or credits the fixed penalty on breach.',
    contractStatus: 'Authorized lifecycle tested locally',
    evidenceStatus: 'Fixture source policy · not deployed',
    maturity: 'court-module',
    accent: 'violet',
  },
] as const;
