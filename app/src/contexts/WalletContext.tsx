import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import { BrowserProvider } from 'ethers';

interface WalletContextType {
  address: string | null;
  chainId: number | null;
  provider: BrowserProvider | null;
  connect: (walletId?: string) => Promise<void>;
  disconnect: () => void;
  isConnecting: boolean;
  error: string | null;
  showWalletModal: boolean;
  openWalletModal: () => void;
  closeWalletModal: () => void;
}

const WalletContext = createContext<WalletContextType | null>(null);

export function useWallet() {
  const ctx = useContext(WalletContext);
  if (!ctx) throw new Error('useWallet must be used within WalletProvider');
  return ctx;
}

export function WalletProvider({ children }: { children: ReactNode }) {
  const [address, setAddress] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [provider, setProvider] = useState<BrowserProvider | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showWalletModal, setShowWalletModal] = useState(false);

  const openWalletModal = useCallback(() => setShowWalletModal(true), []);
  const closeWalletModal = useCallback(() => {
    setShowWalletModal(false);
    setError(null);
  }, []);

  const connect = useCallback(async (walletId?: string) => {
    // If no walletId provided, show the modal
    if (!walletId) {
      setShowWalletModal(true);
      return;
    }

    setIsConnecting(true);
    setError(null);

    try {
      if (walletId === 'metamask') {
        if (typeof window === 'undefined' || !window.ethereum) {
          setError('MetaMask is not installed. Please install MetaMask to continue.');
          setIsConnecting(false);
          return;
        }
        const eth = window.ethereum;
        const accounts = await eth.request({ method: 'eth_requestAccounts' }) as string[];
        const chainHex = await eth.request({ method: 'eth_chainId' }) as string;
        const prov = new BrowserProvider(eth);
        setProvider(prov);
        setAddress(accounts[0]);
        setChainId(parseInt(chainHex, 16));
        setShowWalletModal(false);

        eth.on('accountsChanged', (accs: string[]) => {
          setAddress(accs[0] ?? null);
        });
        eth.on('chainIdChanged', (id: string) => {
          setChainId(parseInt(id, 16));
        });
      } else if (walletId === 'walletconnect') {
        setError('WalletConnect coming soon.');
      } else if (walletId === 'coinbase') {
        setError('Coinbase Wallet coming soon.');
      }
    } catch (err: any) {
      setError(err?.message ?? 'Failed to connect wallet');
    } finally {
      setIsConnecting(false);
    }
  }, []);

  const disconnect = useCallback(() => {
    setAddress(null);
    setChainId(null);
    setProvider(null);
  }, []);

  return (
    <WalletContext.Provider value={{ address, chainId, provider, connect, disconnect, isConnecting, error, showWalletModal, openWalletModal, closeWalletModal }}>
      {children}
    </WalletContext.Provider>
  );
}
