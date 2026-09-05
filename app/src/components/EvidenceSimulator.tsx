import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, CheckCircle2, Circle, Info } from 'lucide-react';

type AnatomyId = 'sandwich' | 'fair-exit' | 'aave';

const anatomies: Record<
  AnatomyId,
  {
    title: string;
    tag: string;
    statement: string;
    sourceFacts: readonly string[];
    structure: readonly string[];
    courtChecks: readonly string[];
    boundary: string;
    route: string;
  }
> = {
  sandwich: {
    title: 'Sandwich ordering',
    tag: 'Same block · exact adjacency',
    statement: 'front-run < victim < back-run',
    sourceFacts: ['Front-run transaction packet', 'Victim transaction packet', 'Back-run transaction packet'],
    structure: ['All three packets resolve under the same source-block Merkle root.', 'Sibling laterality reproduces positions i, i + 1, and i + 2.', 'The structure establishes exact adjacency, not a mempool arrival time.'],
    courtChecks: ['A pre-existing no-sandwich covenant covers the block.', 'Receipts contain the policy-bound swap facts.', 'The two outer legs and the route authorization match the operator policy.'],
    boundary: 'Position alone cannot prove profit, every multi-pool strategy, or generic malicious intent.',
    route: '/dashboard/prove?path=incident',
  },
  'fair-exit': {
    title: 'FairExit queue order',
    tag: 'Global history · completed inversion',
    statement: 'request A < request B < process B < process A',
    sourceFacts: ['Earlier exit request A', 'Later exit request B', 'Process B transaction', 'Process A transaction'],
    structure: ['Each packet supplies a fixed transaction coordinate.', 'Coordinates establish the global sequence across one or more blocks.', 'The structure establishes completed inverse processing without reading pending state.'],
    courtChecks: ['A pre-existing FIFO covenant covers the request and process records.', 'Request IDs and owners bind to the expected vault schema.', 'The processing signer and receipt events match the policy.'],
    boundary: 'It does not prove an arbitrary vault’s current queue or make a claim about unobserved requests.',
    route: '/dashboard/prove?path=incident',
  },
  aave: {
    title: 'Aave repayment observation',
    tag: 'Receipt events · selected facts',
    statement: 'Borrow < later same-address Repay',
    sourceFacts: ['Aave V3 Borrow receipt at an exact log ordinal', 'A later Aave V3 Repay receipt at an exact log ordinal'],
    structure: ['Attestcoin packets fix the selected transactions in Ethereum history.', 'Coordinates establish that the Borrow precedes the Repay.', 'Receipt inclusion pins the chosen event log without trusting tx.from alone.'],
    courtChecks: ['Borrow onBehalfOf and Repay user/repayer bind to the subject.', 'The reserve is USDC and the policy’s block-gap and amount rules pass.', 'The adapter writes a narrow self-repayment observation to the bureau.'],
    boundary: 'It does not establish current balance, loan closure, timeliness, no liquidations, or a complete credit history.',
    route: '/dashboard/prove?path=performance',
  },
};

function CheckList({ items, accent }: { items: readonly string[]; accent: 'red' | 'green' }) {
  return (
    <ul className="space-y-3">
      {items.map((item) => (
        <li key={item} className="flex gap-3 text-sm text-[#666666] leading-relaxed">
          <CheckCircle2 className={`w-4 h-4 shrink-0 mt-0.5 ${accent === 'green' ? 'text-[#1B8A5A]' : 'text-[#D43F3F]'}`} />
          <span>{item}</span>
        </li>
      ))}
    </ul>
  );
}

export default function EvidenceSimulator() {
  const [selected, setSelected] = useState<AnatomyId>('sandwich');
  const [showChecks, setShowChecks] = useState(false);
  const anatomy = anatomies[selected];

  return (
    <div className="max-w-5xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-16 mb-12">
        <div className="lg:col-span-7">
          <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">Proof anatomy</span>
          <h1 className="font-serif text-4xl sm:text-5xl text-[#111111] tracking-tight leading-[1.05]">
            What the Merkle path
            <br />
            <span className="italic text-[#888888]">actually establishes.</span>
          </h1>
        </div>
        <div className="lg:col-span-5 self-end border-l-0 lg:border-l border-[#E5E5E5] lg:pl-8">
          <div className="flex gap-2 text-xs text-[#777777] leading-relaxed">
            <Info className="w-4 h-4 shrink-0 text-[#D43F3F]" />
            <span>Illustrative proof shapes only. This page does not claim a live ruling, incident, payout, or external attack.</span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-8">
        {(Object.keys(anatomies) as AnatomyId[]).map((id) => (
          <button
            key={id}
            onClick={() => {
              setSelected(id);
              setShowChecks(false);
            }}
            className={`text-left border p-4 transition-colors ${selected === id ? 'border-[#111111] bg-[#111111] text-white' : 'border-[#E5E5E5] bg-white text-[#111111] hover:border-[#111111]'}`}
          >
            <div className="font-mono text-[9px] uppercase tracking-widest text-[#D43F3F]">{anatomies[id].tag}</div>
            <div className="font-serif text-xl mt-2">{anatomies[id].title}</div>
          </button>
        ))}
      </div>

      <div className="border border-[#111111] bg-white">
        <div className="p-6 sm:p-8 border-b border-[#E5E5E5]">
          <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest">Structural statement</div>
          <div className="font-serif text-2xl sm:text-3xl text-[#111111] mt-3 tracking-tight">{anatomy.statement}</div>
          <div className="mt-5 flex flex-wrap gap-2">
            {anatomy.sourceFacts.map((fact, index) => (
              <div key={fact} className="flex items-center gap-2 border border-[#E5E5E5] bg-[#FAF9F6] px-3 py-2">
                <span className="w-5 h-5 flex items-center justify-center rounded-full border border-[#CCCCCC] font-mono text-[9px] text-[#888888]">{index + 1}</span>
                <span className="font-mono text-[10px] text-[#555555]">{fact}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 divide-y lg:divide-y-0 lg:divide-x divide-[#E5E5E5]">
          <div className="p-6 sm:p-8">
            <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-5">Merkle structure establishes</div>
            <CheckList items={anatomy.structure} accent="red" />
          </div>
          <div className="p-6 sm:p-8 bg-[#FAF9F6]">
            <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-5">Court or adapter must still establish</div>
            {showChecks ? (
              <CheckList items={anatomy.courtChecks} accent="green" />
            ) : (
              <button
                onClick={() => setShowChecks(true)}
                className="inline-flex items-center gap-2 border border-[#111111] px-4 py-2.5 font-mono text-[10px] uppercase tracking-widest text-[#111111] hover:bg-[#111111] hover:text-white transition-colors"
              >
                Show policy checks <ArrowRight className="w-3 h-3" />
              </button>
            )}
          </div>
        </div>

        <div className="border-t border-[#E5E5E5] p-5 sm:px-8 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex gap-2 text-xs text-[#888888] leading-relaxed max-w-2xl">
            <Circle className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            <span>{anatomy.boundary}</span>
          </div>
          <Link to={anatomy.route} className="inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors shrink-0">
            Open proof route <ArrowRight className="w-3 h-3" />
          </Link>
        </div>
      </div>
    </div>
  );
}
