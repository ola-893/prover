import { useRef } from 'react';
import { motion, useInView } from 'motion/react';
import { Zap } from 'lucide-react';

export default function ProofEngines() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  const engines = [
    {
      id: 'sandwich',
      title: 'Sandwich ordering breach',
      contract: 'OrderingCourt',
      desc: 'Tests whether a relay-controlled front-run and back-run sit immediately around an authorized victim swap in one authenticated source block.',
      tag: 'Merkle Order',
    },
    {
      id: 'fair-exit',
      title: 'FairExit queue inversion',
      contract: 'OrderingCourt',
      desc: 'Tests the fixed request A < request B < process B < process A predicate for a policy-bound vault exit queue.',
      tag: 'Cross-block order',
    },
    {
      id: 'aave',
      title: 'Aave repayment observation',
      contract: 'PerformanceBureau',
      desc: 'Binds one selected Aave V3 USDC Borrow and a later same-address Repay into a narrow, explainable performance observation.',
      tag: 'Receipt events',
    },
    {
      id: 'rfq',
      title: 'RFQ promise outcome',
      contract: 'PromiseCourt',
      desc: 'Authenticates the exact committed RFQ event and checks actor, recipient, amount, terms, and timing against a prospectively activated promise.',
      tag: 'Committed terms',
    },
    {
      id: 'settlement',
      title: 'Settlement promise outcome',
      contract: 'PromiseCourt',
      desc: 'Authenticates a release event and applies a fixed policy to classify fulfillment, a specific mismatch, lateness, or a defaulted promise.',
      tag: 'Receipt events',
    },
  ];

  return (
    <section ref={ref} className="bg-[#111111] py-24 sm:py-40 border-b border-[#333333]">
      <div className="max-w-7xl mx-auto px-6 sm:px-10 lg:px-16">
        
        {/* Section header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={inView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="mb-20"
        >
          <span className="font-mono text-[10px] text-[#555555] uppercase tracking-[0.3em] mb-4 block">
            Proof engines
          </span>
          <h2 className="font-serif text-4xl sm:text-5xl lg:text-6xl text-white tracking-tight leading-[1.1]">
            What Prover can
            <br />
            <span className="italic text-[#555555]">prove today.</span>
          </h2>
        </motion.div>

        {/* Engine list */}
        <div className="space-y-0">
          {engines.map((engine, i) => (
            <motion.div
              key={engine.id}
              initial={{ opacity: 0, y: 30 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.5, delay: i * 0.08 }}
              className="group grid grid-cols-1 sm:grid-cols-12 gap-4 sm:gap-8 py-8 sm:py-10 border-t border-[#333333] hover:border-[#555555] transition-colors cursor-default"
            >
              {/* Tag */}
              <div className="sm:col-span-2">
                <span className="inline-flex items-center gap-2 font-mono text-[10px] text-[#555555] uppercase tracking-widest group-hover:text-[#D43F3F] transition-colors">
                  <Zap className="w-3 h-3" strokeWidth={1.5} />
                  {engine.tag}
                </span>
              </div>

              {/* Title */}
              <div className="sm:col-span-4">
                <h3 className="font-serif text-xl sm:text-2xl text-white tracking-tight group-hover:text-[#D43F3F] transition-colors">
                  {engine.title}
                </h3>
                <span className="font-mono text-[10px] text-[#555555] uppercase tracking-widest mt-1 block">
                  {engine.contract}
                </span>
              </div>

              {/* Description */}
              <div className="sm:col-span-6">
                <p className="font-sans text-sm text-[#777777] leading-relaxed group-hover:text-[#999999] transition-colors">
                  {engine.desc}
                </p>
              </div>
            </motion.div>
          ))}
        </div>

      </div>
    </section>
  );
}
