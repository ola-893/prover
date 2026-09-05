import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  AlertTriangle,
  ArrowRight,
  Loader2,
  RefreshCw,
  Trophy,
} from 'lucide-react';
import {
  readCanonicalEvidenceDirectory,
  type CanonicalBorrowerObservation,
  type CanonicalEvidenceDirectory,
  type CanonicalOrderingRuling,
} from '@/lib/evidence-directory';

type Board = 'borrower' | 'relayer' | 'vault';

interface BoardRow {
  address: string;
  count: number;
  newestRecord: number;
  newestRecordIsBlock: boolean;
}

const boards: Record<Board, { label: string; headline: string; detail: string; tone: string; countLabel: string }> = {
  borrower: {
    label: 'Borrowers',
    headline: 'Selected verified repayment observations',
    detail: 'Ranks only the bounded Aave self-repayment observations recorded by the public evidence adapter. It is not a complete credit history or a loan-closure claim.',
    tone: 'text-[#1B8A5A]',
    countLabel: 'Observations',
  },
  relayer: {
    label: 'Relayers',
    headline: 'Proved no-sandwich breaches',
    detail: 'Ranks only operators with a canonical, bureau-recorded ruling. No record is never treated as a good score.',
    tone: 'text-[#D43F3F]',
    countLabel: 'Rulings',
  },
  vault: {
    label: 'Vault operators',
    headline: 'Proved FairExit breaches',
    detail: 'Ranks only operators with a canonical, bureau-recorded FIFO ruling. No record is never treated as a good score.',
    tone: 'text-[#D43F3F]',
    countLabel: 'Rulings',
  },
};

function groupedRows(records: Array<CanonicalBorrowerObservation | CanonicalOrderingRuling>) {
  const grouped = new Map<string, BoardRow>();
  records.forEach((record) => {
    const isBorrowerObservation = 'subject' in record;
    const address = isBorrowerObservation ? record.subject : record.operator;
    const newestRecord = isBorrowerObservation ? record.recordedInBlock : record.ruledAt;
    const existing = grouped.get(address);
    if (existing) {
      existing.count += 1;
      existing.newestRecord = Math.max(existing.newestRecord, newestRecord);
      return;
    }
    grouped.set(address, {
      address,
      count: 1,
      newestRecord,
      newestRecordIsBlock: isBorrowerObservation,
    });
  });
  return [...grouped.values()].sort(
    (left, right) => right.count - left.count || right.newestRecord - left.newestRecord,
  );
}

function recordsForBoard(directory: CanonicalEvidenceDirectory | null, board: Board) {
  if (!directory) return [];
  if (board === 'borrower') return directory.borrowerObservations;
  return board === 'relayer' ? directory.sandwichRulings : directory.fifoRulings;
}

function latestRecordLabel(row: BoardRow) {
  if (row.newestRecordIsBlock) return `Latest CC3 block ${row.newestRecord.toLocaleString()}`;
  return `Latest ruling ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(row.newestRecord * 1000)}`;
}

