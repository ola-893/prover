import { useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X } from 'lucide-react';
import { useWallet } from '@/contexts/WalletContext';

const wallets = [
  {
    id: 'metamask',
    name: 'MetaMask',
    desc: 'Connect using MetaMask browser extension',
    icon: (
      <svg viewBox="0 0 32 32" className="w-8 h-8">
        <rect width="32" height="32" rx="4" fill="#F6851B"/>
        <path d="M27.2 7.4l-7.2 5.3 1.3-5.1z" fill="#E2761B" stroke="#E2761B" strokeLinecap="round" strokeLinejoin="round"/>
        <path d="M4.8 7.4l7.1 5.4-1.2-5.1zm19.5 17.6l-1.8 2.7 3.9 1.1 1.1-3.8zm-22.2.1l1.1 3.8 3.9-1.1-1.8-2.7z" fill="#E4761B" stroke="#E4761B" strokeLinecap="round" strokeLinejoin="round"/>
        <path d="M9.2 17.2l-1.2 1.8 4.3.2-.1-4.6zm15.6 0l-3-4.6-.1 4.7 4.3-.2z" fill="#E4761B" stroke="#E4761B" strokeLinecap="round" strokeLinejoin="round"/>
        <path d="M10.6 12.6l-4.3-1.6 3-1.4zm12.8 0l1.3-1.4 3 1.4z" fill="#E4761B" stroke="#E4761B" strokeLinecap="round" strokeLinejoin="round"/>
        <path d="M11.5 24.6l2.6-1.3-2.2-1.7zm9.4 0l-2.6-1.3 2.2-1.7z" fill="#E4761B" stroke="#E4761B" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    ),
  },
  {
    id: 'walletconnect',
    name: 'WalletConnect',
    desc: 'Scan QR code with WalletConnect',
    icon: (
      <svg viewBox="0 0 32 32" className="w-8 h-8">
        <rect width="32" height="32" rx="4" fill="#3B99FC"/>
        <path d="M11.5 13.5a2.5 2.5 0 110-5 2.5 2.5 0 010 5zm9 0a2.5 2.5 0 110-5 2.5 2.5 0 010 5z" fill="white"/>
        <path d="M8.5 16.5c3.3-3.3 8.7-3.3 12 0" stroke="white" strokeWidth="2" fill="none" strokeLinecap="round"/>
        <path d="M10.5 19.5c2.2-2.2 5.8-2.2 8 0" stroke="white" strokeWidth="2" fill="none" strokeLinecap="round"/>
      </svg>
    ),
  },
  {
    id: 'coinbase',
    name: 'Coinbase Wallet',
    desc: 'Connect using Coinbase Wallet',
    icon: (
      <svg viewBox="0 0 32 32" className="w-8 h-8">
        <rect width="32" height="32" rx="4" fill="#0052FF"/>
        <circle cx="16" cy="16" r="6" fill="white"/>
      </svg>
    ),
  },
];

export default function WalletModal() {
  const { showWalletModal, closeWalletModal, connect, isConnecting, error } = useWallet();

  useEffect(() => {
    if (showWalletModal) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => { document.body.style.overflow = ''; };
  }, [showWalletModal]);

  return (
    <AnimatePresence>
      {showWalletModal && (
        <motion.div
          className="fixed inset-0 z-[100] flex items-center justify-center p-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
        >
          {/* Backdrop */}
          <motion.div
            className="absolute inset-0 bg-[#111111]/60 backdrop-blur-sm"
            onClick={closeWalletModal}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          />

          {/* Modal */}
          <motion.div
            className="relative w-full max-w-md bg-[#FAF9F6] border border-[#111111] shadow-[8px_8px_0px_#111111]"
            initial={{ opacity: 0, y: 20, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 10, scale: 0.98 }}
            transition={{ duration: 0.25, ease: [0.22, 1, 0.36, 1] }}
          >
            {/* Header */}
            <div className="flex items-center justify-between px-6 py-5 border-b border-[#111111]">
              <div>
                <h3 className="font-serif text-xl text-[#111111] tracking-tight">
                  Connect Wallet
                </h3>
                <p className="font-mono text-[10px] text-[#999999] uppercase tracking-widest mt-1">
                  Choose a provider to continue
                </p>
              </div>
              <button
                onClick={closeWalletModal}
                className="w-8 h-8 flex items-center justify-center border border-[#CCCCCC] text-[#999999] hover:border-[#111111] hover:text-[#111111] transition-colors cursor-pointer"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Wallet list */}
            <div className="p-4 space-y-2">
              {wallets.map((wallet, i) => (
                <motion.button
                  key={wallet.id}
                  onClick={() => connect(wallet.id)}
                  disabled={isConnecting}
                  className="w-full flex items-center gap-4 px-4 py-4 border border-[#E5E5E5] hover:border-[#111111] hover:bg-white transition-all duration-200 text-left group disabled:opacity-50 cursor-pointer"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.3, delay: i * 0.05 }}
                >
                  <div className="flex-shrink-0">{wallet.icon}</div>
                  <div className="flex-1 min-w-0">
                    <div className="font-mono text-sm text-[#111111] font-bold tracking-tight group-hover:text-[#D43F3F] transition-colors">
                      {wallet.name}
                    </div>
                    <div className="font-sans text-xs text-[#999999] mt-0.5">
                      {wallet.desc}
                    </div>
                  </div>
                  <div className="flex-shrink-0 font-mono text-[10px] text-[#CCCCCC] group-hover:text-[#111111] transition-colors">
                    →
                  </div>
                </motion.button>
              ))}
            </div>

            {/* Error */}
            {error && (
              <div className="px-6 pb-4">
                <div className="px-4 py-3 border border-[#D43F3F] bg-[#D43F3F]/5 font-mono text-xs text-[#D43F3F]">
                  {error}
                </div>
              </div>
            )}

            {/* Footer */}
            <div className="px-6 py-4 border-t border-[#E5E5E5]">
              <p className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest text-center">
                Non-custodial · Your keys, your crypto
              </p>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
