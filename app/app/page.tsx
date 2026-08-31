import {
  ArrowDown,
  ArrowRight,
  ExternalLink,
  Gavel,
  GitCompareArrows,
  ShieldCheck,
} from 'lucide-react';

import { PerformanceDemo } from '@/components/performance-demo';
import { Badge } from '@/components/ui/badge';
import { buttonVariants } from '@/components/ui/button';
import { cc3AddressUrl, cc3Deployment, shortAddress } from '@/lib/deployment';
import { promiseCatalog, type PromiseCoverage } from '@/lib/promise-catalog';

export default function Home() {
  return (
    <main className="min-h-screen bg-[#091511] text-white">
      <header className="sticky top-0 z-50 border-b border-white/8 bg-[#091511]/88 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between px-4 sm:px-7 lg:px-10">
          <a
            href="#top"
            className="flex items-center gap-3"
            aria-label="Prover home"
          >
            <span className="grid size-9 place-items-center rounded-xl bg-[#b8f34a] text-[#0a1712]">
              <ShieldCheck className="size-5" strokeWidth={2.5} />
            </span>
            <div>
              <p className="text-[15px] font-bold tracking-[-0.02em]">PROVER</p>
              <p className="text-[9px] font-semibold uppercase tracking-[0.18em] text-white/38">
                Cross-chain bureau
              </p>
            </div>
          </a>

          <div className="hidden items-center gap-7 text-xs text-white/50 md:flex">
            <a className="transition hover:text-white" href="#order-proofs">
              Order proofs
            </a>
            <a className="transition hover:text-white" href="#promises">
              Promise coverage
            </a>
            <a className="transition hover:text-white" href="#deployment">
              CC3 deployment
            </a>
            <a className="transition hover:text-white" href="#court">
              Evidence demo
            </a>
          </div>

          <a
            href={cc3AddressUrl(cc3Deployment.contracts[0].address)}
            target="_blank"
            rel="noreferrer"
          >
            <Badge className="border border-[#b8f34a]/20 bg-[#b8f34a]/10 text-[#c9fa72]">
              CC3 court deployed <ExternalLink className="size-3" />
            </Badge>
          </a>
        </div>
      </header>

      <section
        id="top"
        className="relative overflow-hidden border-b border-white/8 px-4 pb-20 pt-16 sm:px-7 sm:pb-28 sm:pt-24 lg:px-10"
      >
        <div
          aria-hidden="true"
          className="absolute inset-0 opacity-35 [background-image:linear-gradient(to_right,rgba(255,255,255,.035)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,.035)_1px,transparent_1px)] [background-size:44px_44px]"
        />
        <div
          aria-hidden="true"
          className="absolute -right-48 -top-48 size-[580px] rounded-full bg-[#b8f34a]/10 blur-[110px]"
        />
        <div
          aria-hidden="true"
          className="absolute -bottom-64 -left-32 size-[520px] rounded-full bg-[#2a6b51]/20 blur-[100px]"
        />

        <div className="relative mx-auto max-w-[1500px]">
          <div className="grid items-end gap-12 xl:grid-cols-[0.88fr_1.12fr]">
            <div className="max-w-3xl">
              <Badge className="mb-5 h-auto max-w-full whitespace-normal rounded-xl border border-white/10 bg-white/[0.045] px-3 py-1.5 text-left leading-4 text-[#c9fa72]">
                <GitCompareArrows className="size-3" /> A cross-chain bureau of
                fulfilled and breached financial promises.
              </Badge>
              <h1 className="text-balance text-5xl font-semibold leading-[0.98] tracking-[-0.06em] sm:text-6xl lg:text-[76px]">
                Prove the order.
                <span className="block text-[#b8f34a]">
                  Enforce the promise.
                </span>
              </h1>
              <p className="mt-6 max-w-2xl text-base leading-7 text-white/55 sm:text-lg sm:leading-8">
                A Merkle-order proof exposes a relay sandwich. FairExit exposes
                a vault queue inversion. The transaction payload never says “I
                was first”—the Merkle path does.
              </p>

              <div className="mt-8 flex flex-wrap gap-3">
                <a
                  href="#order-proofs"
                  className={buttonVariants({
                    className:
                      'h-11 rounded-xl bg-[#b8f34a] px-4 text-[#0a1712] hover:bg-[#d0ff78]',
                  })}
                >
                  Inspect both verdicts
                  <ArrowDown className="size-4" />
                </a>
                <a
                  href="#court"
                  className={buttonVariants({
                    variant: 'outline',
                    className:
                      'h-11 rounded-xl border-white/12 bg-white/[0.035] px-4 text-white hover:bg-white/10 hover:text-white',
                  })}
                >
                  Open the evidence court
                  <ArrowRight className="size-4" />
                </a>
              </div>

              <div className="mt-10 flex flex-wrap items-center gap-x-6 gap-y-3 font-mono text-[10px] uppercase tracking-[0.1em] text-white/30">
                <span>verifyAndEmit</span>
                <span className="text-[#b8f34a]/55">→</span>
                <span>calculateTxIndex</span>
                <span className="text-[#b8f34a]/55">→</span>
                <span>deterministic verdict</span>
                <span className="text-[#b8f34a]/55">→</span>
                <span>bond slashed</span>
              </div>
            </div>

            <div id="order-proofs" className="scroll-mt-24 space-y-3">
              <SandwichFlagship />
              <FairExitFlagship />
            </div>
          </div>
        </div>
      </section>

      <LiveDeployment />

      <PromiseCoverageSection />

      <section
        id="consequence"
        className="border-b border-white/8 bg-[#0d1d17] px-4 py-5 sm:px-7 lg:px-10"
      >
        <div className="mx-auto flex max-w-[1500px] flex-col justify-between gap-3 md:flex-row md:items-center">
          <div className="flex items-center gap-3">
            <span className="grid size-8 place-items-center rounded-lg bg-[#b8f34a]/10 text-[#b8f34a]">
              <Gavel className="size-4" />
            </span>
            <p className="text-sm font-medium">
              The ruling is the product. Credit is one consequence.
            </p>
          </div>
          <p className="max-w-2xl text-xs leading-5 text-white/40">
            A proven breach follows the operator into future borrowing limits,
            premiums and bond requirements; verified Aave performance uses the
            same transparent record without becoming another opaque score.
          </p>
        </div>
      </section>

      <PerformanceDemo />
    </main>
  );
}

