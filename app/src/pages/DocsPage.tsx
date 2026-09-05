import { CheckCircle2, AlertTriangle } from 'lucide-react';

export default function DocsPage() {
  return (
    <div className="max-w-4xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      {/* Header */}
      <div className="mb-12">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
          Documentation
        </span>
        <h1 className="font-serif text-3xl sm:text-4xl lg:text-5xl text-[#111111] tracking-tight leading-[1.1]">
          How Prover <span className="italic text-[#888888]">works</span>
        </h1>
      </div>

      {/* Predicates */}
      <section className="mb-16">
        <h2 className="font-serif text-2xl text-[#111111] mb-8">
          What Each Predicate Establishes
        </h2>

        <div className="space-y-6">
          {[
            {
              num: '01',
              title: 'No-Sandwich Ruling',
              desc: 'The court requires three transactions authenticated under one source block and one Merkle root, with exact transaction-index adjacency: front-run, victim, back-run. It verifies successful receipts with one exact swap event from the policy-bound pool, the same outer sender for the two searcher legs and a distinct victim sender, a victim call to the policy-bound entrypoint, and an operator-authorized route digest.',
              code: 'require(front.index + 1 == victim.index && victim.index + 1 == back.index);',
              note: 'Does not prove net profit after gas or every possible multi-pool MEV strategy.',
            },
            {
              num: '02',
              title: 'FairExit FIFO Ruling',
              desc: 'Requires four positive facts in fixed roles: request A, request B, process B, process A. Checks request IDs and owners, authenticates the global order, binds both processing transactions to the policy signer, and supports cross-block ordering. The policy commits to a vault implementation with unique, non-cancellable request IDs and single processing.',
              code: 'require(requestA < requestB && processB < processA);',
              note: 'Proves a completed inversion for that policy-bound schema, not a generic proof of an arbitrary vault\'s pending state.',
            },
            {
              num: '03',
              title: 'Aave Observation',
              desc: 'Authenticates successful Ethereum-mainnet Aave V3 Pool receipt logs at an exact ordinal. Attributes Borrow to onBehalfOf and Repay to user, then permits a derived observation only when the subject, USDC reserve, ordering, minimum 32-block gap, self-repayer, and same-or-larger amount all match.',
              code: 'require(sameSubject && sameUsdcReserve && borrow < repay && blockGap >= 32);',
              note: 'Does not prove loan closure, full repayment, current balance, timeliness, liquidation absence, or complete history.',
            },
            {
              num: '04',
              title: 'RFQ and Settlement Outcomes',
              desc: 'Both paths first authenticate the exact V1 transaction and receipt bytes. The selected log must match the committed source chain, emitter, event signature, promise ID, reference ID, actor, topic count, data length, and successful receipt status. A mismatch in those relevance fields rejects the proof. Only after relevance is established does the court classify wrong, short, or late event fields as a breach.',
              code: null,
              note: 'The generic proof-submission default says no acceptable fulfillment proof reached PromiseBook before the evidence window closed.',
            },
          ].map((item) => (
            <div key={item.num} className="border border-[#E5E5E5] bg-white p-6">
              <div className="flex items-center gap-3 mb-4">
                <span className="font-mono text-xs font-bold text-[#D43F3F]">{item.num}</span>
                <h3 className="font-serif text-xl text-[#111111]">{item.title}</h3>
              </div>
              <p className="text-sm text-[#888888] leading-relaxed mb-4">
                {item.desc}
              </p>
              {item.code && (
                <div className="p-4 bg-[#FAF9F6] border border-[#E5E5E5] font-mono text-xs text-[#111111] overflow-x-auto">
                  <code>{item.code}</code>
                </div>
              )}
              <div className="mt-3 font-mono text-[10px] text-[#CCCCCC]">
                {item.note}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Lifecycle */}
      <section className="mb-16">
        <h2 className="font-serif text-2xl text-[#111111] mb-8">
          Promise Lifecycle
        </h2>
        <div className="space-y-3">
          {[
            { step: '01', title: 'Mutual Authorization', desc: 'Actor and beneficiary sign nested EIP-712 data covering every field.' },
            { step: '02', title: 'Policy Approval', desc: 'Governance approves the exact kind, source chain, emitter and policy tuple.' },
            { step: '03', title: 'Prospective Activation', desc: 'The signed anchor is 2-64 Creditcoin blocks in the future. Future block hash becomes part of the final promise ID.' },
            { step: '04', title: 'Typed Resolution', desc: 'PromiseCourt authenticates the exact receipt event and classifies matching, wrong, short, or late outcomes.' },
          ].map((item) => (
            <div key={item.step} className="flex gap-4 border border-[#E5E5E5] bg-white p-4">
              <div className="w-10 h-10 border border-[#E5E5E5] bg-[#FAF9F6] flex items-center justify-center font-mono text-xs font-bold text-[#111111] shrink-0">
                {item.step}
              </div>
              <div>
                <div className="font-serif text-lg text-[#111111]">{item.title}</div>
                <div className="text-xs text-[#888888] mt-1">{item.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Security Boundaries */}
      <section className="mb-16">
        <h2 className="font-serif text-2xl text-[#111111] mb-8">
          Security Boundaries
        </h2>
        <div className="space-y-2">
          {[
            'Covenants cannot be edited, shortened, or cancelled after opening.',
            'RFQ and settlement drafts require exact beneficiary authorization and exact bond funding.',
            'Unordered nonces prevent signature replay across concurrent deals.',
            'Registry changes invalidate pending drafts and permit a full neutral refund.',
            'Ruling replay is blocked in both the court and bond book.',
            'Payouts use pull accounting. A revoked bureau permission cannot roll back an already settled bond.',
            'Reporter permissions are scoped by evidence kind.',
            'The 1 CTC = 1 USDC conversion is an explicit fixture, not an oracle claim.',
          ].map((item, i) => (
            <div key={i} className="flex items-start gap-3 p-3 border border-[#E5E5E5] bg-white">
              <CheckCircle2 className="w-4 h-4 mt-0.5 text-[#1B8A5A] shrink-0" strokeWidth={1.5} />
              <span className="text-xs text-[#888888]">{item}</span>
            </div>
          ))}
        </div>
      </section>

      {/* Disclaimer */}
      <div className="p-5 border border-[#D43F3F]/30 bg-[#D43F3F]/5">
        <div className="flex items-start gap-3">
          <AlertTriangle className="w-4 h-4 text-[#D43F3F] shrink-0 mt-0.5" />
          <div>
            <div className="font-mono text-[10px] font-bold text-[#D43F3F] uppercase tracking-widest mb-2">
              Not Independently Audited
            </div>
            <p className="text-xs text-[#888888] leading-relaxed">
              Contracts have not been independently audited. Use them as hackathon software, not production
              financial infrastructure. Raw PromiseBook.actorStats are mutually authorized ledger
              statistics but are not automatically bureau-grade.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
