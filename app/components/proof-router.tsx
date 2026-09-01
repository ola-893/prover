'use client';

import { useEffect, useRef, useState } from 'react';
import {
  ArrowRight,
  Check,
  CheckCircle2,
  CircleAlert,
  ExternalLink,
  FileSearch,
  Gavel,
  GitCompareArrows,
  Landmark,
  LoaderCircle,
  Route,
  Scale,
  ShieldCheck,
  TriangleAlert,
  WalletCards,
  XCircle,
} from 'lucide-react';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { cc3AddressUrl, shortAddress } from '@/lib/deployment';
import {
  proofEngineById,
  proofEngines,
  publicAaveCase,
  type ProofEngineId,
  type ProofInputKey,
} from '@/lib/proof-engines';
import {
  classifyProofIntent,
  type GateStatus,
  type PreflightResult,
  type ProofInputValues,
} from '@/lib/proof-router';

const accents = {
  orange: {
    border: 'border-[#ff9f67]/24',
    active: 'border-[#ff9f67]/60 bg-[#ff9f67]/10',
    icon: 'bg-[#ff9f67]/12 text-[#ffb389]',
    text: 'text-[#ffb389]',
    glow: 'shadow-[0_12px_50px_rgba(255,159,103,.08)]',
  },
  blue: {
    border: 'border-[#78bfff]/22',
    active: 'border-[#78bfff]/55 bg-[#78bfff]/10',
    icon: 'bg-[#78bfff]/10 text-[#9dd0f5]',
    text: 'text-[#9dd0f5]',
    glow: 'shadow-[0_12px_50px_rgba(120,191,255,.07)]',
  },
  lime: {
    border: 'border-[#b8f34a]/18',
    active: 'border-[#b8f34a]/50 bg-[#b8f34a]/9',
    icon: 'bg-[#b8f34a]/10 text-[#c9fa72]',
    text: 'text-[#c9fa72]',
    glow: '',
  },
  violet: {
    border: 'border-[#c3a4ff]/18',
    active: 'border-[#c3a4ff]/50 bg-[#c3a4ff]/9',
    icon: 'bg-[#c3a4ff]/10 text-[#d4bfff]',
    text: 'text-[#d4bfff]',
    glow: '',
  },
  teal: {
    border: 'border-[#69ddc0]/18',
    active: 'border-[#69ddc0]/50 bg-[#69ddc0]/9',
    icon: 'bg-[#69ddc0]/10 text-[#8ce9d2]',
    text: 'text-[#8ce9d2]',
    glow: '',
  },
} as const;

const engineIcons = {
  sandwich: GitCompareArrows,
  'fair-exit': Scale,
  'aave-performance': Landmark,
  'rfq-execution': FileSearch,
  settlement: WalletCards,
} as const;

const statusCopy: Record<
  PreflightResult['status'],
  { label: string; tone: string }
> = {
  ready_to_verify: {
    label: 'Ready for specialist verification',
    tone: 'bg-[#b8f34a]/12 text-[#c9fa72]',
  },
  ready_to_collect: {
    label: 'Ready to collect evidence',
    tone: 'bg-[#b8f34a]/12 text-[#c9fa72]',
  },
  needs_input: {
    label: 'More evidence needed',
    tone: 'bg-white/8 text-white/62',
  },
  not_enforceable: {
    label: 'Not enforceable through Prover',
    tone: 'bg-[#ff9f67]/12 text-[#ffb389]',
  },
  predicate_mismatch: {
    label: 'Preflight requirements not satisfied',
    tone: 'bg-[#ff9f67]/12 text-[#ffb389]',
  },
  default_available: {
    label: 'Default finalization available',
    tone: 'bg-[#c3a4ff]/12 text-[#d4bfff]',
  },
  already_resolved: {
    label: 'Already resolved',
    tone: 'bg-[#78bfff]/12 text-[#9dd0f5]',
  },
  upstream_unavailable: {
    label: 'Live read unavailable',
    tone: 'bg-white/8 text-white/62',
  },
};