function PromiseCoverageSection() {
  return (
    <section
      id="promises"
      className="scroll-mt-16 border-b border-white/8 bg-[#091511] px-4 py-16 sm:px-7 sm:py-20 lg:px-10"
    >
      <div className="mx-auto max-w-[1500px]">
        <div className="grid gap-5 lg:grid-cols-[0.72fr_1.28fr] lg:items-end">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-[#b8f34a]">
              Promise coverage
            </p>
            <h2 className="mt-3 max-w-lg text-3xl font-semibold tracking-[-0.045em] sm:text-4xl">
              Four promises. One evidence standard.
            </h2>
          </div>
          <p className="max-w-3xl text-sm leading-6 text-white/48 lg:justify-self-end">
            Ordering is the flagship: sandwich and FairExit turn Merkle position
            into a ruling. The same court pattern now classifies exact RFQ and
            settlement events through mutually authorized, prospective promises—
            without pretending those local modules are already deployed or
            bureau-trusted.
          </p>
        </div>

        <div className="mt-8 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          {promiseCatalog.map((item) => (
            <PromiseCard key={item.id} item={item} />
          ))}
        </div>

        <div className="mt-4 grid gap-3 lg:grid-cols-2">
          <p className="rounded-xl border border-[#b8f34a]/14 bg-[#b8f34a]/[0.045] px-4 py-3 text-xs leading-5 text-white/48">
            <span className="font-semibold text-[#c9fa72]">
              Positive evidence boundary.{' '}
            </span>
            A wrong or late transaction is proved from authenticated
            source-chain evidence. A deadline default means no acceptable
            fulfillment proof reached the registered promise before its evidence
            window closed—it is not proof that no source-chain transaction
            existed.
          </p>
          <p className="rounded-xl border border-white/8 bg-white/[0.025] px-4 py-3 text-xs leading-5 text-white/42">
            <span className="font-semibold text-white/68">
              Trust boundary.{' '}
            </span>
            RFQ and settlement drafts now require beneficiary EIP-712 or
            EIP-1271 authorization, an approved source-policy revision and a
            future CC3 block hash before activation. They stay outside the
            shared bureau because the fixture emitter does not transfer assets
            and no production adapter or live proof is deployed.
          </p>
        </div>

        <div className="mt-4 rounded-2xl border border-white/8 bg-white/[0.025] p-4 sm:p-5">
          <div className="grid gap-4 md:grid-cols-4">
            {[
              [
                '01',
                'Mutual authorization',
                'The beneficiary signs every source, timing and economic field.',
              ],
              [
                '02',
                'Policy approval',
                'Governance pins an exact chain, emitter, kind and schema revision.',
              ],
              [
                '03',
                'Prospective activation',
                'A future CC3 block hash makes the final promise ID unknowable at registration.',
              ],
              [
                '04',
                'Typed resolution',
                'One authenticated event fulfills or breaches the immutable promise.',
              ],
            ].map(([number, title, body]) => (
              <div
                key={number}
                className="border-white/8 md:border-l md:pl-4 first:border-l-0 first:pl-0"
              >
                <p className="font-mono text-[9px] text-[#b8f34a]/70">
                  {number}
                </p>
                <p className="mt-1 text-xs font-semibold text-white/72">
                  {title}
                </p>
                <p className="mt-1.5 text-[11px] leading-5 text-white/38">
                  {body}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function PromiseCard({ item }: { item: PromiseCoverage }) {
  const accents = {
    orange: {
      dot: 'bg-[#ff9f67]',
      eyebrow: 'text-[#ffb389]',
      border: 'border-[#ff9f67]/18',
      badge: 'bg-[#ff9f67]/10 text-[#ffb389]',
    },
    blue: {
      dot: 'bg-[#78bfff]',
      eyebrow: 'text-[#9dd0f5]',
      border: 'border-[#78bfff]/18',
      badge: 'bg-[#78bfff]/10 text-[#9dd0f5]',
    },
    lime: {
      dot: 'bg-[#b8f34a]',
      eyebrow: 'text-[#c9fa72]',
      border: 'border-[#b8f34a]/18',
      badge: 'bg-[#b8f34a]/10 text-[#c9fa72]',
    },
    violet: {
      dot: 'bg-[#c3a4ff]',
      eyebrow: 'text-[#d4bfff]',
      border: 'border-[#c3a4ff]/18',
      badge: 'bg-[#c3a4ff]/10 text-[#d4bfff]',
    },
  } as const;
  const accent = accents[item.accent];

  return (
    <article
      className={`flex h-full flex-col rounded-2xl border bg-white/[0.028] p-5 ${accent.border}`}
    >
      <div className="flex items-center justify-between gap-3">
        <div
          className={`flex items-center gap-2 text-[9px] font-bold uppercase tracking-[0.14em] ${accent.eyebrow}`}
        >
          <span className={`size-1.5 rounded-full ${accent.dot}`} />
          {item.eyebrow}
        </div>
        <Badge className={accent.badge}>
          {item.maturity === 'flagship' ? 'Flagship' : 'Court module'}
        </Badge>
      </div>

      <h3 className="mt-4 text-lg font-semibold tracking-[-0.025em]">
        {item.title}
      </h3>
      <p className="mt-3 text-xs leading-5 text-white/46">{item.promise}</p>

      <div className="mt-5 space-y-3 border-t border-white/8 pt-4 text-[11px] leading-5">
        <div>
          <p className="font-semibold uppercase tracking-[0.1em] text-white/28">
            Evidence
          </p>
          <p className="mt-1 text-white/55">{item.proof}</p>
        </div>
        <div>
          <p className="font-semibold uppercase tracking-[0.1em] text-white/28">
            Consequence
          </p>
          <p className="mt-1 text-white/55">{item.consequence}</p>
        </div>
      </div>

      <div className="mt-auto space-y-1.5 border-t border-white/8 pt-4 font-mono text-[9px] uppercase tracking-[0.08em]">
        <p className="text-white/52">{item.contractStatus}</p>
        <p className="text-white/28">{item.evidenceStatus}</p>
      </div>
    </article>
  );
}

function LiveDeployment() {
  return (
    <section
      id="deployment"
      className="scroll-mt-16 border-b border-white/8 bg-[#0b1914] px-4 py-7 sm:px-7 lg:px-10"
    >
      <div className="mx-auto grid max-w-[1500px] gap-5 lg:grid-cols-[0.8fr_1.2fr] lg:items-center">
        <div>
          <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-[0.15em] text-[#b8f34a]">
            <span className="size-2 rounded-full bg-[#b8f34a] shadow-[0_0_12px_#b8f34a]" />
            Contracts live · chain {cc3Deployment.chainId}
          </div>
          <h2 className="mt-2 text-xl font-semibold tracking-[-0.025em]">
            The court infrastructure is deployed on CC3 testnet.
          </h2>
          <p className="mt-2 max-w-xl text-xs leading-5 text-white/42">
            Native verifier and ChainInfo wiring, factory children, decoder
            link, ownership and least-privilege reporter masks were checked
            on-chain. The browser verdicts remain labeled fixtures until live
            proof payloads are submitted.
          </p>
        </div>

        <div className="grid gap-2 sm:grid-cols-2">
          {cc3Deployment.contracts.map((contract) => (
            <a
              key={contract.address}
              href={cc3AddressUrl(contract.address)}
              target="_blank"
              rel="noreferrer"
              className="group flex items-center justify-between rounded-xl border border-white/8 bg-white/[0.035] px-3.5 py-3 transition hover:border-[#b8f34a]/25 hover:bg-white/[0.065]"
            >
              <span>
                <span className="block text-[11px] font-semibold text-white/72">
                  {contract.label}
                </span>
                <span className="mt-1 block font-mono text-[9px] text-white/30">
                  {shortAddress(contract.address)}
                </span>
              </span>
              <ExternalLink className="size-3.5 text-white/25 transition group-hover:text-[#b8f34a]" />
            </a>
          ))}
        </div>
      </div>
    </section>
  );
}

function SandwichFlagship() {
  return (
    <article className="rounded-2xl border border-[#ff9f67]/22 bg-[#15251e]/92 p-5 shadow-[0_28px_80px_rgba(0,0,0,.25)] sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="mb-2 flex items-center gap-2">
            <span className="size-2 rounded-full bg-[#ff9f67] shadow-[0_0_12px_#ff9f67]" />
            <span className="text-[10px] font-bold uppercase tracking-[0.14em] text-[#ffb389]">
              Sandwich verdict
            </span>
          </div>
          <h2 className="text-xl font-semibold tracking-[-0.025em]">
            No-sandwich covenant broken
          </h2>
        </div>
        <Badge className="bg-[#ff9f67]/12 text-[#ffb389]">
          3 proofs · 1 block
        </Badge>
      </div>

      <div className="mt-5 grid grid-cols-[1fr_auto_1fr_auto_1fr] items-center gap-2">
        <Position index="14" label="front-run" accent="orange" />
        <ArrowRight className="size-4 text-white/25" />
        <Position index="15" label="victim" accent="lime" />
        <ArrowRight className="size-4 text-white/25" />
        <Position index="16" label="back-run" accent="orange" />
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-white/8 pt-4">
        <p className="font-mono text-[10px] text-white/38">
          RLLLRRRR → 14 · authenticated receipt logs → same pool
        </p>
        <span className="text-xs font-semibold text-[#ffb389]">
          front &lt; victim &lt; back ✓
        </span>
      </div>
    </article>
  );
}

function FairExitFlagship() {
  return (
    <article className="rounded-2xl border border-[#78bfff]/20 bg-[#10241f]/92 p-5 shadow-[0_28px_80px_rgba(0,0,0,.2)] sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="mb-2 flex items-center gap-2">
            <span className="size-2 rounded-full bg-[#78bfff] shadow-[0_0_12px_#78bfff]" />
            <span className="text-[10px] font-bold uppercase tracking-[0.14em] text-[#9dd0f5]">
              FairExit verdict
            </span>
          </div>
          <h2 className="text-xl font-semibold tracking-[-0.025em]">
            FIFO exit covenant broken
          </h2>
        </div>
        <Badge className="bg-[#78bfff]/10 text-[#a8d8f9]">
          4 positive proofs
        </Badge>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <OrderLane
          label="Requests"
          left="A · request #7"
          right="B · request #8"
        />
        <OrderLane
          label="Processed"
          left="B · request #8"
          right="A · request #7"
          inverted
        />
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-white/8 pt-4">
        <p className="font-mono text-[10px] text-white/38">
          request A &lt; B · process B &lt; A
        </p>
        <span className="text-xs font-semibold text-[#9dd0f5]">
          completed inversion ✓
        </span>
      </div>
    </article>
  );
}

function Position({
  index,
  label,
  accent,
}: {
  index: string;
  label: string;
  accent: 'orange' | 'lime';
}) {
  const isLime = accent === 'lime';
  return (
    <div
      className={`rounded-xl border p-3 text-center ${isLime ? 'border-[#b8f34a]/28 bg-[#b8f34a]/9' : 'border-[#ff9f67]/18 bg-[#ff9f67]/[0.055]'}`}
    >
      <span
        className={`block text-2xl font-semibold tracking-[-0.04em] ${isLime ? 'text-[#c9fa72]' : 'text-[#ffb389]'}`}
      >
        {index}
      </span>
      <span className="mt-1 block text-[9px] font-medium uppercase tracking-[0.1em] text-white/38">
        {label}
      </span>
    </div>
  );
}

function OrderLane({
  label,
  left,
  right,
  inverted = false,
}: {
  label: string;
  left: string;
  right: string;
  inverted?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-3.5 ${inverted ? 'border-[#78bfff]/28 bg-[#78bfff]/8' : 'border-white/8 bg-white/[0.025]'}`}
    >
      <p className="text-[9px] font-semibold uppercase tracking-[0.12em] text-white/32">
        {label}
      </p>
      <div className="mt-2 flex items-center gap-2">
        <span className="min-w-0 flex-1 rounded-lg bg-white/[0.055] px-2 py-2 text-center font-mono text-[10px] text-white/65">
          {left}
        </span>
        <ArrowRight
          className={`size-3.5 shrink-0 ${inverted ? 'text-[#78bfff]' : 'text-white/25'}`}
        />
        <span className="min-w-0 flex-1 rounded-lg bg-white/[0.055] px-2 py-2 text-center font-mono text-[10px] text-white/65">
          {right}
        </span>
      </div>
    </div>
  );
}
