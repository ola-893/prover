import { useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useWallet } from '@/contexts/WalletContext';
import { Wallet } from 'lucide-react';

export default function Navbar() {
  const { address, openWalletModal } = useWallet();
  const navigate = useNavigate();

  useEffect(() => {
    if (address && location.pathname === '/') {
      navigate('/dashboard');
    }
  }, [address, navigate]);

  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-[#FAF9F6]/80 backdrop-blur-xl">
      <div className="max-w-[1800px] mx-auto px-6 sm:px-10 lg:px-16 xl:px-24 h-16 sm:h-20 flex items-center justify-between">
        {/* Brand */}
        <Link to="/" className="flex items-center gap-3">
          <span className="font-serif font-bold text-xl sm:text-2xl tracking-tight text-[#111111]">
            PROVER
          </span>
        </Link>

        {/* Right */}
        <div className="flex items-center gap-6">
          <span className="hidden sm:block font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em]">
            CC3 Testnet
          </span>
          {address ? (
            <Link
              to="/dashboard"
              className="border border-[#111111] px-5 py-2.5 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300"
            >
              Dashboard
            </Link>
          ) : (
            <button
              onClick={openWalletModal}
              className="border border-[#111111] px-5 py-2.5 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300 flex items-center gap-2"
            >
              <Wallet className="w-3.5 h-3.5" />
              Connect
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
