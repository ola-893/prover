import { useState } from 'react';
import { Contract, isHexString } from 'ethers';
import { CheckCircle2, ExternalLink, Loader2, Wallet } from 'lucide-react';
import { useWallet } from '@/contexts/WalletContext';
import { cc3Deployment, cc3AddressUrl } from '@/lib/deployment';

const EVIDENCE_SBT_ABI = [
  'function mintFromEvidence(bytes32 evidenceId) external returns (uint256 tokenId)',
] as const;

interface EvidenceMintPanelProps {
  onMinted?: () => void;
}

export default function EvidenceMintPanel({ onMinted }: EvidenceMintPanelProps) {
  const { address, chainId, provider, openWalletModal } = useWallet();
  const [evidenceId, setEvidenceId] = useState('');
  const [isMinting, setIsMinting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [transactionHash, setTransactionHash] = useState<string | null>(null);

  const mint = async () => {
    setError(null);
    setTransactionHash(null);
    if (!address || !provider) {
      openWalletModal();
      return;
    }
    if (chainId !== cc3Deployment.chainId) {
      setError(`Switch your wallet to ${cc3Deployment.network} (chain ${cc3Deployment.chainId}) before minting.`);
      return;
    }
    if (!isHexString(evidenceId.trim(), 32)) {
      setError('Enter a 32-byte terminal evidence ID (0x followed by 64 hexadecimal characters).');
      return;
    }

    setIsMinting(true);
    try {
      const signer = await provider.getSigner();
      const sbt = new Contract(cc3Deployment.contracts[4].address, EVIDENCE_SBT_ABI, signer);
      const transaction = await sbt.mintFromEvidence(evidenceId.trim());
      setTransactionHash(transaction.hash);
      await transaction.wait();
      onMinted?.();
    } catch (mintError) {
      setError(mintError instanceof Error ? mintError.message : 'Minting could not be completed.');
    } finally {
      setIsMinting(false);
    }
  };

  return (
    <section className="border border-[#111111] bg-white p-6 sm:p-8">
      <div className="flex flex-col lg:flex-row lg:items-start justify-between gap-6">
        <div className="max-w-2xl">
          <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Mint a report card</div>
          <h2 className="font-serif text-2xl text-[#111111]">Materialize terminal evidence as an ERC-5192 receipt.</h2>
          <p className="text-sm text-[#777777] leading-relaxed mt-3">
            The contract reads the canonical terminal record itself and reverts for a missing, non-terminal, or already-minted ID. The caller cannot pick the recipient, verdict, or metadata; a positive observation goes to its proven subject and a breach receipt goes to its proof-derived claimant.
          </p>
        </div>
        <a
          href={cc3AddressUrl(cc3Deployment.contracts[4].address)}
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[#888888] hover:text-[#111111] transition-colors shrink-0"
        >
          View SBT contract <ExternalLink className="w-3 h-3" />
        </a>
      </div>

      <div className="mt-6 flex flex-col sm:flex-row gap-3">
        <label className="sr-only" htmlFor="mint-evidence-id">Terminal evidence ID</label>
        <input
          id="mint-evidence-id"
          value={evidenceId}
          onChange={(event) => setEvidenceId(event.target.value)}
          placeholder="0x… terminal evidence ID"
          className="min-w-0 flex-1 border border-[#E5E5E5] bg-[#FAF9F6] px-4 py-3.5 font-mono text-xs text-[#111111] placeholder:text-[#BBBBBB] focus:outline-none focus:border-[#111111]"
          spellCheck={false}
          autoComplete="off"
        />
        <button
          onClick={() => void mint()}
          disabled={isMinting}
          className="inline-flex items-center justify-center gap-2 border border-[#111111] bg-[#111111] px-6 py-3.5 font-mono text-xs uppercase tracking-[0.15em] text-white hover:bg-[#D43F3F] hover:border-[#D43F3F] disabled:bg-[#FAF9F6] disabled:border-[#E5E5E5] disabled:text-[#BBBBBB] transition-colors"
        >
          {isMinting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Wallet className="w-4 h-4" />}
          {address ? 'Mint report card' : 'Connect to mint'}
        </button>
      </div>

      {error && <div className="mt-4 border border-[#D43F3F]/30 bg-[#D43F3F]/5 px-4 py-3 text-xs text-[#D43F3F] break-words">{error}</div>}
      {transactionHash && (
        <div className="mt-4 flex items-center gap-2 border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 px-4 py-3 text-xs text-[#1B8A5A]">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>Mint transaction submitted.</span>
          <a
            href={`${cc3Deployment.explorer}/tx/${transactionHash}`}
            target="_blank"
            rel="noreferrer"
            className="ml-auto inline-flex items-center gap-1 font-mono text-[10px] hover:text-[#111111]"
          >
            Explorer <ExternalLink className="w-3 h-3" />
          </a>
        </div>
      )}
    </section>
  );
}
