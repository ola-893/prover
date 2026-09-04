import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { EVIDENCE_SCENARIOS } from '../data/mockIncidents';
import {
  Play,
  RotateCcw,
  CheckCircle2,
  Copy,
} from 'lucide-react';

export default function EvidenceSimulator() {
  const [selectedScenarioId, setSelectedScenarioId] = useState<string>('sandwich-arbitrum');
  const [activeTab, setActiveTab] = useState<'TRACE' | 'PROOF' | 'EXECUTE'>('TRACE');
  const [isVerifying, setIsVerifying] = useState(false);
  const [verificationComplete, setVerificationComplete] = useState(false);
  const [copiedHash, setCopiedHash] = useState(false);

  const scenario = EVIDENCE_SCENARIOS.find((s) => s.id === selectedScenarioId) || EVIDENCE_SCENARIOS[0];

  const handleSimulateVerification = () => {
    setIsVerifying(true);
    setVerificationComplete(false);
    setTimeout(() => {
      setIsVerifying(false);
      setVerificationComplete(true);
    }, 1200);
  };

  const handleReset = () => {
    setIsVerifying(false);
    setVerificationComplete(false);
  };

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedHash(true);
    setTimeout(() => setCopiedHash(false), 2000);
  };

  return (
    <div className="max-w-5xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      {/* Header */}
      <div className="mb-12">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
          Evidence Terminal
        </span>
        <h1 className="font-serif text-3xl sm:text-4xl lg:text-5xl text-[#111111] tracking-tight leading-[1.1]">
          On-chain evidence{' '}
          <span className="italic text-[#888888]">& enforcement</span>
        </h1>
        <p className="text-sm text-[#888888] mt-3 max-w-2xl">
          Test the verification engine against authenticated transaction traces. Inspect Merkle-order proofs and deterministic breach predicates.
        </p>
      </div>

      {/* Scenario Selector */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-8">
        {EVIDENCE_SCENARIOS.map((item) => {
          const isSelected = item.id === selectedScenarioId;
          return (
            <button
              key={item.id}
              onClick={() => {
                setSelectedScenarioId(item.id);
                handleReset();
              }}
              className={`text-left p-5 border transition-all duration-200 ${
                isSelected
                  ? 'border-[#111111] bg-[#111111] text-white'
                  : 'border-[#E5E5E5] bg-white text-[#111111] hover:border-[#111111]'
              }`}
            >
              <div className="flex items-center justify-between mb-3">
                <span className={`font-mono text-[9px] uppercase tracking-widest px-2 py-0.5 ${
                  isSelected
                    ? 'bg-white text-[#111111]'
                    : 'bg-[#FAF9F6] text-[#D43F3F] border border-[#E5E5E5]'
                }`}>
                  {item.category === 'VIOLATION' ? 'BREACH' : 'PERFORMANCE'}
                </span>
                <span className={`font-mono text-[10px] ${isSelected ? 'text-white/40' : 'text-[#CCCCCC]'}`}>
                  {item.chain}
                </span>
              </div>
              <div className={`font-serif text-lg mb-1 truncate ${isSelected ? 'text-white' : 'text-[#111111]'}`}>
                {item.title}
              </div>
              <div className={`font-mono text-[10px] truncate ${isSelected ? 'text-white/50' : 'text-[#BBBBBB]'}`}>
                {item.targetProtocol}
              </div>
            </button>
          );
        })}
      </div>

      {/* Terminal */}
      <div className="border border-[#E5E5E5] bg-white overflow-hidden">
        {/* Top Bar */}
        <div className="flex flex-wrap items-center justify-between px-5 py-3 border-b border-[#E5E5E5] gap-3">
          <div className="flex items-center gap-3">
            <span className="w-2 h-2 rounded-full bg-[#D43F3F] animate-pulse" />
            <span className="font-mono text-xs text-[#111111] font-bold uppercase tracking-wider">
              {scenario.id}
            </span>
            <span className="text-[#E5E5E5]">·</span>
            <span className="font-mono text-[10px] text-[#BBBBBB]">
              Block #{scenario.blockNumber}
            </span>
          </div>

          {/* Tabs */}
          <div className="flex border border-[#E5E5E5]">
            {(['TRACE', 'PROOF', 'EXECUTE'] as const).map((tab, i) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`px-4 py-1.5 font-mono text-[10px] uppercase tracking-widest transition-all ${
                  i > 0 ? 'border-l border-[#E5E5E5]' : ''
                } ${
                  activeTab === tab
                    ? 'bg-[#111111] text-white'
                    : 'text-[#BBBBBB] hover:text-[#111111]'
                }`}
              >
                {tab === 'TRACE' ? 'Mempool Trace' : tab === 'PROOF' ? 'Merkle Proof' : 'Execute'}
              </button>
            ))}
          </div>
        </div>

        {/* Incident Overview */}
        <div className="px-5 py-4 border-b border-[#E5E5E5] flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-1">
              Rule Invariant
            </div>
            <div className="font-mono text-xs text-[#111111] font-bold">{scenario.violationRule}</div>
            <p className="text-xs text-[#888888] mt-1 max-w-2xl">{scenario.summary}</p>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={handleReset}
              disabled={isVerifying}
              className="p-2 border border-[#E5E5E5] hover:border-[#111111] text-[#AAAAAA] hover:text-[#111111] transition-colors"
            >
              <RotateCcw className="w-4 h-4" />
            </button>
            <button
              onClick={handleSimulateVerification}
              disabled={isVerifying}
              className={`inline-flex items-center gap-2 px-5 py-2 font-mono text-[10px] uppercase tracking-widest font-bold border transition-all duration-300 ${
                verificationComplete
                  ? 'border-[#1B8A5A] bg-[#1B8A5A] text-white'
                  : isVerifying
                  ? 'border-[#E5E5E5] bg-[#FAF9F6] text-[#BBBBBB] cursor-wait'
                  : 'border-[#111111] bg-[#111111] text-white hover:bg-[#D43F3F] hover:border-[#D43F3F]'
              }`}
            >
              {isVerifying ? (
                <>
                  <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Verifying...
                </>
              ) : verificationComplete ? (
                <>
                  <CheckCircle2 className="w-3.5 h-3.5" />
                  Finalized
                </>
              ) : (
                <>
                  <Play className="w-3 h-3 fill-current" />
                  Verify & Execute
                </>
              )}
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="p-5">
          {/* Mempool Trace */}
          {activeTab === 'TRACE' && (
            <div className="space-y-5">
              {/* Stats */}
              <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                {[
                  { label: 'Bonded Collateral', value: scenario.bondedCollateral },
                  { label: scenario.category === 'VIOLATION' ? 'Slashing Forfeit' : 'Performance Rebate', value: scenario.slashedAmount, red: true },
                  { label: 'Victim Recovery', value: scenario.victimRecovery },
                  { label: 'Proof Type', value: scenario.evidenceProofType },
                ].map((stat) => (
                  <div key={stat.label} className="p-3 border border-[#E5E5E5]">
                    <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">{stat.label}</div>
                    <div className={`font-serif text-lg mt-1 ${stat.red ? 'text-[#D43F3F]' : 'text-[#111111]'}`}>
                      {stat.value}
                    </div>
                  </div>
                ))}
              </div>

              {/* Transaction Trace */}
              <div className="border border-[#E5E5E5] divide-y divide-[#E5E5E5]">
                {scenario.mempoolTrace.map((step) => {
                  const isBreach = step.status === 'BREACH';
                  const isSettled = step.status === 'SETTLED';
                  return (
                    <div
                      key={step.step}
                      className={`p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs ${
                        isBreach ? 'bg-[#D43F3F]/[0.03] border-l-2 border-l-[#D43F3F]' : ''
                      } ${verificationComplete && isSettled ? 'bg-[#1B8A5A]/[0.03] border-l-2 border-l-[#1B8A5A]' : ''}`}
                    >
                      <div className="flex items-start gap-3">
                        <div className="w-6 h-6 shrink-0 flex items-center justify-center font-mono text-[10px] font-bold border border-[#E5E5E5] text-[#111111]">
                          {step.step}
                        </div>
                        <div>
                          <div className="flex items-center gap-2">
                            <span className="font-mono font-bold text-[#111111] uppercase tracking-wider">
                              {step.action}
                            </span>
                            <span className="text-[#E5E5E5]">·</span>
                            <span className="font-mono text-[10px] text-[#BBBBBB]">{step.timestampOffset}</span>
                          </div>
                          <p className="text-[#888888] mt-0.5">{step.detail}</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 self-end sm:self-center shrink-0">
                        <span className="font-mono text-[10px] text-[#AAAAAA] px-2 py-1 border border-[#E5E5E5]">
                          {step.gasPrice}
                        </span>
                        <span className={`font-mono text-[9px] font-bold uppercase tracking-widest px-2 py-1 ${
                          isBreach
                            ? 'border border-[#D43F3F]/30 bg-[#D43F3F]/5 text-[#D43F3F]'
                            : isSettled
                            ? 'border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 text-[#1B8A5A]'
                            : 'border border-[#E5E5E5] text-[#AAAAAA]'
                        }`}>
                          {step.status}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Merkle Proof */}
          {activeTab === 'PROOF' && (
            <div className="space-y-4">
              <div className="p-4 border border-[#E5E5E5]">
                <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-3">
                  Merkle-order verification
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {[
                    { label: 'Root Hash', value: scenario.zkProofMetrics.hashRoot },
                    { label: 'Epoch', value: `Block ${scenario.blockNumber}` },
                    { label: 'Position', value: `${scenario.mempoolTrace.length} txs in sequence` },
                    { label: 'Predicate', value: scenario.violationRule },
                  ].map((item) => (
                    <div key={item.label}>
                      <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">{item.label}</div>
                      <div className="font-mono text-xs text-[#111111] mt-1 break-all">{item.value}</div>
                    </div>
                  ))}
                </div>
              </div>
              <div className="p-4 border border-[#E5E5E5] font-mono text-[11px]">
                <div className="text-[#BBBBBB] text-[10px] uppercase tracking-widest mb-2">Public inputs:</div>
                <div className="p-3 bg-[#FAF9F6] border border-[#E5E5E5] overflow-x-auto text-[#555555]">
{`{
  "merkle_root": "${scenario.zkProofMetrics.hashRoot}",
  "violation_invariant": "${scenario.violationRule}",
  "block_height": ${scenario.blockNumber},
  "tx_count": ${scenario.mempoolTrace.length},
  "outcome": "PROVED_BREACH_VALID"
}`}
                </div>
              </div>
            </div>
          )}

          {/* Execute */}
          {activeTab === 'EXECUTE' && (
            <div className="space-y-4">
              <div className="p-4 border border-[#E5E5E5]">
                <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">
                  Contract call
                </div>
                <div className="font-mono text-xs text-[#111111] break-all">
                  ProverEnforcementHub.executeSlash(bytes32 proofHash, address victim, uint256 amount)
                </div>
              </div>
              <div className="p-4 border border-[#E5E5E5] font-mono text-[11px]">
                <div className="text-[#BBBBBB] text-[10px] uppercase tracking-widest mb-2">Calldata:</div>
                <div className="p-3 bg-[#FAF9F6] border border-[#E5E5E5] overflow-x-auto text-[#555555]">
                  0x71c8a993000000000000000000000000{scenario.victimAddress.slice(2, 14)}...
                </div>
              </div>
              <button
                onClick={() => handleCopy('0x71c8a993')}
                className="inline-flex items-center gap-2 px-4 py-2 border border-[#E5E5E5] hover:border-[#111111] font-mono text-[10px] uppercase tracking-widest text-[#888888] hover:text-[#111111] transition-colors"
              >
                <Copy className="w-3 h-3" />
                {copiedHash ? 'Copied' : 'Copy calldata'}
              </button>
            </div>
          )}
        </div>

        {/* Status Bar */}
        <div className="px-5 py-3 border-t border-[#E5E5E5] flex flex-col sm:flex-row sm:items-center justify-between gap-2 font-mono text-[10px] text-[#BBBBBB]">
          <div className="flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-[#1B8A5A]" />
            <span>Verifier deployed on CC3 testnet</span>
          </div>
          <span>Gas: {scenario.zkProofMetrics.verifierGas}</span>
        </div>
      </div>
    </div>
  );
}
