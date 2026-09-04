import { useRef } from 'react';
import { motion, useInView } from 'motion/react';

export default function Infrastructure() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });

  const contracts = [
    { name: 'OrderingCourt', addr: '0xc01f…c5Ff', role: 'FIFO ordering + sandwich detection' },
    { name: 'CovenantBook', addr: '0x66aF…4223', role: 'Covenant registry + RFQ comparison' },
    { name: 'PerformanceBureau', addr: '0x8Ef4…D74', role: 'Aave yield + drawdown predicates' },
    { name: 'PromiseCourt', addr: '0x41A8…CDcd', role: 'Settlement rulings + breach verdicts' },
    { name: 'PromiseBook', addr: '0x31B6…0821', role: 'Promise lifecycle + state machine' },
    { name: 'AaveAdapter', addr: '0xbA6e…1a02', role: 'AAVE aToken balance snapshots' },
    { name: 'BureauEvidenceSBT', addr: '0x59e4…D442', role: 'Soulbound evidence tokens' },
  ];

  return (
    <section ref={ref} className="bg-[#FAF9F6] py-24 sm:py-40 border-b border-[#111111]">
      <div className="max-w-7xl mx-auto px-6 sm:px-10 lg:px-16">
        
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-16 lg:gap-24">
          
          {/* Left — header */}
          <div className="lg:col-span-5">
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={inView ? { opacity: 1, y: 0 } : {}}
              transition={{ duration: 0.6 }}
              className="lg:sticky lg:top-32"
            >
              <span className="font-mono text-[10px] text-[#888888] uppercase tracking-[0.3em] mb-4 block">
                Infrastructure
              </span>
              <h2 className="font-serif text-4xl sm:text-5xl text-[#111111] tracking-tight leading-[1.1] mb-6">
                Deployed on CC3 testnet
              </h2>
              <p className="font-sans text-sm text-[#666666] leading-relaxed max-w-md">
                Nine contracts forming the evidence pipeline. Each handles one concern. No monolithic logic.
              </p>
            </motion.div>
          </div>

          {/* Right — contract list */}
          <div className="lg:col-span-7">
            {contracts.map((c, i) => (
              <motion.div
                key={c.name}
                initial={{ opacity: 0, x: 20 }}
                animate={inView ? { opacity: 1, x: 0 } : {}}
                transition={{ duration: 0.4, delay: i * 0.06 }}
                className="group grid grid-cols-1 sm:grid-cols-12 gap-2 sm:gap-4 py-6 border-b border-[#E5E5E5] hover:border-[#111111] transition-colors"
              >
                <div className="sm:col-span-4">
                  <span className="font-mono text-xs sm:text-sm text-[#111111] font-bold tracking-tight group-hover:text-[#D43F3F] transition-colors">
                    {c.name}
                  </span>
                </div>
                <div className="sm:col-span-3">
                  <span className="font-mono text-[10px] sm:text-xs text-[#888888]">
                    {c.addr}
                  </span>
                </div>
                <div className="sm:col-span-5">
                  <span className="font-sans text-xs text-[#777777]">
                    {c.role}
                  </span>
                </div>
              </motion.div>
            ))}
          </div>

        </div>

      </div>
    </section>
  );
}
