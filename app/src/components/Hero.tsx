import { useEffect, useState, useRef, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { motion, useScroll, useTransform } from 'motion/react';
import { ArrowRight, Search, ShieldCheck } from 'lucide-react';
import { useWallet } from '@/contexts/WalletContext';

function SplitLine({ text, delay, className }: { text: string; delay: number; className?: string }) {
  const words = text.split(' ');
  return (
    <span className={className}>
      {words.map((word, i) => (
        <span key={i} className="inline-block overflow-hidden mr-[0.3em]">
          <motion.span
            className="inline-block"
            initial={{ y: '120%', rotate: 3 }}
            animate={{ y: 0, rotate: 0 }}
            transition={{
              duration: 0.8,
              delay: delay + i * 0.08,
              ease: [0.22, 1, 0.36, 1],
            }}
          >
            {word}
          </motion.span>
        </span>
      ))}
    </span>
  );
}

function FloatingShape({ mouseX, mouseY }: { mouseX: number; mouseY: number }) {
  return (
    <>
      {/* Large circle */}
      <motion.div
        className="absolute top-[15%] right-[10%] w-[300px] h-[300px] rounded-full border border-[#E5E5E5]"
        animate={{
          x: mouseX * 0.02,
          y: mouseY * 0.02,
        }}
        transition={{ type: 'spring', stiffness: 40, damping: 30 }}
      />
      {/* Small dot */}
      <motion.div
        className="absolute top-[35%] right-[25%] w-3 h-3 rounded-full bg-[#D43F3F]"
        animate={{
          x: mouseX * -0.04,
          y: mouseY * -0.04,
        }}
        transition={{ type: 'spring', stiffness: 60, damping: 25 }}
      />
      {/* Horizontal line */}
      <motion.div
        className="absolute bottom-[30%] left-[8%] w-24 h-px bg-[#CCCCCC]"
        animate={{
          x: mouseX * 0.03,
          y: mouseY * 0.01,
        }}
        transition={{ type: 'spring', stiffness: 50, damping: 30 }}
      />
      {/* Small square */}
      <motion.div
        className="absolute top-[60%] right-[5%] w-6 h-6 border border-[#CCCCCC] rotate-45"
        animate={{
          x: mouseX * -0.025,
          y: mouseY * 0.03,
          rotate: 45 + mouseX * 0.05,
        }}
        transition={{ type: 'spring', stiffness: 50, damping: 28 }}
      />
      {/* Thin vertical line */}
      <motion.div
        className="absolute top-[20%] left-[20%] w-px h-16 bg-[#E5E5E5]"
        animate={{
          x: mouseX * 0.015,
          y: mouseY * 0.02,
        }}
        transition={{ type: 'spring', stiffness: 45, damping: 30 }}
      />
    </>
  );
}

export default function Hero() {
  const containerRef = useRef<HTMLElement>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });
  const { openWalletModal, address } = useWallet();

  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ['start start', 'end start'],
  });
  const headlineY = useTransform(scrollYProgress, [0, 1], [0, -80]);
  const subY = useTransform(scrollYProgress, [0, 1], [0, -40]);
  const opacity = useTransform(scrollYProgress, [0, 0.6], [1, 0]);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    const { innerWidth, innerHeight } = window;
    setMousePos({
      x: (e.clientX - innerWidth / 2) / 2,
      y: (e.clientY - innerHeight / 2) / 2,
    });
  }, []);

  return (
    <section
      ref={containerRef}
      onMouseMove={handleMouseMove}
      className="relative min-h-[100vh] bg-[#FAF9F6] overflow-hidden flex flex-col justify-center"
    >
      {/* Subtle grain texture */}
      <div
        className="absolute inset-0 opacity-[0.35] pointer-events-none mix-blend-multiply"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='0.5'/%3E%3C/svg%3E")`,
        }}
      />

      {/* Floating geometric elements */}
      <div className="absolute inset-0 pointer-events-none">
        <FloatingShape mouseX={mousePos.x} mouseY={mousePos.y} />
      </div>

      {/* Top-right label */}
      <motion.div
        className="absolute top-8 right-8 sm:top-10 sm:right-12"
        initial={{ opacity: 0, x: 20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.8, delay: 1.4 }}
      >
        <span className="font-mono text-[10px] text-[#AAAAAA] uppercase tracking-[0.25em]">
          Public evidence workspace
        </span>
      </motion.div>

      {/* Main content */}
      <motion.div
        style={{ y: headlineY, opacity }}
        className="relative z-10 px-6 sm:px-10 lg:px-16 xl:px-24 max-w-[1800px] mx-auto w-full"
      >
        {/* Eyebrow — minimal */}
        <motion.div
          className="mb-8 sm:mb-10"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.6, delay: 0.3 }}
        >
          <span className="font-mono text-[10px] text-[#AAAAAA] uppercase tracking-[0.3em]">
            Attestcoin-authenticated · CC3 Testnet
          </span>
        </motion.div>

        {/* Massive headline */}
        <h1 className="font-serif text-[11vw] sm:text-[9.5vw] lg:text-[8vw] xl:text-[7.2vw] leading-[0.92] tracking-[-0.02em] text-[#111111] mb-8 sm:mb-12">
          <SplitLine text="Prove what happened." delay={0.4} className="block" />
          <SplitLine text="Carry the evidence." delay={0.9} className="block mt-1 sm:mt-2 text-[#888888]" />
        </h1>

        {/* Subline */}
        <motion.div style={{ y: subY }}>
          <motion.p
            className="font-sans text-base sm:text-lg text-[#999999] max-w-lg leading-relaxed mb-12"
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 1.5 }}
          >
            Use authenticated transaction paths to establish a supported attack, a repayment observation, or a financial promise outcome—then inspect the record anywhere.
          </motion.p>

          {/* The three core user journeys are available before a wallet is connected. */}
          <motion.div
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 1.7 }}
            className="grid max-w-3xl grid-cols-1 sm:grid-cols-3 border border-[#111111] bg-white"
          >
            <Link
              to="/dashboard/prove?path=incident"
              className="group border-b sm:border-b-0 sm:border-r border-[#E5E5E5] p-4 sm:p-5 hover:bg-[#111111] transition-colors"
            >
              <span className="font-mono text-[9px] text-[#D43F3F] group-hover:text-[#D43F3F] uppercase tracking-widest">I was attacked</span>
              <span className="mt-2 flex items-center justify-between font-serif text-lg text-[#111111] group-hover:text-white">Prove an incident <ArrowRight className="w-4 h-4" /></span>
              <span className="mt-2 block text-xs text-[#888888] group-hover:text-white/55">Sandwich, FIFO, or a supported promise breach.</span>
            </Link>
            <Link
              to="/dashboard/prove?path=performance"
              className="group border-b sm:border-b-0 sm:border-r border-[#E5E5E5] p-4 sm:p-5 hover:bg-[#111111] transition-colors"
            >
              <span className="font-mono text-[9px] text-[#1B8A5A] group-hover:text-[#1B8A5A] uppercase tracking-widest">I want a report card</span>
              <span className="mt-2 flex items-center justify-between font-serif text-lg text-[#111111] group-hover:text-white">Prove performance <ShieldCheck className="w-4 h-4" /></span>
              <span className="mt-2 block text-xs text-[#888888] group-hover:text-white/55">Selected Aave repayment evidence and terms.</span>
            </Link>
            <Link
              to="/dashboard/check"
              className="group p-4 sm:p-5 hover:bg-[#111111] transition-colors"
            >
              <span className="font-mono text-[9px] text-[#888888] group-hover:text-[#BBBBBB] uppercase tracking-widest">I need to assess someone</span>
              <span className="mt-2 flex items-center justify-between font-serif text-lg text-[#111111] group-hover:text-white">Check a wallet <Search className="w-4 h-4" /></span>
              <span className="mt-2 block text-xs text-[#888888] group-hover:text-white/55">Read the public evidence record without connecting.</span>
            </Link>
          </motion.div>

          {!address && (
            <button
              onClick={openWalletModal}
              className="mt-5 font-mono text-[10px] uppercase tracking-widest text-[#888888] hover:text-[#111111] transition-colors"
            >
              Connect a wallet when you are ready to sign or mint →
            </button>
          )}
        </motion.div>
      </motion.div>

      {/* Bottom-left corner label */}
      <motion.div
        className="absolute bottom-8 left-8 sm:bottom-10 sm:left-12"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.6, delay: 2 }}
      >
        <span className="font-mono text-[10px] text-[#CCCCCC] uppercase tracking-[0.2em]">
          Public lookup · No wallet required
        </span>
      </motion.div>

      {/* Thin decorative line at bottom */}
      <motion.div
        className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-[#E5E5E5] to-transparent"
        initial={{ scaleX: 0 }}
        animate={{ scaleX: 1 }}
        transition={{ duration: 1.2, delay: 1.8, ease: [0.22, 1, 0.36, 1] }}
      />
    </section>
  );
}