export function ProofRouter() {
  const [description, setDescription] = useState('');
  const [selectedId, setSelectedId] = useState<ProofEngineId>('sandwich');
  const [routeMessage, setRouteMessage] = useState(
    'Choose a specialist or describe the outcome you want to prove.',
  );
  const [routeConfidence, setRouteConfidence] = useState<
    'high' | 'medium' | 'none'
  >('none');
  const [inputs, setInputs] = useState<ProofInputValues>({});
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState('');
  const [invalidInput, setInvalidInput] = useState<ProofInputKey | null>(null);
  const [result, setResult] = useState<PreflightResult | null>(null);
  const requestController = useRef<AbortController | null>(null);

  const engine = proofEngineById(selectedId);
  const accent = accents[engine.accent];

  useEffect(
    () => () => {
      requestController.current?.abort();
    },
    [],
  );

  function cancelPreflight() {
    requestController.current?.abort();
    requestController.current = null;
    setBusy(false);
  }

  function chooseEngine(engineId: ProofEngineId, reason?: string) {
    cancelPreflight();
    setSelectedId(engineId);
    setInputs({});
    setResult(null);
    setFormError('');
    setInvalidInput(null);
    setRouteConfidence('none');
    setRouteMessage(
      reason ??
        `${proofEngineById(engineId).specialist} selected. Supply the exact evidence coordinates for a read-only eligibility check.`,
    );
  }

  function routeDescription() {
    const classification = classifyProofIntent(description.slice(0, 1_000));
    setRouteConfidence(classification.confidence);
    setRouteMessage(classification.reason);
    if (classification.engineId) {
      cancelPreflight();
      setSelectedId(classification.engineId);
      setInputs({});
      setResult(null);
      setFormError('');
      setInvalidInput(null);
    }
  }

  function loadPublicAaveCase() {
    cancelPreflight();
    setInputs({ ...publicAaveCase });
    setResult(null);
    setFormError('');
    setInvalidInput(null);
    setRouteMessage(
      'Loaded the public Ethereum Borrow/Repay pair used by the repository’s live verification script.',
    );
  }

  async function runPreflight() {
    const missing = engine.inputs.find((input) => !inputs[input.key]?.trim());
    if (missing) {
      setFormError(`${missing.label} is required.`);
      setInvalidInput(missing.key);
      requestAnimationFrame(() => {
        document.getElementById(`router-${selectedId}-${missing.key}`)?.focus();
      });
      return;
    }
    requestController.current?.abort();
    const controller = new AbortController();
    requestController.current = controller;
    const timeout = window.setTimeout(() => controller.abort(), 20_000);
    setBusy(true);
    setFormError('');
    setInvalidInput(null);
    setResult(null);
    try {
      const response = await fetch('/api/proof-router/preflight', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ engineId: selectedId, inputs }),
        signal: controller.signal,
      });
      const payload: unknown = await response.json();
      if (!response.ok) {
        const detail =
          typeof payload === 'object' &&
          payload !== null &&
          'error' in payload &&
          typeof payload.error === 'string'
            ? payload.error
            : 'The preflight request was rejected.';
        throw new Error(detail);
      }
      if (
        typeof payload !== 'object' ||
        payload === null ||
        !('engineId' in payload) ||
        payload.engineId !== selectedId ||
        !('status' in payload) ||
        !('gates' in payload) ||
        !Array.isArray(payload.gates)
      ) {
        throw new Error('The preflight response was malformed.');
      }
      setResult(payload as PreflightResult);
    } catch (error) {
      if (requestController.current !== controller) return;
      setFormError(
        error instanceof Error && error.name === 'AbortError'
          ? 'The live check timed out. No conclusion was made; try again.'
          : error instanceof Error
            ? error.message
            : 'The preflight request could not be completed.',
      );
    } finally {
      window.clearTimeout(timeout);
      if (requestController.current === controller) {
        requestController.current = null;
        setBusy(false);
      }
    }
  }

  return (
    <section
      id="proof-router"
      className="scroll-mt-16 border-b border-white/8 bg-[#0b1914] px-4 py-16 sm:px-7 sm:py-20 lg:px-10"
    >
      <div className="mx-auto max-w-[1500px]">
        <div className="grid gap-7 lg:grid-cols-[0.7fr_1.3fr] lg:items-end">
          <div className="max-w-xl">
            <Badge className="border border-[#b8f34a]/18 bg-[#b8f34a]/8 text-[#c9fa72]">
              <Route className="size-3" /> Proof Router · triage only
            </Badge>
            <h2 className="mt-4 text-balance text-3xl font-semibold tracking-[-0.045em] sm:text-4xl">
              What do you want to prove?
            </h2>
            <p className="mt-3 text-sm leading-6 text-white/48">
              Describe the outcome. Prover routes you to one deterministic
              specialist and checks route eligibility, coverage and evidence
              availability. The router never decides the case.
            </p>
          </div>

          <div className="rounded-2xl border border-white/9 bg-white/[0.035] p-4 sm:p-5">
            <Label
              htmlFor="proof-intent"
              className="text-xs font-semibold text-white/72"
            >
              Describe your goal or grievance
            </Label>
            <Textarea
              id="proof-intent"
              value={description}
              maxLength={1_000}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="A relay placed transactions immediately before and after my swap in the same block…"
              className="mt-3 min-h-24 resize-none border-white/10 bg-[#091511]/80 text-white placeholder:text-white/24 focus-visible:border-[#b8f34a]/45 focus-visible:ring-[#b8f34a]/15"
            />
            <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center">
              <Button
                type="button"
                onClick={routeDescription}
                className="h-11 bg-[#b8f34a] px-4 text-[#0a1712] hover:bg-[#d0ff78]"
              >
                Find the proof specialist <ArrowRight />
              </Button>
              <p
                className="min-w-0 text-[11px] leading-5 text-white/38"
                aria-live="polite"
              >
                {routeMessage}
                {routeConfidence !== 'none' && (
                  <span className="ml-2 font-semibold uppercase tracking-[0.08em] text-[#b8f34a]/70">
                    {routeConfidence} route confidence
                  </span>
                )}
              </p>
            </div>
          </div>
        </div>

        <div className="mt-7 grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          {proofEngines.map((candidate) => {
            const Icon = engineIcons[candidate.id];
            const candidateAccent = accents[candidate.accent];
            const selected = candidate.id === selectedId;
            return (
              <button
                key={candidate.id}
                type="button"
                aria-pressed={selected}
                onClick={() => chooseEngine(candidate.id)}
                className={`min-h-36 rounded-2xl border p-4 text-left outline-none transition focus-visible:ring-2 focus-visible:ring-[#b8f34a]/70 ${selected ? candidateAccent.active : `bg-white/[0.025] hover:bg-white/[0.055] ${candidateAccent.border}`} ${candidate.flagship ? candidateAccent.glow : ''}`}
              >
                <span className="flex items-start justify-between gap-3">
                  <span
                    className={`grid size-9 place-items-center rounded-xl ${candidateAccent.icon}`}
                  >
                    <Icon className="size-[18px]" />
                  </span>
                  {candidate.flagship && (
                    <Badge
                      className={`bg-white/[0.055] text-[9px] ${candidateAccent.text}`}
                    >
                      Flagship
                    </Badge>
                  )}
                </span>
                <span className="mt-4 block text-sm font-semibold text-white/82">
                  {candidate.label}
                </span>
                <span className="mt-1.5 block text-[10px] leading-4 text-white/34">
                  {candidate.specialist}
                </span>
              </button>
            );
          })}
        </div>

        <div
          className={`mt-5 overflow-hidden rounded-3xl border bg-[#091511] ${accent.border}`}
        >
          <div className="grid lg:grid-cols-[0.78fr_1.22fr]">
            <div className="border-b border-white/8 p-5 sm:p-7 lg:border-b-0 lg:border-r">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p
                    className={`text-[10px] font-bold uppercase tracking-[0.15em] ${accent.text}`}
                  >
                    Selected specialist
                  </p>
                  <h3 className="mt-2 text-2xl font-semibold tracking-[-0.035em]">
                    {engine.specialist}
                  </h3>
                </div>
                <Badge className={`${accent.icon} font-mono text-[9px]`}>
                  {engine.version}
                </Badge>
              </div>

              <p className="mt-4 text-sm leading-6 text-white/48">
                {engine.goal}
              </p>

              <div className="mt-5 space-y-3 border-t border-white/8 pt-5">
                <RouterFact label="Source" value={engine.source} />
                <RouterFact
                  label="Runs on"
                  value={`${engine.deployment.network} · ${shortAddress(engine.deployment.contractAddress)}`}
                  href={cc3AddressUrl(engine.deployment.contractAddress)}
                />
              </div>

              <div className="mt-5 rounded-xl border border-white/8 bg-white/[0.028] p-4">
                <p className="text-[10px] font-bold uppercase tracking-[0.13em] text-white/30">
                  Required at final verification
                </p>
                <ul className="mt-3 space-y-2.5">
                  {engine.evidence.map((item) => (
                    <li
                      key={item}
                      className="flex gap-2.5 text-[11px] leading-5 text-white/48"
                    >
                      <Check
                        className={`mt-1 size-3 shrink-0 ${accent.text}`}
                      />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            <div className="p-5 sm:p-7">
              <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-[0.15em] text-white/28">
                    Read-only preflight
                  </p>
                  <h4 className="mt-2 text-lg font-semibold">
                    Check eligibility and evidence readiness
                  </h4>
                  <p className="mt-1 max-w-2xl text-xs leading-5 text-white/38">
                    No wallet signature, transaction or accusation is created.
                  </p>
                </div>
                {selectedId === 'aave-performance' && (
                  <Button
                    type="button"
                    variant="outline"
                    onClick={loadPublicAaveCase}
                    className="h-10 shrink-0 border-[#b8f34a]/20 bg-[#b8f34a]/7 text-[#c9fa72] hover:bg-[#b8f34a]/12 hover:text-[#d0ff78]"
                  >
                    Load public Aave case
                  </Button>
                )}
              </div>

              <div className="mt-5 grid gap-4 md:grid-cols-2">
                {engine.inputs.map((definition) => (
                  <div
                    key={definition.key}
                    className={
                      engine.inputs.length % 2 === 1 &&
                      definition === engine.inputs[0]
                        ? 'md:col-span-2'
                        : ''
                    }
                  >
                    <Label
                      htmlFor={`router-${selectedId}-${definition.key}`}
                      className="text-[11px] text-white/62"
                    >
                      {definition.label}
                    </Label>
                    <Input
                      id={`router-${selectedId}-${definition.key}`}
                      value={inputs[definition.key] ?? ''}
                      onChange={(event) => {
                        cancelPreflight();
                        setInputs((current) => ({
                          ...current,
                          [definition.key]: event.target.value,
                        }));
                        setFormError('');
                        if (invalidInput === definition.key) {
                          setInvalidInput(null);
                        }
                        setResult(null);
                      }}
                      inputMode={
                        definition.kind === 'integer' ? 'numeric' : 'text'
                      }
                      autoComplete="off"
                      spellCheck={false}
                      aria-invalid={invalidInput === definition.key}
                      aria-describedby={`router-help-${selectedId}-${definition.key}`}
                      placeholder={definition.placeholder}
                      className="mt-2 h-11 border-white/10 bg-white/[0.035] font-mono text-xs text-white placeholder:font-sans placeholder:text-white/20 focus-visible:border-[#b8f34a]/45 focus-visible:ring-[#b8f34a]/15"
                    />
                    <p
                      id={`router-help-${selectedId}-${definition.key}`}
                      className="mt-1.5 text-[10px] leading-4 text-white/28"
                    >
                      {definition.help}
                      {invalidInput === definition.key && (
                        <span className="ml-1 text-[#ffb389]">Required.</span>
                      )}
                    </p>
                  </div>
                ))}
              </div>

              <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center">
                <Button
                  type="button"
                  onClick={runPreflight}
                  disabled={busy}
                  className="h-11 bg-[#b8f34a] px-4 text-[#0a1712] hover:bg-[#d0ff78]"
                >
                  {busy ? (
                    <LoaderCircle className="animate-spin" />
                  ) : (
                    <ShieldCheck />
                  )}
                  {busy ? 'Checking live contracts…' : 'Run eligibility check'}
                </Button>
                <p
                  className={`text-xs leading-5 ${formError ? 'text-[#ffb389]' : 'text-white/32'}`}
                  role={formError ? 'alert' : undefined}
                >
                  {formError ||
                    'The engine ID is confirmed here; grievance text is never sent to the API.'}
                </p>
              </div>

              <div className="mt-6" aria-live="polite">
                {result ? (
                  <PreflightReport result={result} />
                ) : (
                  <div className="rounded-2xl border border-dashed border-white/10 bg-white/[0.018] p-5">
                    <div className="flex items-start gap-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-white/[0.045] text-white/40">
                        <Gavel className="size-4" />
                      </span>
                      <div>
                        <p className="text-sm font-semibold text-white/68">
                          Routing is not a ruling
                        </p>
                        <p className="mt-1 text-[11px] leading-5 text-white/36">
                          Classification creates no accusation, breach, payout
                          or reputation record. Only the selected CC3 specialist
                          can verify authenticated source-chain evidence and
                          issue a deterministic outcome.
                        </p>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>

          <div className="grid border-t border-white/8 bg-white/[0.024] sm:grid-cols-2">
            <div className="p-4 sm:p-5">
              <p className="text-[9px] font-bold uppercase tracking-[0.13em] text-white/28">
                If proven
              </p>
              <p className="mt-1.5 text-xs leading-5 text-white/52">
                {engine.consequence}
              </p>
            </div>
            <div className="border-t border-white/8 p-4 sm:border-l sm:border-t-0 sm:p-5">
              <p className="text-[9px] font-bold uppercase tracking-[0.13em] text-white/28">
                Evidence boundary
              </p>
              <p className="mt-1.5 text-xs leading-5 text-white/42">
                {engine.boundary}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function RouterFact({
  label,
  value,
  href,
}: {
  label: string;
  value: string;
  href?: string;
}) {
  return (
    <div>
      <p className="text-[9px] font-bold uppercase tracking-[0.12em] text-white/25">
        {label}
      </p>
      {href ? (
        <a
          href={href}
          target="_blank"
          rel="noreferrer"
          className="mt-1 inline-flex items-center gap-1.5 text-xs text-white/55 transition hover:text-[#c9fa72]"
        >
          {value} <ExternalLink className="size-3" />
        </a>
      ) : (
        <p className="mt-1 text-xs leading-5 text-white/55">{value}</p>
      )}
    </div>
  );
}

function GateIcon({ status }: { status: GateStatus }) {
  if (status === 'pass') {
    return <CheckCircle2 className="size-4 text-[#b8f34a]" />;
  }
  if (status === 'fail') {
    return <XCircle className="size-4 text-[#ff9f67]" />;
  }
  if (status === 'warning') {
    return <TriangleAlert className="size-4 text-[#d4bfff]" />;
  }
  return <CircleAlert className="size-4 text-white/38" />;
}

function PreflightReport({ result }: { result: PreflightResult }) {
  const status = statusCopy[result.status];
  return (
    <div className="rounded-2xl border border-white/10 bg-white/[0.028] p-4 sm:p-5">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
        <div>
          <Badge className={status.tone}>{status.label}</Badge>
          <h5 className="mt-3 text-base font-semibold text-white/82">
            {result.headline}
          </h5>
          <p className="mt-1 max-w-2xl text-[11px] leading-5 text-white/40">
            {result.summary}
          </p>
        </div>
        {result.source && (
          <div className="shrink-0 rounded-xl border border-white/8 bg-[#091511]/70 px-3 py-2 text-right font-mono text-[9px] text-white/34">
            <p>source key {result.source.chainKey}</p>
            <p className="mt-1">
              attested {result.source.latestAttestedHeight.toLocaleString()}
            </p>
          </div>
        )}
      </div>

      <div className="mt-4 grid gap-2 sm:grid-cols-2">
        {result.gates.map((gate) => (
          <div
            key={gate.id}
            className="rounded-xl border border-white/8 bg-[#091511]/55 p-3"
          >
            <div className="flex items-center gap-2">
              <GateIcon status={gate.status} />
              <span className="sr-only">Status: {gate.status}.</span>
              <p className="text-[11px] font-semibold text-white/66">
                {gate.label}
              </p>
            </div>
            <p className="mt-1.5 text-[10px] leading-4 text-white/32">
              {gate.detail}
            </p>
          </div>
        ))}
      </div>

      {result.packets && result.packets.length > 0 && (
        <div className="mt-4 border-t border-white/8 pt-4">
          <p className="text-[9px] font-bold uppercase tracking-[0.13em] text-white/28">
            Bounded packet summary · no raw proof bytes returned
          </p>
          <div className="mt-2 grid gap-2 sm:grid-cols-2">
            {result.packets.map((packet) => (
              <div
                key={`${packet.role}-${packet.txHash}`}
                className="min-w-0 rounded-lg bg-white/[0.035] px-3 py-2.5"
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-[10px] font-semibold text-white/58">
                    {packet.role}
                  </span>
                  <span className="font-mono text-[9px] text-[#b8f34a]/65">
                    #{packet.blockHeight}:{packet.txIndex}
                  </span>
                </div>
                <p className="mt-1 truncate font-mono text-[8px] text-white/24">
                  {packet.txHash}
                </p>
                <p className="mt-1 text-[9px] text-white/28">
                  {packet.merkleSiblingCount} Merkle siblings ·{' '}
                  {packet.continuityRootCount} continuity roots
                </p>
              </div>
            ))}
          </div>
        </div>
      )}

      <p className="mt-4 border-t border-white/8 pt-3 text-[10px] leading-4 text-white/28">
        Checked {new Date(result.checkedAt).toLocaleString()} ·{' '}
        {result.boundary}
      </p>
    </div>
  );
}
