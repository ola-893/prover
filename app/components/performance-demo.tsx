'use client';

import { useState } from 'react';
import {
  ArrowLeft,
  ArrowRight,
  Check,
  CircleDot,
  FileCheck2,
  Gavel,
  Landmark,
  Link2,
  LockKeyhole,
  RotateCcw,
  Scale,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  WalletCards,
} from 'lucide-react';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  actors,
  demoSteps,
  evidenceRecords,
  profileAt,
  termsFor,
  type ActorKey,
  type EvidenceRecord,
} from '@/lib/demo';

const actorKeys: ActorKey[] = ['borrower', 'relay', 'vault'];

export function PerformanceDemo() {
  const [step, setStep] = useState(5);
  const [selectedActor, setSelectedActor] = useState<ActorKey>('relay');
  const active = demoSteps[step - 1];
  const records = evidenceRecords.filter((record) => record.visibleAt <= step);

  function moveTo(nextStep: number) {
    const bounded = Math.min(Math.max(nextStep, 1), demoSteps.length);
    setStep(bounded);
    const nextActor = demoSteps[bounded - 1].actor;
    if (nextActor !== 'all') setSelectedActor(nextActor);
  }

  return (
    <div id="court" className="scroll-mt-16 bg-[#eeece4]">
      <section className="border-b border-[#183027]/10 bg-[#091511] px-4 pb-16 pt-10 text-white sm:px-7 lg:px-10">
        <div className="mx-auto max-w-[1500px]">
          <div className="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
            <div className="max-w-3xl">
              <div className="mb-4 flex flex-wrap items-center gap-2">
                <Badge className="border border-[#b8f34a]/25 bg-[#b8f34a]/10 text-[#c9fa72]">
                  Interactive MVP
                </Badge>
                <span className="text-xs text-white/40">
                  Evidence fixtures are visibly labeled until live proof capture
                </span>
              </div>
              <p className="text-xs font-semibold uppercase tracking-[0.17em] text-[#b8f34a]">
                Step {step} of 8 · {active.short}
              </p>
              <h1 className="mt-2 text-balance text-4xl font-semibold tracking-[-0.045em] sm:text-5xl">
                {active.title}
              </h1>
              <p className="mt-3 max-w-2xl text-[15px] leading-7 text-white/52">
                {active.description}
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                className="h-10 border-white/12 bg-white/[0.04] px-3 text-white hover:bg-white/10 hover:text-white"
                onClick={() => moveTo(1)}
              >
                <RotateCcw data-icon="inline-start" />
                Reset
              </Button>
              <Button
                className="h-10 bg-[#b8f34a] px-4 text-[#0a1712] hover:bg-[#d1ff7d]"
                onClick={() => moveTo(step + 1)}
                disabled={step === demoSteps.length}
              >
                {step === demoSteps.length ? 'Demo complete' : `Continue to ${demoSteps[step].short}`}
                {step < demoSteps.length && <ArrowRight data-icon="inline-end" />}
              </Button>
            </div>
          </div>

          <nav aria-label="Demo stages" className="mt-9 grid grid-cols-4 gap-2 lg:grid-cols-8">
            {demoSteps.map((item) => {
              const isActive = item.number === step;
              const isPast = item.number < step;
              return (
                <button
                  key={item.number}
                  type="button"
                  onClick={() => moveTo(item.number)}
                  aria-current={isActive ? 'step' : undefined}
                  className={`group rounded-xl border p-3 text-left transition-colors ${
                    isActive
                      ? 'border-[#b8f34a]/45 bg-[#b8f34a]/12'
                      : 'border-white/8 bg-white/[0.025] hover:bg-white/[0.06]'
                  }`}
                >
                  <span className="flex items-center justify-between">
                    <span className={`text-[10px] font-bold ${isActive ? 'text-[#c9fa72]' : 'text-white/30'}`}>
                      0{item.number}
                    </span>
                    {isPast && <Check className="size-3.5 text-[#b8f34a]" strokeWidth={2.8} />}
                    {isActive && <CircleDot className="size-3.5 text-[#b8f34a]" />}
                  </span>
                  <span className={`mt-2 block text-xs font-medium ${isActive ? 'text-white' : 'text-white/55'}`}>
                    {item.short}
                  </span>
                </button>
              );
            })}
          </nav>
        </div>
      </section>

      <section className="mx-auto -mt-9 max-w-[1500px] px-4 pb-14 sm:px-7 lg:px-10">
        <div className="grid gap-4 xl:grid-cols-[220px_minmax(0,1.35fr)_minmax(310px,0.75fr)]">
          <ActorRail
            selected={selectedActor}
            step={step}
            onSelect={setSelectedActor}
          />

          <div className="space-y-4">
            <ProfileCard actor={selectedActor} step={step} />
            <PredicateCard actor={selectedActor} step={step} />
          </div>

          <div className="space-y-4">
            <TermsCard actor={selectedActor} step={step} />
            <CovenantCard actor={selectedActor} step={step} />
          </div>
        </div>

        {step === 8 && <PortfolioComparison step={step} />}

        <EvidenceLedger records={records} />

        <div className="mt-5 flex flex-col items-start justify-between gap-3 rounded-xl border border-[#183027]/10 bg-[#e6e3da] px-4 py-3 text-xs text-[#58665f] sm:flex-row sm:items-center">
          <span>
            The bureau proves selected events and covenant violations—not complete history,
            current solvency, identity, intent or off-chain truth.
          </span>
          <div className="flex shrink-0 items-center gap-2">
            <Button variant="ghost" size="sm" disabled={step === 1} onClick={() => moveTo(step - 1)}>
              <ArrowLeft data-icon="inline-start" /> Previous
            </Button>
            <Button variant="outline" size="sm" disabled={step === 8} onClick={() => moveTo(step + 1)}>
              Next <ArrowRight data-icon="inline-end" />
            </Button>
          </div>
        </div>
      </section>
    </div>
  );
}

