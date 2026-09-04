import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { useWallet } from '@/contexts/WalletContext';
import {
  ArrowRight,
  ArrowLeft,
  Shield,
  Search,
  ArrowLeftRight,
  FileCheck,
  CheckCircle2,
  AlertTriangle,
} from 'lucide-react';

const COVENANT_TYPES = [
  {
    id: 'sandwich' as const,
    title: 'No-Sandwich',
    desc: 'Relay promises not to sandwich your swaps',
    icon: Shield,
    color: 'text-[#D43F3F]',
    fields: ['poolAddress', 'maxSlippageBps', 'windowBlocks'],
  },
  {
    id: 'fifo' as const,
    title: 'FairExit FIFO',
    desc: 'Vault promises to process exits in order',
    icon: ArrowLeftRight,
    color: 'text-[#1B8A5A]',
    fields: ['vaultAddress', 'maxWindowBlocks'],
  },
  {
    id: 'rfq' as const,
    title: 'RFQ Quote',
    desc: 'Market maker honors quoted price',
    icon: Search,
    color: 'text-[#8B5CF6]',
    fields: ['pair', 'maxSpreadBps', 'expiryBlocks'],
  },
  {
    id: 'settlement' as const,
    title: 'Settlement',
    desc: 'Promise to release funds by deadline',
    icon: FileCheck,
    color: 'text-[#0EA5E9]',
    fields: ['assetAddress', 'minAmount', 'deadlineBlocks'],
  },
] as const;

type CovenantType = typeof COVENANT_TYPES[number]['id'];

const FIELD_LABELS: Record<string, { label: string; placeholder: string; help: string }> = {
  poolAddress: { label: 'Pool address', placeholder: '0x...', help: 'The Uniswap pool to protect' },
  maxSlippageBps: { label: 'Max slippage (bps)', placeholder: '50', help: 'Maximum allowed slippage in basis points' },
  windowBlocks: { label: 'Protection window (blocks)', placeholder: '25', help: 'How many blocks the covenant covers' },
  vaultAddress: { label: 'Vault address', placeholder: '0x...', help: 'The vault contract to enforce FIFO on' },
  maxWindowBlocks: { label: 'Max processing window (blocks)', placeholder: '50', help: 'Maximum blocks before exit expires' },
  pair: { label: 'Trading pair', placeholder: 'ETH/USDC', help: 'The pair the RFQ covers' },
  maxSpreadBps: { label: 'Max spread (bps)', placeholder: '30', help: 'Maximum allowed spread from mid-price' },
  expiryBlocks: { label: 'Quote expiry (blocks)', placeholder: '10', help: 'How long the quote must be honored' },
  assetAddress: { label: 'Asset address', placeholder: '0x...', help: 'The ERC-20 token to be settled' },
  minAmount: { label: 'Minimum amount', placeholder: '1000000', help: 'Smallest amount that must be delivered' },
  deadlineBlocks: { label: 'Deadline (blocks)', placeholder: '100', help: 'Blocks until settlement is due' },
};

