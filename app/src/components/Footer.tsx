import { useRef, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { ArrowUp } from 'lucide-react';

export default function Footer() {
  const watermarkRef = useRef<HTMLDivElement>(null);
  const [mousePos, setMousePos] = useState({ x: 0, y: 0 });
  const [isHovering, setIsHovering] = useState(false);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!watermarkRef.current) return;
    const rect = watermarkRef.current.getBoundingClientRect();
    setMousePos({
      x: e.clientX - rect.left,
      y: e.clientY - rect.top,
    });
  }, []);

  const scrollToTop = () => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  return (
    <footer className="bg-[#111111] border-t border-[#333333] text-[#999999] font-mono text-xs">
      
      {/* Main Footer Grid */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-10 pb-12 border-b border-[#333333]">
          
          {/* Brand Column */}
          <div className="lg:col-span-2 space-y-4">
            <Link to="/" className="flex items-center gap-3">
              <div className="w-8 h-8 bg-white border border-white flex items-center justify-center font-mono text-[#111111] font-bold text-sm">
                [P]
              </div>
              <span className="font-serif font-bold text-2xl text-white tracking-tight">
                PROVER
              </span>
            </Link>
            <p className="text-xs text-[#999999] max-w-sm leading-relaxed font-sans">
              A cross-chain bureau of fulfilled and breached financial promises. It turns authenticated source-chain transactions into typed evidence, applies fixed predicates, and makes terminal records portable as soulbound report cards.
            </p>
            <div className="flex items-center gap-4 text-[11px] font-mono text-[#666666]">
              <span>CC3 TESTNET</span>
              <span>·</span>
              <span>MIT LICENSED</span>
            </div>
          </div>

          {/* Networks */}
          <div className="space-y-3">
            <div className="text-white font-mono font-bold uppercase text-xs tracking-wider">
              Networks
            </div>
            <ul className="space-y-2 text-xs">
              <li><span className="text-[#999999]">Creditcoin CC3 (Chain 102031)</span></li>
              <li><span className="text-[#999999]">Ethereum Sepolia (Fixture Emitter)</span></li>
              <li><span className="text-[#999999]">Ethereum Mainnet (Aave Source)</span></li>
            </ul>
          </div>

          {/* Contracts */}
          <div className="space-y-3">
            <div className="text-white font-mono font-bold uppercase text-xs tracking-wider">
              Key Contracts
            </div>
            <ul className="space-y-2 text-xs">
              <li><span className="text-[#999999]">OrderingCourt · 0xc01f…c5Ff</span></li>
              <li><span className="text-[#999999]">CovenantBook · 0x66aF…4223</span></li>
              <li><span className="text-[#999999]">PerformanceBureau · 0x8Ef4…D74</span></li>
              <li><span className="text-[#999999]">PromiseCourt · 0x41A8…CDcd</span></li>
              <li><span className="text-[#999999]">BureauEvidenceSBT · 0x59e4…D442</span></li>
            </ul>
          </div>

        </div>
      </div>

      {/* Brand Watermark with liquid paint effect */}
      <div
        ref={watermarkRef}
        className="relative overflow-hidden px-4 sm:px-6 lg:px-8 py-10 sm:py-16 cursor-none"
        onMouseMove={handleMouseMove}
        onMouseEnter={() => setIsHovering(true)}
        onMouseLeave={() => setIsHovering(false)}
      >
        {/* Base text — dim */}
        <h2 className="font-serif font-bold text-[28vw] sm:text-[24vw] md:text-[22vw] lg:text-[20vw] text-[#222222] tracking-tight leading-none text-center select-none transition-colors duration-300">
          PROVER
        </h2>

        {/* Revealed text — bright, follows cursor */}
        {isHovering && (
          <div
            className="absolute inset-0 flex items-center justify-center pointer-events-none"
            style={{
              WebkitMaskImage: `radial-gradient(circle 120px at ${mousePos.x}px ${mousePos.y}px, white 0%, transparent 100%)`,
              maskImage: `radial-gradient(circle 120px at ${mousePos.x}px ${mousePos.y}px, white 0%, transparent 100%)`,
            }}
          >
            <h2 className="font-serif font-bold text-[28vw] sm:text-[24vw] md:text-[22vw] lg:text-[20vw] text-white tracking-tight leading-none text-center select-none">
              PROVER
            </h2>
          </div>
        )}

        {/* Liquid ripple ring */}
        {isHovering && (
          <div
            className="absolute pointer-events-none rounded-full border-2 border-white/20 animate-ping"
            style={{
              left: mousePos.x - 40,
              top: mousePos.y - 40,
              width: 80,
              height: 80,
            }}
          />
        )}

        {/* Tagline */}
        <div className="relative z-10 flex flex-wrap items-center justify-center gap-4 sm:gap-6 font-mono text-[10px] sm:text-xs text-[#666666] uppercase tracking-widest mt-4 sm:mt-6">
          <span>Prove what happened</span>
          <span className="text-[#444444]">·</span>
          <span>Carry the evidence</span>
          <span className="text-[#444444]">·</span>
          <span>CC3 Testnet</span>
        </div>
      </div>

      {/* Bottom Bar */}
      <div className="border-t border-[#333333]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex flex-col sm:flex-row items-center justify-between gap-4 text-[11px] font-mono text-[#666666]">
          <div className="flex flex-wrap items-center gap-4">
            <span>&copy; 2026 PROVER</span>
            <span>·</span>
            <span>MIT LICENSED</span>
            <span>·</span>
            <span className="text-[#1B8A5A] font-bold">CC3 TESTNET LIVE</span>
          </div>

          <button
            onClick={scrollToTop}
            className="flex items-center gap-2 text-white hover:text-[#D43F3F] transition-colors cursor-pointer border border-[#555555] px-4 py-1.5 bg-transparent shadow-none font-mono text-xs uppercase tracking-wider font-bold"
          >
            <span>[ Back to Top ]</span>
            <ArrowUp className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

    </footer>
  );
}
