import { useRef } from 'react';
import { motion, useInView } from 'motion/react';
import { Zap } from 'lucide-react';

export default function ProofEngines() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  const engines = [
    {
      id: 'fifo',
      title: 'FIFO Violation',
      contract: 'OrderingCourt',
      desc: 'First-in-first-out enforcement across the settlement epoch. Proves a trade was filled out of position using a Merkle ordering proof.',
      tag: 'Merkle Order',
    },
    {
      id: 'sandwich',
      title: 'Sandwich Attack',
      contract: 'OrderingCourt',
      desc: 'Detects predatory front-run/back-run patterns against a victim transaction. Same block, same epoch, provable causal chain.',
      tag: 'Pattern Match',
    },
    {
      id: 'aave',
      title: 'Aave Performance',
      contract: 'PerformanceBureau',
      desc: 'Measures real yield and drawdown against promised APY. Compares on-chain aToken balances across declared periods.',
      tag: 'Time Series',
    },
    {
      id: 'rfq',
      title: 'RFQ Comparison',
      contract: 'CovenantBook',
      desc: 'Compares quoted spreads against actual execution. Proves whether a market maker honored their posted price.',
      tag: 'Price Diff',
    },
    {
      id: 'settlement',
      title: 'Settlement Breach',
      contract: 'PromiseCourt',
      desc: 'Determines whether a bonded promise was fulfilled within its declared terms. Binary predicate, zero discretion.',
      tag: 'Term Check',
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
            Engines
          </span>
          <h2 className="font-serif text-4xl sm:text-5xl lg:text-6xl text-white tracking-tight leading-[1.1]">
            Five predicates.
            <br />
            <span className="italic text-[#555555]">Zero interpretation.</span>
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