function ActorRail({
  selected,
  step,
  onSelect,
}: {
  selected: ActorKey;
  step: number;
  onSelect: (actor: ActorKey) => void;
}) {
  return (
    <Card className="h-fit border-0 bg-[#14271f] text-white ring-0">
      <CardHeader>
        <CardTitle className="text-sm text-white/90">Performance profiles</CardTitle>
        <CardDescription className="text-xs text-white/38">
          One evidence model, three actor types
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {actorKeys.map((key) => {
          const actor = actors[key];
          const record = profileAt(key, step);
          const breaches = record.sandwichBreaches + record.fifoBreaches;
          return (
            <button
              type="button"
              key={key}
              onClick={() => onSelect(key)}
              className={`w-full rounded-xl border p-3 text-left transition ${
                selected === key
                  ? 'border-white/18 bg-white/10'
                  : 'border-white/[0.06] bg-white/[0.025] hover:bg-white/[0.06]'
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <span
                  className="mt-0.5 size-2 rounded-full"
                  style={{ background: actor.accent, boxShadow: `0 0 10px ${actor.accent}80` }}
                />
                <Badge
                  variant="outline"
                  className={`h-4 border-white/10 px-1.5 text-[9px] ${
                    breaches > 0 ? 'text-[#ffad7c]' : record.matchedAaveCycles > 0 ? 'text-[#c9fa72]' : 'text-white/35'
                  }`}
                >
                  {breaches > 0 ? `${breaches} breach` : record.matchedAaveCycles > 0 ? 'positive' : 'baseline'}
                </Badge>
              </div>
              <span className="mt-2 block text-xs font-semibold text-white/90">{actor.name}</span>
              <span className="mt-0.5 block font-mono text-[9px] text-white/30">{actor.address}</span>
            </button>
          );
        })}
      </CardContent>
    </Card>
  );
}

function ProfileCard({ actor, step }: { actor: ActorKey; step: number }) {
  const profile = profileAt(actor, step);
  const identity = actors[actor];
  const breaches = profile.sandwichBreaches + profile.fifoBreaches;
  const facts = profile.aaveBorrowFacts + profile.aaveRepayFacts + profile.matchedAaveCycles + breaches;

  return (
    <Card className="border-0 bg-[#f9f7f1] ring-1 ring-[#183027]/10">
      <CardHeader className="border-b border-[#183027]/10 pb-5 sm:grid-cols-[1fr_auto]">
        <div>
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <Badge className="bg-[#183027] text-white">Verified performance vector</Badge>
            <Badge variant="outline" className="border-[#183027]/14 font-mono text-[#536159]">
              {identity.address}
            </Badge>
          </div>
          <CardTitle className="text-2xl font-semibold tracking-[-0.035em] text-[#14271f] sm:text-[28px]">
            {identity.name}
          </CardTitle>
          <CardDescription className="mt-1 text-[#647169]">{identity.role}</CardDescription>
        </div>
        <div
          className="mt-4 grid size-[86px] place-items-center rounded-full border-[6px] bg-white lg:mt-0"
          style={{ borderColor: breaches > 0 ? '#ff9f67' : facts > 0 ? '#b8f34a' : '#d5d7d0' }}
        >
          <div className="text-center text-[#183027]">
            <strong className="block text-2xl leading-none">{facts}</strong>
            <span className="text-[9px] font-bold uppercase tracking-wider text-[#718078]">facts</span>
          </div>
        </div>
      </CardHeader>
      <CardContent className="pt-5">
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          <Metric label="Aave cycles" value={profile.matchedAaveCycles} tone="positive" />
          <Metric label="Liquidations" value={profile.liquidations} />
          <Metric label="Sandwich" value={profile.sandwichBreaches} tone={profile.sandwichBreaches ? 'negative' : 'neutral'} />
          <Metric label="FIFO" value={profile.fifoBreaches} tone={profile.fifoBreaches ? 'negative' : 'neutral'} />
          <Metric label="Uncompensated" value={profile.uncompensatedBreaches} tone={profile.uncompensatedBreaches ? 'negative' : 'neutral'} />
          <Metric label="Slashed" value={`${profile.totalSlashedCtc} CTC`} tone={profile.totalSlashedCtc ? 'negative' : 'neutral'} />
        </div>
        <div className="mt-4 flex items-start gap-3 rounded-xl bg-[#ece9df] p-3 text-xs leading-5 text-[#58665f]">
          <FileCheck2 className="mt-0.5 size-4 shrink-0 text-[#2f5a46]" />
          <p>
            This is an append-only evidence vector. It deliberately avoids a mystery 0–1000
            score and exposes each term-changing fact.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}

function Metric({
  label,
  value,
  tone = 'neutral',
}: {
  label: string;
  value: number | string;
  tone?: 'positive' | 'negative' | 'neutral';
}) {
  const color = tone === 'positive' ? '#356b35' : tone === 'negative' ? '#a24d2a' : '#1c3128';
  return (
    <div className="rounded-xl border border-[#183027]/9 bg-white/65 p-3">
      <p className="text-[10px] font-medium uppercase tracking-[0.1em] text-[#78847d]">{label}</p>
      <strong className="mt-1.5 block text-xl tracking-[-0.03em]" style={{ color }}>
        {value}
      </strong>
    </div>
  );
}

function TermsCard({ actor, step }: { actor: ActorKey; step: number }) {
  const terms = termsFor(profileAt(actor, step));
  return (
    <Card className="border-0 bg-[#14271f] text-white ring-0">
      <CardHeader>
        <div className="mb-2 flex items-start justify-between">
          <div className="grid size-9 place-items-center rounded-xl bg-[#b8f34a]/12 text-[#b8f34a]">
            <Landmark className="size-[18px]" />
          </div>
          <Badge variant="outline" className="border-white/10 font-mono text-[9px] text-white/40">
            POLICY_V1
          </Badge>
        </div>
        <CardTitle className="text-lg">Future terms</CardTitle>
        <CardDescription className="text-xs text-white/38">
          Deterministic outputs · every adjustment explained
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        <Term label="Collateral required" value={`${terms.collateralBps / 100}%`} baseline="150% baseline" />
        <div className="grid grid-cols-2 gap-2">
          <Term label="Credit limit" value={`$${terms.maxBorrowUsdc.toLocaleString()}`} compact />
          <Term label="Premium" value={`${(terms.premiumBps / 100).toFixed(2)}%`} compact />
        </div>
        <Term label="Minimum future bond" value={`${terms.minimumBondCtc} CTC`} compact />

        <div className="space-y-2 pt-2">
          {terms.reasons.map((reason) => (
            <div key={reason.code} className="rounded-lg border border-white/[0.07] bg-white/[0.035] p-3">
              <div className="flex items-start gap-2">
                {reason.tone === 'positive' ? (
                  <Sparkles className="mt-0.5 size-3.5 shrink-0 text-[#b8f34a]" />
                ) : reason.tone === 'negative' ? (
                  <ShieldAlert className="mt-0.5 size-3.5 shrink-0 text-[#ff9f67]" />
                ) : (
                  <Scale className="mt-0.5 size-3.5 shrink-0 text-white/40" />
                )}
                <div className="min-w-0">
                  <p className="break-all font-mono text-[9px] text-white/38">{reason.code}</p>
                  <p className="mt-1 text-[11px] leading-4 text-white/70">{reason.label}</p>
                  <p className={`mt-1 text-[10px] ${reason.tone === 'negative' ? 'text-[#ffad7c]' : reason.tone === 'positive' ? 'text-[#c9fa72]' : 'text-white/38'}`}>
                    {reason.effect}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

function Term({ label, value, baseline, compact = false }: { label: string; value: string; baseline?: string; compact?: boolean }) {
  return (
    <div className="rounded-xl border border-white/[0.07] bg-white/[0.035] p-3.5">
      <p className="text-[10px] text-white/38">{label}</p>
      <div className={`mt-1 flex items-end justify-between gap-2 ${compact ? '' : 'min-h-8'}`}>
        <strong className={compact ? 'text-lg tracking-[-0.025em]' : 'text-3xl tracking-[-0.045em]'}>{value}</strong>
        {baseline && <span className="mb-0.5 text-[9px] text-[#b8f34a]">{baseline}</span>}
      </div>
    </div>
  );
}

function CovenantCard({ actor, step }: { actor: ActorKey; step: number }) {
  const isRelay = actor === 'relay';
  const isVault = actor === 'vault';
  const active = (isRelay && step >= 4) || (isVault && step >= 6);
  const breached = (isRelay && step >= 5) || (isVault && step >= 7);
  const startingBond = isRelay ? 500 : 400;

  return (
    <Card className="border-0 bg-[#f9f7f1] ring-1 ring-[#183027]/10">
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div className="grid size-9 place-items-center rounded-xl bg-[#e7e3d8] text-[#294b3b]">
            <LockKeyhole className="size-[18px]" />
          </div>
          <Badge
            className={
              breached
                ? 'bg-[#ffe0d0] text-[#8d3f22]'
                : active
                  ? 'bg-[#def8af] text-[#254a2a]'
                  : 'bg-[#e7e3d8] text-[#66736c]'
            }
          >
            {breached ? 'slashed' : active ? 'active covenant' : actor === 'borrower' ? 'not an operator' : 'not yet bound'}
          </Badge>
        </div>
        <CardTitle className="text-base text-[#183027]">
          {isRelay ? 'No-sandwich bond' : isVault ? 'FIFO exit bond' : 'Covenant exposure'}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {actor === 'borrower' ? (
          <p className="text-xs leading-5 text-[#65736b]">
            The borrower profile contains authenticated Aave performance. Operator covenants
            use the same bureau but remain separate, attributable promises.
          </p>
        ) : (
          <>
            <div className="flex items-end justify-between rounded-xl bg-[#ece9df] p-3">
              <div>
                <p className="text-[10px] uppercase tracking-wider text-[#748078]">Bond remaining</p>
                <strong className="mt-1 block text-xl text-[#183027]">
                  {active ? startingBond - (breached ? 50 : 0) : 0} CTC
                </strong>
              </div>
              {breached && <span className="text-xs font-semibold text-[#ad522d]">−50 CTC</span>}
            </div>
            <dl className="mt-3 grid grid-cols-2 gap-3 text-[10px]">
              <div>
                <dt className="text-[#839087]">Coverage</dt>
                <dd className="mt-1 font-mono text-[#42564b]">future heights only</dd>
              </div>
              <div>
                <dt className="text-[#839087]">Penalty</dt>
                <dd className="mt-1 font-mono text-[#42564b]">fixed 50 CTC</dd>
              </div>
            </dl>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function PredicateCard({ actor, step }: { actor: ActorKey; step: number }) {
  if (actor === 'relay') {
    const proven = step >= 5;
    return (
      <Card className="border-0 bg-[#fff8f2] ring-1 ring-[#b85e38]/15">
        <CardHeader className="sm:grid-cols-[1fr_auto]">
          <div>
            <CardTitle className="flex items-center gap-2 text-base text-[#47271a]">
              <Gavel className="size-[18px] text-[#b85e38]" /> Sandwich predicate
            </CardTitle>
            <CardDescription className="mt-1 text-xs text-[#7f675d]">
              Three successful transactions · same block · same pool · matching outer sender
            </CardDescription>
          </div>
          <Badge className={proven ? 'bg-[#ffdcc9] text-[#8b3b1e]' : 'bg-[#eee8e1] text-[#72675f]'}>
            {proven ? 'breach proven' : 'awaiting evidence'}
          </Badge>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-[1fr_auto_1fr_auto_1fr] items-center gap-2">
            <OrderNode index="41" label="front-run" active={proven} />
            <ArrowRight className="size-4 text-[#a98a7d]" />
            <OrderNode index="42" label="victim" active={proven} victim />
            <ArrowRight className="size-4 text-[#a98a7d]" />
            <OrderNode index="43" label="back-run" active={proven} />
          </div>
          <p className="mt-3 font-mono text-[10px] text-[#8d756a]">
            merkle laterality → 41 &lt; 42 &lt; 43 · staged capture fixture
          </p>
        </CardContent>
      </Card>
    );
  }

  if (actor === 'vault') {
    const proven = step >= 7;
    return (
      <Card className="border-0 bg-[#f1f8ff] ring-1 ring-[#3e79a4]/15">
        <CardHeader className="sm:grid-cols-[1fr_auto]">
          <div>
            <CardTitle className="flex items-center gap-2 text-base text-[#183d58]">
              <Gavel className="size-[18px] text-[#3376a4]" /> FIFO predicate
            </CardTitle>
            <CardDescription className="mt-1 text-xs text-[#5e7586]">
              Completed reverse processing proves inversion without a non-inclusion claim
            </CardDescription>
          </div>
          <Badge className={proven ? 'bg-[#cdeaff] text-[#225a80]' : 'bg-[#e4ebef] text-[#657985]'}>
            {proven ? 'breach proven' : 'awaiting evidence'}
          </Badge>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-2">
          <QueueLine title="Requests" first="A · #7" second="B · #8" reversed={false} active={proven} />
          <QueueLine title="Processed" first="B · #8" second="A · #7" reversed active={proven} />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-0 bg-[#eef5e6] ring-1 ring-[#4b7938]/15">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base text-[#294522]">
          <WalletCards className="size-[18px] text-[#4a7c35]" /> Aave attribution predicate
        </CardTitle>
        <CardDescription className="mt-1 text-xs text-[#62735c]">
          Borrow.onBehalfOf and Repay.user resolve to the same debt owner
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="flex flex-wrap items-center gap-2 font-mono text-[10px]">
          <Badge variant="outline" className="border-[#47723a]/20 text-[#3d6531]">Borrow</Badge>
          <Link2 className="size-3.5 text-[#7d9273]" />
          <span className="rounded-md bg-white/70 px-2 py-1.5 text-[#40543a]">onBehalfOf 0x71C7…3A91</span>
          <ArrowRight className="size-3.5 text-[#7d9273]" />
          <Badge variant="outline" className="border-[#47723a]/20 text-[#3d6531]">Repay.user matches</Badge>
        </div>
        <p className="mt-3 text-[11px] leading-5 text-[#687962]">
          The record says “borrow→later-repay cycle.” Aave debt is aggregate, so it does not
          claim a unique loan was fully closed or paid before a due date.
        </p>
      </CardContent>
    </Card>
  );
}

function OrderNode({ index, label, active, victim = false }: { index: string; label: string; active: boolean; victim?: boolean }) {
  return (
    <div className={`rounded-xl border p-3 text-center ${active ? victim ? 'border-[#df7e55] bg-[#ffe0cf]' : 'border-[#9c6d58]/20 bg-white/75' : 'border-[#9c6d58]/15 bg-white/45'}`}>
      <strong className="block text-lg text-[#4c2b1e]">{index}</strong>
      <span className="text-[9px] uppercase tracking-wider text-[#8c7065]">{label}</span>
    </div>
  );
}

function QueueLine({ title, first, second, reversed, active }: { title: string; first: string; second: string; reversed: boolean; active: boolean }) {
  return (
    <div className={`rounded-xl border p-3 ${active && reversed ? 'border-[#63a6d3] bg-[#dff2ff]' : 'border-[#527c99]/15 bg-white/60'}`}>
      <p className="text-[9px] font-semibold uppercase tracking-wider text-[#6f8797]">{title}</p>
      <div className="mt-2 flex items-center gap-2">
        <span className="rounded-md bg-white px-2 py-1 font-mono text-[10px] text-[#264c67]">{first}</span>
        <ArrowRight className="size-3.5 text-[#7995a8]" />
        <span className="rounded-md bg-white px-2 py-1 font-mono text-[10px] text-[#264c67]">{second}</span>
      </div>
    </div>
  );
}

function PortfolioComparison({ step }: { step: number }) {
  return (
    <Card className="mt-4 border-0 bg-[#f9f7f1] ring-1 ring-[#183027]/10">
      <CardHeader>
        <CardTitle className="text-lg text-[#183027]">One bureau, differentiated future terms</CardTitle>
        <CardDescription className="text-xs text-[#68756d]">
          Positive performance improves borrower capacity; objective covenant breaches raise operator costs.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[680px] text-left text-xs">
            <thead className="border-b border-[#183027]/10 text-[9px] uppercase tracking-[0.12em] text-[#7c8881]">
              <tr>
                <th className="pb-3 font-semibold">Profile</th>
                <th className="pb-3 font-semibold">Verified vector</th>
                <th className="pb-3 text-right font-semibold">Collateral</th>
                <th className="pb-3 text-right font-semibold">Limit</th>
                <th className="pb-3 text-right font-semibold">Premium</th>
                <th className="pb-3 text-right font-semibold">Min bond</th>
              </tr>
            </thead>
            <tbody>
              {actorKeys.map((key) => {
                const profile = profileAt(key, step);
                const terms = termsFor(profile);
                const vector = profile.matchedAaveCycles
                  ? '1 Aave cycle'
                  : profile.sandwichBreaches
                    ? '1 sandwich breach'
                    : '1 FIFO breach';
                return (
                  <tr key={key} className="border-b border-[#183027]/7 last:border-0">
                    <td className="py-4 font-semibold text-[#20372d]">{actors[key].name}</td>
                    <td className="py-4 text-[#627069]">{vector}</td>
                    <td className="py-4 text-right font-mono text-[#344b40]">{terms.collateralBps / 100}%</td>
                    <td className="py-4 text-right font-mono text-[#344b40]">${terms.maxBorrowUsdc.toLocaleString()}</td>
                    <td className="py-4 text-right font-mono text-[#344b40]">{(terms.premiumBps / 100).toFixed(2)}%</td>
                    <td className="py-4 text-right font-mono text-[#344b40]">{terms.minimumBondCtc} CTC</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
}

function EvidenceLedger({ records }: { records: EvidenceRecord[] }) {
  return (
    <Card className="mt-4 border-0 bg-[#f9f7f1] ring-1 ring-[#183027]/10">
      <CardHeader className="sm:grid-cols-[1fr_auto]">
        <div>
          <CardTitle className="flex items-center gap-2 text-lg text-[#183027]">
            <ShieldCheck className="size-[19px] text-[#3e684f]" /> Evidence ledger
          </CardTitle>
          <CardDescription className="mt-1 text-xs text-[#68756d]">
            Every profile mutation links to a typed fact and source coordinate.
          </CardDescription>
        </div>
        <Badge variant="outline" className="border-[#183027]/12 text-[#5c6a63]">
          {records.length} visible record{records.length === 1 ? '' : 's'}
        </Badge>
      </CardHeader>
      <CardContent className="space-y-2">
        {records.length === 0 ? (
          <div className="rounded-xl border border-dashed border-[#183027]/15 p-7 text-center text-xs text-[#748078]">
            Advance the demonstration to authenticate the first source facts.
          </div>
        ) : records.map((record) => (
          <div key={record.id} className="grid gap-3 rounded-xl border border-[#183027]/8 bg-white/60 p-3.5 md:grid-cols-[minmax(200px,1fr)_minmax(180px,0.8fr)_auto] md:items-center">
            <div className="flex min-w-0 items-start gap-3">
              <span className={`grid size-8 shrink-0 place-items-center rounded-lg ${record.kind.includes('BREACH') ? 'bg-[#ffe2d2] text-[#a44b28]' : 'bg-[#e3f7bc] text-[#3a6535]'}`}>
                {record.kind.includes('BREACH') ? <Gavel className="size-4" /> : <FileCheck2 className="size-4" />}
              </span>
              <div className="min-w-0">
                <p className="truncate text-xs font-semibold text-[#20372d]">{record.title}</p>
                <p className="mt-1 text-[10px] leading-4 text-[#748078]">{record.detail}</p>
              </div>
            </div>
            <div>
              <p className="text-[10px] font-medium text-[#536159]">{record.source}</p>
              <p className="mt-1 font-mono text-[9px] text-[#829087]">{record.coordinate}</p>
            </div>
            <div className="flex items-center justify-between gap-3 md:justify-end">
              <Badge className={record.mode === 'fixture' ? 'bg-[#eee7d7] text-[#75694e]' : 'bg-[#def8af] text-[#31552b]'}>
                {record.mode}
              </Badge>
              <span className="font-mono text-[9px] text-[#89948e]">{record.id}</span>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
