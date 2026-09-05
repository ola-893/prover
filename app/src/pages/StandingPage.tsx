import { FormEvent, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  AlertTriangle,
  ArrowRight,
  ExternalLink,
  Loader2,
  Search,
  ShieldCheck,
} from 'lucide-react';
import { useWallet } from '@/contexts/WalletContext';
import EvidenceMintPanel from '@/components/EvidenceMintPanel';
import { cc3AddressUrl } from '@/lib/deployment';
import {
  evidenceRoles,
  formatCtc,
  formatUsdc,
  readStanding,
  roleStanding,
  shortEvidenceAddress,
  type EvidenceRole,
  type StandingReport,
} from '@/lib/evidence-directory';

const toneStyles = {
  positive: 'border-[#1B8A5A]/30 bg-[#1B8A5A]/5 text-[#1B8A5A]',
  negative: 'border-[#D43F3F]/30 bg-[#D43F3F]/5 text-[#D43F3F]',
  neutral: 'border-[#E5E5E5] bg-[#FAF9F6] text-[#888888]',
} as const;

function EvidenceNumber({ label, value, note }: { label: string; value: string | number; note?: string }) {
  return (
    <div className="border border-[#E5E5E5] bg-white p-4">
      <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">{label}</div>
      <div className="font-serif text-2xl text-[#111111] mt-2 tracking-tight">{value}</div>
      {note && <div className="font-mono text-[9px] text-[#BBBBBB] mt-1.5 leading-relaxed">{note}</div>}
    </div>
  );
}

function RoleMetrics({ report, role }: { report: StandingReport; role: EvidenceRole }) {
  const { profile, terms } = report;

  if (role === 'borrower') {
    return (
      <>
        <EvidenceNumber label="Repayment observations" value={profile.aaveSelfRepaymentObservations} note="Selected Aave facts only" />
        <EvidenceNumber label="Borrow facts" value={profile.aaveBorrowFacts} />
        <EvidenceNumber label="Repay facts" value={profile.aaveRepayFacts} />
        <EvidenceNumber label="Experimental max loan" value={formatUsdc(terms.maxBorrowUsdc)} note="Policy V1, not a credit decision" />
      </>
    );
  }

  if (role === 'relayer') {
    return (
      <>
        <EvidenceNumber label="Sandwich rulings" value={profile.sandwichBreaches} />
        <EvidenceNumber label="All recorded CTC damages" value={formatCtc(profile.totalSlashedCtc)} note="Across supported ordering breaches" />
        <EvidenceNumber label="Uncompensated rulings" value={profile.uncompensatedBreaches} />
        <EvidenceNumber label="Proof cards held" value={report.evidenceCardCount.toString()} note="Cards can be held by affected users" />
      </>
    );
  }

  if (role === 'vault-operator') {
    return (
      <>
        <EvidenceNumber label="FIFO rulings" value={profile.fifoBreaches} />
        <EvidenceNumber label="All recorded CTC damages" value={formatCtc(profile.totalSlashedCtc)} note="Across supported ordering breaches" />
        <EvidenceNumber label="Uncompensated rulings" value={profile.uncompensatedBreaches} />
        <EvidenceNumber label="Proof cards held" value={report.evidenceCardCount.toString()} note="Cards can be held by affected users" />
      </>
    );
  }

  return (
    <div className="sm:col-span-2 lg:col-span-4 border border-[#E5E5E5] bg-[#FAF9F6] p-5">
      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Coverage boundary</div>
      <p className="text-sm text-[#666666] leading-relaxed max-w-2xl">
        Validator behavior is outside the current set of deterministic proof engines. Prover cannot turn no visible record into a trust claim.
      </p>
    </div>
  );
}