export default function LeaderboardPage() {
  const [board, setBoard] = useState<Board>('borrower');
  const [directory, setDirectory] = useState<CanonicalEvidenceDirectory | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async (background = false) => {
    if (background) setIsRefreshing(true);
    else setIsLoading(true);
    setError(null);
    try {
      setDirectory(await readCanonicalEvidenceDirectory());
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'The CC3 testnet evidence index could not be read.');
    } finally {
      if (background) setIsRefreshing(false);
      else setIsLoading(false);
    }
  };

  useEffect(() => {
    void load();
    const refresh = window.setInterval(() => void load(true), 30_000);
    return () => window.clearInterval(refresh);
  }, []);

  const current = boards[board];
  const rows = useMemo(() => groupedRows(recordsForBoard(directory, board)), [directory, board]);

  return (
    <div className="max-w-6xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-6 mb-12">
        <div>
          <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">Public evidence board</span>
          <h1 className="font-serif text-4xl sm:text-5xl text-[#111111] tracking-tight leading-[1.05]">
            Rank proof.
            <br />
            <span className="italic text-[#888888]">Never silence.</span>
          </h1>
          <p className="text-base text-[#777777] leading-relaxed mt-5 max-w-2xl">
            This public board reads canonical Bureau and Court records on CC3—not an optional receipt mint, a made-up trust score, or wallets that simply have no records.
          </p>
        </div>
        <button
          onClick={() => void load()}
          disabled={isLoading || isRefreshing}
          className="inline-flex items-center justify-center gap-2 border border-[#E5E5E5] bg-white px-4 py-3 font-mono text-[10px] uppercase tracking-widest text-[#888888] hover:border-[#111111] hover:text-[#111111] disabled:opacity-50 transition-colors"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading || isRefreshing ? 'animate-spin' : ''}`} />
          Refresh live data
        </button>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 mb-6">
        {(Object.keys(boards) as Board[]).map((key) => (
          <button
            key={key}
            onClick={() => setBoard(key)}
            className={`text-left p-4 border transition-colors ${
              board === key ? 'border-[#111111] bg-[#111111] text-white' : 'border-[#E5E5E5] bg-white text-[#111111] hover:border-[#111111]'
            }`}
          >
            <div className="font-mono text-[10px] uppercase tracking-widest">{boards[key].label}</div>
            <div className={`font-serif text-lg mt-2 ${board === key ? 'text-white' : 'text-[#111111]'}`}>{boards[key].headline}</div>
          </button>
        ))}
      </div>

      <div className="border border-[#E5E5E5] bg-[#FAF9F6] px-5 py-4 mb-6">
        <div className={`font-mono text-[10px] uppercase tracking-widest ${current.tone}`}>{current.headline}</div>
        <p className="text-sm text-[#666666] mt-2 leading-relaxed">{current.detail}</p>
      </div>

      {error && (
        <div className="mb-6 flex gap-3 border border-[#D43F3F]/30 bg-[#D43F3F]/5 p-4 text-sm text-[#D43F3F]">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <span>{error}</span>
        </div>
      )}

      {isLoading ? (
        <div className="border border-[#E5E5E5] bg-white px-6 py-16 text-center">
          <Loader2 className="w-5 h-5 animate-spin text-[#D43F3F] mx-auto mb-3" />
          <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest">Reading canonical evidence from CC3</div>
        </div>
      ) : rows.length > 0 ? (
        <div className="border border-[#E5E5E5] bg-white divide-y divide-[#E5E5E5]">
          {rows.map((row, index) => (
            <div key={row.address} className="grid grid-cols-[2.75rem_minmax(0,1fr)_auto] sm:grid-cols-[4rem_minmax(0,1fr)_10rem_9rem] items-center gap-3 sm:gap-5 p-4 sm:p-5">
              <div className="font-serif text-2xl text-[#CCCCCC]">{String(index + 1).padStart(2, '0')}</div>
              <div className="min-w-0">
                <div className="font-mono text-sm text-[#111111] truncate">{row.address}</div>
                <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest mt-1">{latestRecordLabel(row)}</div>
              </div>
              <div className="hidden sm:block">
                <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">{current.countLabel}</div>
                <div className="font-serif text-xl text-[#111111] mt-1">{row.count}</div>
              </div>
              <Link
                to={`/dashboard/check?address=${encodeURIComponent(row.address)}&role=${board === 'vault' ? 'vault-operator' : board}`}
                className="inline-flex items-center gap-2 border border-[#E5E5E5] px-3 py-2 font-mono text-[10px] uppercase tracking-widest text-[#888888] hover:border-[#111111] hover:text-[#111111] transition-colors"
              >
                <span className="hidden sm:inline">Inspect</span>
                <span className="sm:hidden">View</span>
                <ArrowRight className="w-3 h-3" />
              </Link>
            </div>
          ))}
        </div>
      ) : !error ? (
        <div className="border border-dashed border-[#CCCCCC] bg-white px-6 py-16 text-center">
          <Trophy className="w-6 h-6 text-[#CCCCCC] mx-auto mb-4" />
          <div className="font-serif text-2xl text-[#111111]">No canonical records in this lane yet.</div>
          <p className="text-sm text-[#888888] max-w-xl mx-auto mt-3 leading-relaxed">
            The first supported evidence record will appear here without waiting for anyone to mint a receipt. Prover will not fill this board with unverified names or infer a favorable score from an empty history.
          </p>
          <Link to="/dashboard/prove" className="inline-flex items-center gap-2 mt-6 font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors">
            Start a proof route <ArrowRight className="w-3 h-3" />
          </Link>
        </div>
      ) : null}

      <div className="mt-8 border-t border-[#E5E5E5] pt-6 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <p className="text-xs text-[#888888] leading-relaxed max-w-2xl">
          Auto-refreshes every 30 seconds. Unsupported today: “best” relay/vault rankings, adverse borrower rankings, and validators—none can be honestly derived from an empty record.
        </p>
        <Link to="/dashboard/check" className="inline-flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[#D43F3F] hover:text-[#111111] transition-colors shrink-0">
          Check a wallet <ArrowRight className="w-3 h-3" />
        </Link>
      </div>
    </div>
  );
}
