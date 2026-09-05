import { Link } from 'react-router-dom';
import { ArrowRight, LockKeyhole, ShieldCheck } from 'lucide-react';

export default function CovenantPage() {
  const requirements = [
    ['Posted first', 'The relay or vault must bind the policy and coverage window before the source-chain incident.'],
    ['Exact policy', 'The court only accepts the specific pool, route, vault schema, signer, and evidence shape committed by that covenant.'],
    ['Bounded claim window', 'A claim can be read and tested only while its attested-height window remains open.'],
    ['Terminal ruling', 'A passed preflight is not a verdict. The deployed court still authenticates packets and decodes policy-specific receipt facts.'],
  ];

  return (
    <div className="max-w-5xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      <div className="max-w-3xl mb-12">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">Evidence boundary</span>
        <h1 className="font-serif text-4xl sm:text-5xl text-[#111111] tracking-tight leading-[1.05]">
          A breach needs a promise
          <br />
          <span className="italic text-[#888888]">that existed first.</span>
        </h1>
        <p className="text-base text-[#777777] leading-relaxed mt-5">
          Prover does not retroactively label a wallet as malicious. A no-sandwich or FairExit claim is enforceable only where the operator posted the matching covenant before the incident.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {requirements.map(([title, detail], index) => (
          <div key={title} className="border border-[#E5E5E5] bg-white p-6">
            <div className="flex items-center gap-3 mb-4">
              {index < 2 ? <LockKeyhole className="w-4 h-4 text-[#D43F3F]" /> : <ShieldCheck className="w-4 h-4 text-[#1B8A5A]" />}
              <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest">0{index + 1}</span>
            </div>
            <h2 className="font-serif text-xl text-[#111111]">{title}</h2>
            <p className="text-sm text-[#777777] leading-relaxed mt-3">{detail}</p>
          </div>
        ))}
      </div>

      <div className="mt-8 border border-[#111111] bg-[#111111] text-white p-6 sm:p-8 flex flex-col sm:flex-row sm:items-center justify-between gap-5">
        <div>
          <div className="font-mono text-[10px] text-[#777777] uppercase tracking-widest">Next step</div>
          <div className="font-serif text-2xl mt-2">Check the covenant, then test the evidence.</div>
        </div>
        <Link to="/dashboard/prove?path=incident" className="inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-white hover:text-[#D43F3F] transition-colors shrink-0">
          Open incident route <ArrowRight className="w-3 h-3" />
        </Link>
      </div>
    </div>
  );
}
