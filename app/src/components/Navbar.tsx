import { Link } from 'react-router-dom';
import { useWallet } from '@/contexts/WalletContext';
import { Search, Wallet } from 'lucide-react';

export default function Navbar() {
  const { address, openWalletModal } = useWallet();

  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-[#FAF9F6]/80 backdrop-blur-xl">
      <div className="max-w-[1800px] mx-auto px-6 sm:px-10 lg:px-16 xl:px-24 h-16 sm:h-20 flex items-center justify-between">
        {/* Brand */}
        <Link to="/" className="flex items-center gap-3">
          <span className="font-serif font-bold text-xl sm:text-2xl tracking-tight text-[#111111]">
            PROVER
          </span>
        </Link>

        {/* Proof routes stay public; a wallet is only required for a future signing action. */}
        <div className="flex items-center gap-6">
          <nav className="hidden lg:flex items-center gap-5 font-mono text-[10px] text-[#888888] uppercase tracking-widest">
            <Link to="/dashboard/prove" className="hover:text-[#111111] transition-colors">Prove</Link>
            <Link to="/dashboard/check" className="hover:text-[#111111] transition-colors">Check wallet</Link>
            <Link to="/dashboard/leaderboard" className="hover:text-[#111111] transition-colors">Evidence board</Link>
          </nav>
          <span className="hidden sm:block font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em]">
            CC3 Testnet
          </span>
          {address ? (
            <Link
              to={`/dashboard/check?address=${encodeURIComponent(address)}`}
              className="border border-[#111111] px-5 py-2.5 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300"
            >
              My record
            </Link>
          ) : (
            <div className="flex items-center gap-2">
              <Link
                to="/dashboard/check"
                className="sm:hidden border border-[#111111] px-3 py-2.5 text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300"
                aria-label="Check a wallet"
              >
                <Search className="w-3.5 h-3.5" />
              </Link>
              <button
                onClick={openWalletModal}
                className="border border-[#111111] px-5 py-2.5 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300 flex items-center gap-2"
              >
                <Wallet className="w-3.5 h-3.5" />
                Connect
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
