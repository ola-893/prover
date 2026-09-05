import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  proofEngines,
  proofEngineById,
  type ProofEngineId,
  publicAaveCase,
} from '@/lib/proof-engines';
import { classifyProofIntent, type PreflightResult } from '@/lib/proof-router';
import { runProofPreflight, validatePreflightRequest } from '@/lib/proof-preflight';
import {
  ArrowRight,
  CheckCircle2,
  AlertTriangle,
  Search,
  ExternalLink,
  Loader2,
} from 'lucide-react';

export default function ProofRouter() {
  const [searchParams] = useSearchParams();
  const [intent, setIntent] = useState('');
  const [classification, setClassification] = useState<{
    engineId: ProofEngineId | null;
    confidence: 'high' | 'medium' | 'none';
    reason: string;
  } | null>(null);
  const [selectedEngine, setSelectedEngine] = useState<ProofEngineId | null>(null);
  const [inputs, setInputs] = useState<Record<string, string>>({});
  const [preflightResult, setPreflightResult] = useState<PreflightResult | null>(null);
  const [isPreflighting, setIsPreflighting] = useState(false);
  const [preflightError, setPreflightError] = useState<string | null>(null);

  const handleClassify = () => {
    const result = classifyProofIntent(intent);
    setClassification(result);
    if (result.engineId) setSelectedEngine(result.engineId);
  };

  useEffect(() => {
    const path = searchParams.get('path');
    if (path === 'incident') {
      setIntent('I want to prove a sandwich attack or a FairExit queue inversion');
      setSelectedEngine('sandwich');
    }
    if (path === 'performance') {
      setIntent('I want to prove selected Aave repayment performance');
      setSelectedEngine('aave-performance');
    }
  }, [searchParams]);

  const handleSelectEngine = (id: ProofEngineId) => {
    setSelectedEngine(id);
    setInputs({});
    setPreflightResult(null);
    setPreflightError(null);
  };

  const handleLoadPublicCase = () => {
    if (selectedEngine === 'aave-performance') {
      setInputs({
        wallet: publicAaveCase.wallet,
        borrowTxHash: publicAaveCase.borrowTxHash,
        repayTxHash: publicAaveCase.repayTxHash,
        borrowReceiptLogOrdinal: publicAaveCase.borrowReceiptLogOrdinal,
        repayReceiptLogOrdinal: publicAaveCase.repayReceiptLogOrdinal,
      });
    }
  };

  const handlePreflight = async () => {
    if (!selectedEngine) return;
    setIsPreflighting(true);
    setPreflightError(null);
    setPreflightResult(null);
    try {
      const request = validatePreflightRequest({ engineId: selectedEngine, inputs });
      setPreflightResult(await runProofPreflight(request));
    } catch (err: any) {
      setPreflightError(err?.message ?? 'Network error');
    } finally {
      setIsPreflighting(false);
    }
  };

  const engine = selectedEngine ? proofEngineById(selectedEngine) : null;

  return (
    <div className="max-w-5xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      {/* Header */}
      <div className="mb-12">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
          Deterministic proof router
        </span>
        <h1 className="font-serif text-3xl sm:text-4xl lg:text-5xl text-[#111111] tracking-tight leading-[1.1]">
          What do you want to{' '}
          <span className="italic text-[#888888]">prove</span>?
        </h1>
        <p className="text-sm text-[#888888] max-w-2xl mt-4 leading-relaxed">
          Choose a supported fact. The router only prepares evidence and reads eligibility; a court or adapter is the only component that can create a final record.
        </p>
      </div>

      {/* Intent Input */}
      <div className="mb-10">
        <label className="block font-mono text-[10px] text-[#AAAAAA] uppercase tracking-[0.2em] mb-3">
          Describe what you want to prove
        </label>
        <div className="flex gap-3">
          <textarea
            value={intent}
            onChange={(e) => setIntent(e.target.value)}
            placeholder="e.g. A relay sandwiched my swap; a vault skipped my exit; or I want to document an Aave repayment"
            className="flex-1 border border-[#E5E5E5] bg-white p-4 font-mono text-sm text-[#111111] placeholder:text-[#CCCCCC] resize-none h-24 focus:outline-none focus:border-[#111111] transition-colors"
          />
          <button
            onClick={handleClassify}
            className="self-start border border-[#111111] px-5 py-3 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300 flex items-center gap-2"
          >
            <Search className="w-3.5 h-3.5" />
            Route
          </button>
        </div>
        {classification && (
          <div className={`mt-3 px-4 py-3 font-mono text-xs ${
            classification.confidence === 'high'
              ? 'border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 text-[#1B8A5A]'
              : classification.confidence === 'medium'
              ? 'border border-[#D43F3F]/30 bg-[#D43F3F]/5 text-[#D43F3F]'
              : 'border border-[#E5E5E5] bg-[#FAF9F6] text-[#888888]'
          }`}>
            <span className="font-bold uppercase">{classification.confidence} confidence:</span>{' '}
            {classification.reason}
          </div>
        )}
      </div>

      {/* Engine Selector */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-10">
        {proofEngines.map((eng) => (
          <button
            key={eng.id}
            onClick={() => handleSelectEngine(eng.id)}
            className={`text-left p-5 border transition-all duration-200 ${
              selectedEngine === eng.id
                ? 'border-[#111111] bg-[#111111] text-white'
                : 'border-[#E5E5E5] bg-white text-[#111111] hover:border-[#111111]'
            }`}
          >
            <div className="flex items-center justify-between mb-3">
              <span className={`font-mono text-[9px] uppercase tracking-widest px-2 py-0.5 ${
                selectedEngine === eng.id
                  ? 'bg-white text-[#111111]'
                  : 'bg-[#FAF9F6] text-[#D43F3F] border border-[#E5E5E5]'
              }`}>
                {eng.mode === 'breach' ? 'BREACH' : 'PERFORMANCE'}
              </span>
              {eng.flagship && (
                <span className={`font-mono text-[9px] ${selectedEngine === eng.id ? 'text-white/40' : 'text-[#CCCCCC]'}`}>
                  FLAGSHIP
                </span>
              )}
            </div>
            <div className={`font-serif text-lg mb-1 ${selectedEngine === eng.id ? 'text-white' : 'text-[#111111]'}`}>
              {eng.shortLabel}
            </div>
            <div className={`font-mono text-[10px] ${selectedEngine === eng.id ? 'text-white/50' : 'text-[#BBBBBB]'}`}>
              {eng.specialist}
            </div>
          </button>
        ))}
      </div>

      {/* Engine Detail + Preflight Form */}
      {engine && (
        <div className="border border-[#E5E5E5] bg-white mb-10">
          <div className="p-6 border-b border-[#E5E5E5]">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="font-serif text-xl sm:text-2xl text-[#111111]">{engine.label}</h2>
                <p className="text-sm text-[#888888] mt-1">{engine.goal}</p>
              </div>
              <a
                href={`${engine.deployment.network === 'Creditcoin CC3 Testnet' ? 'https://creditcoin-testnet.blockscout.com' : 'https://sepolia.etherscan.io'}/address/${engine.deployment.contractAddress}`}
                target="_blank"
                rel="noopener noreferrer"
                className="font-mono text-[10px] text-[#BBBBBB] hover:text-[#111111] flex items-center gap-1 transition-colors"
              >
                {engine.deployment.contractLabel}
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 divide-y lg:divide-y-0 lg:divide-x divide-[#E5E5E5]">
            {/* Evidence Requirements */}
            <div className="p-6">
              <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-4">
                Evidence Requirements
              </h3>
              <ul className="space-y-2.5">
                {engine.evidence.map((req, i) => (
                  <li key={i} className="flex items-start gap-2.5 text-xs text-[#666666]">
                    <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 text-[#1B8A5A] shrink-0" />
                    {req}
                  </li>
                ))}
              </ul>
              <div className="mt-6 p-4 bg-[#FAF9F6] border border-[#E5E5E5]">
                <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">If proven</div>
                <div className="text-xs text-[#111111] mt-1.5">{engine.consequence}</div>
              </div>
              <div className="mt-3 p-4 bg-[#FAF9F6] border border-[#E5E5E5]">
                <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">Evidence boundary</div>
                <div className="text-xs text-[#888888] mt-1.5">{engine.boundary}</div>
              </div>
            </div>

            {/* Preflight Form */}
            <div className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em]">
                Live Read-Only Preflight
                </h3>
                {selectedEngine === 'aave-performance' && (
                  <button
                    onClick={handleLoadPublicCase}
                    className="font-mono text-[10px] text-[#D43F3F] hover:text-[#111111] uppercase tracking-widest transition-colors"
                  >
                    Load public Aave case
                  </button>
                )}
              </div>
              <div className="space-y-4">
                {engine.inputs.map((input) => (
                  <div key={input.key}>
                    <label className="block font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest mb-1.5">
                      {input.label}
                    </label>
                    <input
                      type="text"
                      value={inputs[input.key] ?? ''}
                      onChange={(e) => setInputs({ ...inputs, [input.key]: e.target.value })}
                      placeholder={input.placeholder}
                      className="w-full border border-[#E5E5E5] bg-[#FAF9F6] px-3 py-2.5 font-mono text-xs text-[#111111] placeholder:text-[#CCCCCC] focus:outline-none focus:border-[#111111] transition-colors"
                    />
                    <div className="font-mono text-[9px] text-[#CCCCCC] mt-1">{input.help}</div>
                  </div>
                ))}
              </div>
              <button
                onClick={handlePreflight}
                disabled={isPreflighting}
                className={`mt-6 w-full border border-[#111111] px-6 py-3 font-mono text-xs uppercase tracking-[0.15em] transition-all duration-300 flex items-center justify-center gap-2 ${
                  isPreflighting
                    ? 'bg-[#FAF9F6] text-[#BBBBBB] cursor-wait'
                    : 'bg-[#111111] text-white hover:bg-[#D43F3F] hover:border-[#D43F3F]'
                }`}
              >
                {isPreflighting ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Running preflight...
                  </>
                ) : (
                  <>
                    Run Preflight Check
                    <ArrowRight className="w-3.5 h-3.5" />
                  </>
                )}
              </button>
              <p className="mt-3 font-mono text-[9px] text-[#CCCCCC] text-center">
                Reads the public proof builder and CC3 contracts directly. It cannot accuse, settle, mint, or alter any record.
              </p>
            </div>
          </div>

          {/* Preflight Results */}
          {(preflightResult || preflightError) && (
            <div className="border-t border-[#E5E5E5] p-6">
              {preflightError ? (
                <div className="p-4 border border-[#D43F3F]/30 bg-[#D43F3F]/5 font-mono text-xs text-[#D43F3F]">
                  <AlertTriangle className="w-4 h-4 inline mr-2" />
                  {preflightError}
                </div>
              ) : preflightResult && (
                <div>
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em]">
                      Preflight Result
                    </h3>
                    <span className={`font-mono text-[10px] font-bold uppercase px-2 py-1 ${
                      preflightResult.status === 'ready_to_verify'
                        ? 'border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 text-[#1B8A5A]'
                        : 'border border-[#D43F3F]/30 bg-[#D43F3F]/5 text-[#D43F3F]'
                    }`}>
                      {preflightResult.status.replace(/_/g, ' ')}
                    </span>
                  </div>
                  <div className="font-serif text-lg text-[#111111] mb-2">{preflightResult.headline}</div>
                  <p className="text-sm text-[#888888] mb-5">{preflightResult.summary}</p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                    {preflightResult.gates.map((gate) => (
                      <div key={gate.id} className={`p-3 border font-mono text-xs ${
                        gate.status === 'pass' ? 'border-[#1B8A5A]/20 bg-[#1B8A5A]/5' :
                        gate.status === 'fail' ? 'border-[#D43F3F]/20 bg-[#D43F3F]/5' :
                        gate.status === 'warning' ? 'border-[#D43F3F]/20 bg-[#D43F3F]/5' :
                        'border-[#E5E5E5] bg-[#FAF9F6]'
                      }`}>
                        <div className="flex items-center justify-between mb-1">
                          <span className="font-bold text-[#111111]">{gate.label}</span>
                          <span className={`text-[9px] uppercase font-bold tracking-widest ${
                            gate.status === 'pass' ? 'text-[#1B8A5A]' :
                            gate.status === 'fail' ? 'text-[#D43F3F]' :
                            'text-[#888888]'
                          }`}>
                            {gate.status}
                          </span>
                        </div>
                        <div className="text-[#888888]">{gate.detail}</div>
                      </div>
                    ))}
                  </div>
                  {preflightResult.packets && preflightResult.packets.length > 0 && (
                    <div className="mt-5 border border-[#E5E5E5] divide-y divide-[#E5E5E5]">
                      {preflightResult.packets.map((pkt, i) => (
                        <div key={i} className="p-3 font-mono text-xs flex items-center justify-between">
                          <div>
                            <span className="font-bold text-[#111111]">{pkt.role}</span>
                            <span className="text-[#BBBBBB] ml-2">{pkt.txHash.slice(0, 18)}...</span>
                          </div>
                          <div className="text-[#AAAAAA]">
                            Block #{pkt.blockHeight.toLocaleString()} · Index {pkt.txIndex}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