export default function CovenantPage() {
  const { address } = useWallet();
  const [step, setStep] = useState(0);
  const [covenantType, setCovenantType] = useState<CovenantType | null>(null);
  const [counterparty, setCounterparty] = useState('');
  const [collateral, setCollateral] = useState('');
  const [fields, setFields] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const selectedType = COVENANT_TYPES.find((t) => t.id === covenantType);
  const requiredFields = selectedType?.fields ?? [];

  const canProceed = () => {
    if (step === 0) return counterparty.startsWith('0x') && counterparty.length === 42;
    if (step === 1) return covenantType !== null;
    if (step === 2) return requiredFields.every((f) => fields[f]?.trim());
    if (step === 3) return parseFloat(collateral) > 0;
    return true;
  };

  const handleSubmit = async () => {
    setIsSubmitting(true);
    // Simulate transaction
    await new Promise((r) => setTimeout(r, 2000));
    setIsSubmitting(false);
    setSubmitted(true);
  };

  const steps = ['Counterparty', 'Type', 'Terms', 'Collateral', 'Review'];

  return (
    <div className="max-w-3xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      {/* Header */}
      <div className="mb-10">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
          Create Covenant
        </span>
        <h1 className="font-serif text-3xl sm:text-4xl lg:text-5xl text-[#111111] tracking-tight leading-[1.1]">
          Open a bonded{' '}
          <span className="italic text-[#888888]">promise</span>
        </h1>
      </div>

      {/* Success State */}
      {submitted && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 p-8 text-center"
        >
          <CheckCircle2 className="w-12 h-12 text-[#1B8A5A] mx-auto mb-4" />
          <h2 className="font-serif text-2xl text-[#111111] mb-2">Covenant opened</h2>
          <p className="text-sm text-[#888888] mb-6">
            Your bonded promise is now live on CC3 testnet. The counterparty must authorize before it activates.
          </p>
          <button
            onClick={() => {
              setStep(0);
              setCovenantType(null);
              setCounterparty('');
              setCollateral('');
              setFields({});
              setSubmitted(false);
            }}
            className="border border-[#111111] px-6 py-3 font-mono text-xs uppercase tracking-[0.15em] text-[#111111] hover:bg-[#111111] hover:text-white transition-all duration-300"
          >
            Create another
          </button>
        </motion.div>
      )}

      {/* Wizard */}
      {!submitted && (
        <>
          {/* Step indicator */}
          <div className="flex items-center gap-2 mb-10 overflow-x-auto pb-2">
            {steps.map((s, i) => (
              <div key={s} className="flex items-center gap-2 shrink-0">
                <div
                  className={`w-7 h-7 flex items-center justify-center font-mono text-[10px] font-bold border transition-all ${
                    i < step
                      ? 'border-[#1B8A5A] bg-[#1B8A5A] text-white'
                      : i === step
                      ? 'border-[#111111] bg-[#111111] text-white'
                      : 'border-[#E5E5E5] text-[#CCCCCC]'
                  }`}
                >
                  {i < step ? '✓' : i + 1}
                </div>
                <span className={`font-mono text-[10px] uppercase tracking-widest ${
                  i === step ? 'text-[#111111]' : 'text-[#CCCCCC]'
                }`}>
                  {s}
                </span>
                {i < steps.length - 1 && (
                  <div className={`w-8 h-px ${i < step ? 'bg-[#1B8A5A]' : 'bg-[#E5E5E5]'}`} />
                )}
              </div>
            ))}
          </div>

          {/* Step content */}
          <AnimatePresence mode="wait">
            <motion.div
              key={step}
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -20 }}
              transition={{ duration: 0.2 }}
            >
              {/* Step 0: Counterparty */}
              {step === 0 && (
                <div>
                  <h2 className="font-serif text-2xl text-[#111111] mb-2">Who is the other party?</h2>
                  <p className="text-sm text-[#888888] mb-8">Enter the address of the counterparty who will sign this covenant.</p>
                  <label className="block font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-2">
                    Counterparty address
                  </label>
                  <input
                    type="text"
                    value={counterparty}
                    onChange={(e) => setCounterparty(e.target.value)}
                    placeholder="0x..."
                    className="w-full border border-[#E5E5E5] bg-white px-4 py-3 font-mono text-sm text-[#111111] placeholder:text-[#CCCCCC] focus:outline-none focus:border-[#111111] transition-colors"
                  />
                  <div className="font-mono text-[10px] text-[#CCCCCC] mt-2">
                    Must be a valid Ethereum address (0x + 40 hex chars)
                  </div>
                  {counterparty && counterparty.length === 42 && counterparty.startsWith('0x') && (
                    <div className="mt-4 p-3 border border-[#1B8A5A]/30 bg-[#1B8A5A]/5 font-mono text-xs text-[#1B8A5A]">
                      Valid address format
                    </div>
                  )}
                </div>
              )}

              {/* Step 1: Type Selection */}
              {step === 1 && (
                <div>
                  <h2 className="font-serif text-2xl text-[#111111] mb-2">What are you promising?</h2>
                  <p className="text-sm text-[#888888] mb-8">Select the type of covenant you want to open.</p>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {COVENANT_TYPES.map((type) => (
                      <button
                        key={type.id}
                        onClick={() => setCovenantType(type.id)}
                        className={`text-left p-5 border transition-all duration-200 ${
                          covenantType === type.id
                            ? 'border-[#111111] bg-[#111111] text-white'
                            : 'border-[#E5E5E5] bg-white text-[#111111] hover:border-[#111111]'
                        }`}
                      >
                        <type.icon className={`w-5 h-5 mb-3 ${covenantType === type.id ? 'text-white' : type.color}`} strokeWidth={1.5} />
                        <div className={`font-serif text-lg mb-1 ${covenantType === type.id ? 'text-white' : 'text-[#111111]'}`}>
                          {type.title}
                        </div>
                        <div className={`text-xs ${covenantType === type.id ? 'text-white/60' : 'text-[#888888]'}`}>
                          {type.desc}
                        </div>
                      </button>
                    ))}
                  </div>
                </div>
              )}

              {/* Step 2: Terms */}
              {step === 2 && selectedType && (
                <div>
                  <h2 className="font-serif text-2xl text-[#111111] mb-2">Define the terms</h2>
                  <p className="text-sm text-[#888888] mb-8">
                    Set the specific conditions for your {selectedType.title} covenant.
                  </p>
                  <div className="space-y-5">
                    {requiredFields.map((fieldKey) => {
                      const field = FIELD_LABELS[fieldKey];
                      return (
                        <div key={fieldKey}>
                          <label className="block font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-1.5">
                            {field.label}
                          </label>
                          <input
                            type="text"
                            value={fields[fieldKey] ?? ''}
                            onChange={(e) => setFields({ ...fields, [fieldKey]: e.target.value })}
                            placeholder={field.placeholder}
                            className="w-full border border-[#E5E5E5] bg-white px-4 py-3 font-mono text-sm text-[#111111] placeholder:text-[#CCCCCC] focus:outline-none focus:border-[#111111] transition-colors"
                          />
                          <div className="font-mono text-[10px] text-[#CCCCCC] mt-1">{field.help}</div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Step 3: Collateral */}
              {step === 3 && (
                <div>
                  <h2 className="font-serif text-2xl text-[#111111] mb-2">Set the bond</h2>
                  <p className="text-sm text-[#888888] mb-8">
                    Both parties lock CTC as collateral. If the covenant is breached, the victim receives the bond.
                  </p>
                  <label className="block font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-2">
                    Collateral amount (CTC)
                  </label>
                  <input
                    type="text"
                    value={collateral}
                    onChange={(e) => setCollateral(e.target.value)}
                    placeholder="100"
                    className="w-full border border-[#E5E5E5] bg-white px-4 py-3 font-mono text-sm text-[#111111] placeholder:text-[#CCCCCC] focus:outline-none focus:border-[#111111] transition-colors"
                  />
                  <div className="font-mono text-[10px] text-[#CCCCCC] mt-2">
                    Both you and the counterparty will lock this amount
                  </div>
                  {collateral && parseFloat(collateral) > 0 && (
                    <div className="mt-4 p-4 border border-[#E5E5E5] bg-[#FAF9F6]">
                      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Summary</div>
                      <div className="grid grid-cols-2 gap-4 text-xs">
                        <div>
                          <span className="text-[#AAAAAA]">Your bond:</span>
                          <span className="font-mono font-bold text-[#111111] ml-2">{collateral} CTC</span>
                        </div>
                        <div>
                          <span className="text-[#AAAAAA]">Their bond:</span>
                          <span className="font-mono font-bold text-[#111111] ml-2">{collateral} CTC</span>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* Step 4: Review */}
              {step === 4 && selectedType && (
                <div>
                  <h2 className="font-serif text-2xl text-[#111111] mb-2">Review & sign</h2>
                  <p className="text-sm text-[#888888] mb-8">
                    Confirm all details before submitting. This will open a wallet signature request.
                  </p>
                  <div className="space-y-4">
                    <div className="p-4 border border-[#E5E5E5] bg-white">
                      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Type</div>
                      <div className="font-serif text-lg text-[#111111]">{selectedType.title}</div>
                    </div>
                    <div className="p-4 border border-[#E5E5E5] bg-white">
                      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Counterparty</div>
                      <div className="font-mono text-xs text-[#111111] break-all">{counterparty}</div>
                    </div>
                    <div className="p-4 border border-[#E5E5E5] bg-white">
                      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Terms</div>
                      <div className="space-y-1">
                        {requiredFields.map((f) => (
                          <div key={f} className="flex justify-between text-xs">
                            <span className="text-[#888888]">{FIELD_LABELS[f].label}</span>
                            <span className="font-mono text-[#111111]">{fields[f]}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                    <div className="p-4 border border-[#E5E5E5] bg-white">
                      <div className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-widest mb-2">Collateral</div>
                      <div className="font-serif text-2xl text-[#111111]">{collateral} CTC</div>
                      <div className="font-mono text-[10px] text-[#AAAAAA] mt-1">
                        Total locked: {collateral} CTC (you) + {collateral} CTC (them)
                      </div>
                    </div>
                  </div>

                  <div className="mt-6 p-4 border border-[#D43F3F]/30 bg-[#D43F3F]/5">
                    <div className="flex items-start gap-3">
                      <AlertTriangle className="w-4 h-4 text-[#D43F3F] shrink-0 mt-0.5" />
                      <div className="text-xs text-[#888888]">
                        This action requires a wallet signature and will submit a transaction to CC3 testnet. CTC collateral will be locked until the covenant expires or is resolved.
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>

          {/* Navigation */}
          <div className="flex items-center justify-between mt-10 pt-6 border-t border-[#E5E5E5]">
            <button
              onClick={() => setStep((s) => s - 1)}
              disabled={step === 0}
              className={`flex items-center gap-2 font-mono text-xs uppercase tracking-[0.15em] transition-colors ${
                step === 0
                  ? 'text-[#CCCCCC] cursor-not-allowed'
                  : 'text-[#888888] hover:text-[#111111]'
              }`}
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              Back
            </button>

            {step < 4 ? (
              <button
                onClick={() => setStep((s) => s + 1)}
                disabled={!canProceed()}
                className={`flex items-center gap-2 border border-[#111111] px-6 py-3 font-mono text-xs uppercase tracking-[0.15em] transition-all duration-300 ${
                  canProceed()
                    ? 'bg-[#111111] text-white hover:bg-[#D43F3F] hover:border-[#D43F3F]'
                    : 'bg-[#FAF9F6] text-[#CCCCCC] border-[#E5E5E5] cursor-not-allowed'
                }`}
              >
                Continue
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            ) : (
              <button
                onClick={handleSubmit}
                disabled={isSubmitting}
                className={`flex items-center gap-2 border border-[#111111] px-8 py-3 font-mono text-xs uppercase tracking-[0.15em] transition-all duration-300 ${
                  isSubmitting
                    ? 'bg-[#FAF9F6] text-[#BBBBBB] border-[#E5E5E5] cursor-wait'
                    : 'bg-[#111111] text-white hover:bg-[#1B8A5A] hover:border-[#1B8A5A]'
                }`}
              >
                {isSubmitting ? (
                  <>
                    <span className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    Signing...
                  </>
                ) : (
                  <>
                    Sign & Submit
                    <ArrowRight className="w-3.5 h-3.5" />
                  </>
                )}
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
}
