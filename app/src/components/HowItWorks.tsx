import { useRef } from 'react';
import { motion, useInView } from 'motion/react';
import { Shield, Search, Gavel } from 'lucide-react';

export default function HowItWorks() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  const steps = [
    {
      num: '01',
      icon: Shield,
      title: 'Covenant',
      desc: 'Promises are locked on-chain with bonded CTC collateral. Terms are explicit. Stakes are real.',
      contracts: ['CovenantBook', 'PromiseBook'],
      color: 'text-[#1B8A5A]',
    },
    {
      num: '02',
      icon: Search,
      title: 'Evidence',
      desc: 'Source-chain transactions are authenticated, typed, and fed into deterministic breach predicates. No interpretation.',
      contracts: ['BureauEvidenceSBT', 'PerformanceBureau'],
      color: 'text-[#D43F3F]',
    },
    {
      num: '03',
      icon: Gavel,
      title: 'Ruling',
      desc: 'Merkle-order proofs determine FIFO position, sandwich detection, or covenant breach. Collateral is distributed automatically.',
      contracts: ['OrderingCourt', 'PromiseCourt'],
      color: 'text-[#111111]',
    },
  ];

  return (
    <section ref={ref} className="bg-[#FAF9F6] py-24 sm:py-40 border-b border-[#111111]">
      <div className="max-w-7xl mx-auto px-6 sm:px-10 lg:px-16">
        
        {/* Section header */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={inView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6 }}
          className="mb-20"
        >
          <span className="font-mono text-[10px] text-[#888888] uppercase tracking-[0.3em] mb-4 block">
            How it works
          </span>
          <h2 className="font-serif text-4xl sm:text-5xl lg:text-6xl text-[#111111] tracking-tight leading-[1.1]">
            Three positions.
            <br />
            <span className="italic text-[#888888]">One enforcement.</span>
          </h2>
        </motion.div>

        {/* Steps — staggered */}
        <div className="space-y-0">
          {steps.map((step, i) => (
            <motion.div
              key={step.num}
              initial={{ opacity: 0, y: 40 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6, delay: i * 0.15 }}
              className={`grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-16 py-12 sm:py-16 border-t border-[#111111] ${
                i % 2 === 0 ? '' : 'lg:direction-rtl'
              }`}
            >
              {/* Step number + icon */}
              <div className="lg:col-span-2 flex items-start gap-4">
                <span className="font-serif text-6xl sm:text-7xl text-[#E5E5E5] leading-none select-none">
                  {step.num}
                </span>
                <step.icon className={`w-5 h-5 mt-3 ${step.color}`} strokeWidth={1.5} />
              </div>

              {/* Content */}
              <div className={`lg:col-span-5 ${i % 2 !== 0 ? 'lg:order-last' : ''}`}>
                <h3 className="font-serif text-2xl sm:text-3xl text-[#111111] tracking-tight mb-4">
                  {step.title}
                </h3>
                <p className="font-sans text-sm text-[#666666] leading-relaxed max-w-md">
                  {step.desc}
                </p>
              </div>

              {/* Contracts */}
              <div className={`lg:col-span-5 flex items-center ${i % 2 !== 0 ? 'lg:order-first' : ''}`}>
                <div className="flex flex-wrap gap-3">
                  {step.contracts.map((c) => (
                    <span
                      key={c}
                      className="font-mono text-[10px] sm:text-xs border border-[#CCCCCC] text-[#888888] px-4 py-2 uppercase tracking-wider"
                    >
                      {c}
                    </span>
                  ))}
                </div>
              </div>
            </motion.div>
          ))}
        </div>

      </div>
    </section>
  );
}
