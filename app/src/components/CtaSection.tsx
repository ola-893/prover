import { useRef } from 'react';
import { Link } from 'react-router-dom';
import { motion, useInView } from 'motion/react';
import { ArrowRight } from 'lucide-react';
import { useWallet } from '@/contexts/WalletContext';

export default function CtaSection() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: '-100px' });
  const { openWalletModal, address } = useWallet();

  return (
    <section ref={ref} className="relative bg-[#111111] py-24 sm:py-40 overflow-hidden">
      
      {/* Grid overlay */}
      <div className="absolute inset-0 opacity-[0.03] pointer-events-none"
        style={{
          backgroundImage: 'linear-gradient(to right, white 1px, transparent 1px), linear-gradient(to bottom, white 1px, transparent 1px)',
          backgroundSize: '48px 48px',
        }}
      />

      <div className="relative z-10 max-w-7xl mx-auto px-6 sm:px-10 lg:px-16 text-center">
        <motion.span
          initial={{ opacity: 0 }}
          animate={inView ? { opacity: 1 } : {}}
          transition={{ duration: 0.6 }}
          className="font-mono text-[10px] text-[#555555] uppercase tracking-[0.3em] mb-6 block"
        >
          Start proving
        </motion.span>

        <motion.h2
          initial={{ opacity: 0, y: 30 }}
          animate={inView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.7, delay: 0.1 }}
          className="font-serif text-4xl sm:text-5xl lg:text-7xl text-white tracking-tight leading-[1.05] mb-10"
        >
          Every promise leaves a trace.
          <br />
          <span className="italic text-[#555555]">Prove it.</span>
        </motion.h2>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={inView ? { opacity: 1, y: 0 } : {}}
          transition={{ duration: 0.6, delay: 0.3 }}
        >
          {address ? (
            <Link
              to="/dashboard"
              className="inline-flex items-center gap-4 border border-white px-10 py-5 font-mono text-xs uppercase tracking-[0.15em] text-white hover:bg-white hover:text-[#111111] transition-all duration-300 group"
            >
              Enter Dashboard
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </Link>
          ) : (
            <button
              onClick={openWalletModal}
              className="inline-flex items-center gap-4 border border-white px-10 py-5 font-mono text-xs uppercase tracking-[0.15em] text-white hover:bg-white hover:text-[#111111] transition-all duration-300 group"
            >
              Connect Wallet
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </button>
          )}
        </motion.div>

        <motion.p
          initial={{ opacity: 0 }}
          animate={inView ? { opacity: 1 } : {}}
          transition={{ duration: 0.6, delay: 0.5 }}
          className="mt-8 font-mono text-[10px] text-[#444444] uppercase tracking-widest"
        >
          Non-custodial · Deterministic · CC3 Testnet
        </motion.p>
      </div>

    </section>
  );
}