export default function StandingPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { address: connectedAddress, openWalletModal } = useWallet();
  const queryAddress = searchParams.get('address') ?? '';
  const queryRole = searchParams.get('role');
  const [address, setAddress] = useState(queryAddress);
  const [role, setRole] = useState<EvidenceRole>(
    evidenceRoles.some((item) => item.id === queryRole) ? (queryRole as EvidenceRole) : 'borrower',
  );
  const [report, setReport] = useState<StandingReport | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hydratedSharedLookup = useRef(false);

  const standing = useMemo(
    () => (report ? roleStanding(report, role) : null),
    [report, role],
  );

  const lookup = async (candidate: string) => {
    setIsLoading(true);
    setError(null);
    setReport(null);
    try {
      const nextReport = await readStanding(candidate);
      setReport(nextReport);
      setAddress(nextReport.address);
      setSearchParams({ address: nextReport.address, role });
    } catch (lookupError) {
      setError(lookupError instanceof Error ? lookupError.message : 'The CC3 testnet read failed. Try again shortly.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void lookup(address);
  };

  const selectRole = (nextRole: EvidenceRole) => {
    setRole(nextRole);
    if (report) setSearchParams({ address: report.address, role: nextRole });
  };

  useEffect(() => {
    if (hydratedSharedLookup.current) return;
    hydratedSharedLookup.current = true;
    if (evidenceRoles.some((item) => item.id === queryRole)) setRole(queryRole as EvidenceRole);
    if (queryAddress) void lookup(queryAddress);
    // A shared address is hydrated once on mount; subsequent URL writes come from this view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [queryAddress, queryRole]);

  return (
    <div className="max-w-6xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 lg:gap-16 mb-12">
        <div className="lg:col-span-7">
          <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
            Public evidence directory
          </span>
          <h1 className="font-serif text-4xl sm:text-5xl text-[#111111] tracking-tight leading-[1.05]">
            Check the proof record.
            <br />
            <span className="italic text-[#888888]">Not an opinion.</span>
          </h1>
          <p className="text-base text-[#777777] leading-relaxed mt-5 max-w-xl">
            Look up any wallet without connecting. Prover reads the public CC3 evidence vector and minted ERC-5192 report cards; it never infers good standing from silence.
          </p>
        </div>
        <div className="lg:col-span-5 border-l-0 lg:border-l border-[#E5E5E5] lg:pl-10 self-end">
          <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">What this proves</div>
          <p className="text-sm text-[#666666] leading-relaxed">
            A selected repayment observation, an adjudicated no-sandwich breach, or an adjudicated FairExit breach—only when a terminal record exists on-chain.
          </p>
        </div>
      </div>

      <div className="border border-[#111111] bg-white p-5 sm:p-7 mb-8">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-5">
          <div>
            <h2 className="font-serif text-xl text-[#111111]">Choose the role you are assessing</h2>
            <p className="text-sm text-[#888888] mt-1">Each role has a deliberately narrow evidence boundary.</p>
          </div>
          {connectedAddress ? (
            <button
              onClick={() => {
                setAddress(connectedAddress);
                void lookup(connectedAddress);
              }}
              className="font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors"
            >
              Check my wallet
            </button>
          ) : (
            <button
              onClick={openWalletModal}
              className="font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors"
            >
              Connect to check yours
            </button>
          )}
        </div>

        <div className="grid grid-cols-2 lg:grid-cols-4 gap-2 mb-6">
          {evidenceRoles.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => selectRole(item.id)}
              className={`text-left border p-3 sm:p-4 transition-colors ${
                role === item.id
                  ? 'border-[#111111] bg-[#111111] text-white'
                  : 'border-[#E5E5E5] bg-[#FAF9F6] text-[#111111] hover:border-[#111111]'
              }`}
            >
              <div className="font-mono text-[10px] uppercase tracking-widest">{item.label}</div>
              <div className={`text-[11px] leading-relaxed mt-2 ${role === item.id ? 'text-white/60' : 'text-[#888888]'}`}>
                {item.description}
              </div>
            </button>
          ))}
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col sm:flex-row gap-3">
          <label className="sr-only" htmlFor="wallet-address">Wallet address</label>
          <input
            id="wallet-address"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            placeholder="0x… wallet address"
            className="min-w-0 flex-1 border border-[#E5E5E5] bg-[#FAF9F6] px-4 py-3.5 font-mono text-sm text-[#111111] placeholder:text-[#BBBBBB] focus:outline-none focus:border-[#111111]"
            spellCheck={false}
            autoComplete="off"
          />
          <button
            type="submit"
            disabled={isLoading || !address.trim()}
            className="inline-flex items-center justify-center gap-2 border border-[#111111] bg-[#111111] px-6 py-3.5 font-mono text-xs uppercase tracking-[0.15em] text-white hover:bg-[#D43F3F] hover:border-[#D43F3F] disabled:cursor-wait disabled:bg-[#FAF9F6] disabled:text-[#BBBBBB] disabled:border-[#E5E5E5] transition-colors"
          >
            {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
            Read record
          </button>
        </form>
      </div>

      {error && (
        <div className="mb-8 flex gap-3 border border-[#D43F3F]/30 bg-[#D43F3F]/5 p-4 text-sm text-[#D43F3F]">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <span>{error}</span>
        </div>
      )}

      {report && standing && (
        <>
          <section className="border border-[#E5E5E5] bg-white">
            <div className="flex flex-col md:flex-row md:items-start justify-between gap-6 p-6 sm:p-8 border-b border-[#E5E5E5]">
            <div>
              <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Verified report</div>
              <h2 className="font-serif text-2xl sm:text-3xl text-[#111111]">{shortEvidenceAddress(report.address)}</h2>
              <a
                href={cc3AddressUrl(report.address)}
                target="_blank"
                rel="noreferrer"
                className="mt-2 inline-flex items-center gap-1 font-mono text-[10px] text-[#888888] hover:text-[#111111] transition-colors"
              >
                View wallet on CC3 explorer <ExternalLink className="w-3 h-3" />
              </a>
            </div>
            <div className={`max-w-sm border px-4 py-3 ${toneStyles[standing.tone]}`}>
              <div className="font-mono text-[9px] uppercase tracking-widest mb-1">{evidenceRoles.find((item) => item.id === role)?.label} evidence state</div>
              <div className="font-serif text-lg leading-tight">{standing.label}</div>
              <p className="text-xs leading-relaxed mt-2 opacity-80">{standing.detail}</p>
            </div>
            </div>

            <div className="p-6 sm:p-8">
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                <RoleMetrics report={report} role={role} />
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-6">
                <div className="border border-[#E5E5E5] bg-[#FAF9F6] p-5">
                  <div className="flex items-center gap-2 font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-3">
                    <ShieldCheck className="w-4 h-4 text-[#1B8A5A]" />
                    Soulbound report cards
                  </div>
                  <div className="font-serif text-3xl text-[#111111]">{report.evidenceCardCount.toString()}</div>
                  <p className="text-xs text-[#777777] leading-relaxed mt-2">
                    Each card is an ERC-5192 evidence receipt, permanently locked to its proof-derived recipient. A zero count means no card has been minted; it says nothing about the underlying address.
                  </p>
                </div>
                <div className="border border-[#E5E5E5] bg-[#FAF9F6] p-5">
                  <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-3">How a card is issued</div>
                  <p className="text-xs text-[#777777] leading-relaxed">
                    First, a deterministic court or adapter records a terminal fact. Then anyone may materialize its matching card. Neither the caller nor the UI chooses its recipient, verdict, or metadata.
                  </p>
                  <Link to="/dashboard/prove" className="inline-flex items-center gap-2 mt-4 font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors">
                    Start a proof route <ArrowRight className="w-3 h-3" />
                  </Link>
                </div>
              </div>
            </div>
          </section>
          <div className="mt-6">
            <EvidenceMintPanel onMinted={() => void lookup(report.address)} />
          </div>
        </>
      )}

      {!report && !error && !isLoading && (
        <div className="border border-dashed border-[#CCCCCC] px-6 py-12 text-center bg-white">
          <div className="font-serif text-2xl text-[#111111]">Evidence is public. Wallet connection is optional.</div>
          <p className="text-sm text-[#888888] max-w-xl mx-auto mt-3 leading-relaxed">
            Enter any wallet to see exactly what the live bureau record can—and cannot—establish for the role you selected.
          </p>
        </div>
      )}
    </div>
  );
}
