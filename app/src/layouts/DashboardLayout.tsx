import { NavLink, Outlet } from 'react-router-dom';
import { useWallet } from '@/contexts/WalletContext';
import {
  Search,
  Shield,
  Terminal,
  FileCode,
  BookOpen,
  ChevronLeft,
  Trophy,
  Wallet,
} from 'lucide-react';

const sidebarLinks = [
  { to: '/dashboard/prove', icon: Search, label: 'Prove a fact' },
  { to: '/dashboard/check', icon: Shield, label: 'Check a wallet' },
  { to: '/dashboard/leaderboard', icon: Trophy, label: 'Evidence board' },
  { to: '/dashboard/demo', icon: Terminal, label: 'Proof anatomy' },
  { to: '/dashboard/contracts', icon: FileCode, label: 'Contracts' },
  { to: '/dashboard/docs', icon: BookOpen, label: 'Docs' },
];

export default function DashboardLayout() {
  const { address, chainId, disconnect, openWalletModal } = useWallet();

  const shortAddress = address ? `${address.slice(0, 6)}...${address.slice(-4)}` : null;
  const networkName =
    chainId === 102031
      ? 'CC3 Testnet'
      : chainId === 1
      ? 'Ethereum'
      : chainId === 11155111
      ? 'Sepolia'
      : chainId
      ? `Chain ${chainId}`
      : 'Unknown';

  return (
    <div className="min-h-screen flex bg-[#FAF9F6]">
      {/* Sidebar */}
      <aside className="hidden lg:flex lg:flex-col w-60 border-r border-[#E5E5E5] bg-white shrink-0 sticky top-0 h-screen">
        {/* Brand */}
        <div className="h-16 flex items-center px-6 border-b border-[#E5E5E5]">
          <NavLink to="/" className="flex items-center gap-2">
            <span className="font-serif font-bold text-lg tracking-tight text-[#111111]">
              PROVER
            </span>
            <span className="font-mono text-[9px] text-[#CCCCCC] uppercase tracking-widest">
              /dash
            </span>
          </NavLink>
        </div>

        {/* Nav links */}
        <nav className="flex-1 py-6 px-4 space-y-1">
          {sidebarLinks.map((link) => (
            <NavLink
              key={link.to}
              to={link.to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 font-mono text-xs tracking-wide transition-all rounded-sm ${
                  isActive
                    ? 'bg-[#111111] text-white'
                    : 'text-[#888888] hover:text-[#111111] hover:bg-[#FAF9F6]'
                }`
              }
            >
              <link.icon className="w-4 h-4" strokeWidth={1.5} />
              {link.label}
            </NavLink>
          ))}
        </nav>

        {/* Back to home */}
        <div className="p-4 border-t border-[#E5E5E5]">
          <NavLink
            to="/"
            className="flex items-center gap-2 px-3 py-2 font-mono text-[10px] text-[#BBBBBB] hover:text-[#111111] uppercase tracking-widest transition-colors"
          >
            <ChevronLeft className="w-3 h-3" />
            Back to site
          </NavLink>
        </div>
      </aside>

      {/* Main area */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top bar */}
        <header className="h-14 border-b border-[#E5E5E5] bg-white/80 backdrop-blur-xl flex items-center justify-between px-6 shrink-0">
          {/* Mobile brand */}
          <NavLink to="/" className="lg:hidden flex items-center gap-2">
            <span className="font-serif font-bold text-lg text-[#111111]">PROVER</span>
          </NavLink>

          {/* Mobile nav */}
          <nav className="lg:hidden flex items-center gap-1 overflow-x-auto">
            {sidebarLinks.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                className={({ isActive }) =>
                  `px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider whitespace-nowrap transition-all rounded-sm ${
                    isActive
                      ? 'bg-[#111111] text-white'
                      : 'text-[#888888] hover:bg-[#FAF9F6]'
                  }`
                }
              >
                {link.label}
              </NavLink>
            ))}
          </nav>

          <div className="hidden lg:block" />

          {/* Wallet is optional for public lookup and proof preflight. */}
          <div className="flex items-center gap-3">
            <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 font-mono text-[10px]">
              <span className="w-1.5 h-1.5 rounded-full bg-[#1B8A5A]" />
              <span className="text-[#AAAAAA] uppercase tracking-widest">{address ? networkName : 'Public mode'}</span>
            </div>
            {shortAddress ? (
              <>
                <div className="border border-[#E5E5E5] px-3 py-1.5 font-mono text-xs text-[#555555]">
                  {shortAddress}
                </div>
                <button
                  onClick={disconnect}
                  className="border border-[#E5E5E5] hover:border-[#111111] text-[#AAAAAA] hover:text-[#111111] px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider transition-colors"
                >
                  Disconnect
                </button>
              </>
            ) : (
              <button
                onClick={openWalletModal}
                className="inline-flex items-center gap-2 border border-[#111111] bg-[#111111] px-3 py-1.5 font-mono text-[10px] uppercase tracking-wider text-white hover:bg-[#D43F3F] hover:border-[#D43F3F] transition-colors"
              >
                <Wallet className="w-3 h-3" />
                Connect
              </button>
            )}
          </div>
        </header>

        {/* Page content */}
        <div className="flex-1 overflow-auto">
          <Outlet />
        </div>
      </div>
    </div>
  );
}
