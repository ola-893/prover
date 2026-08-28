import {
  ArrowRight,
  Check,
  Landmark,
  ShieldCheck,
  Sparkles,
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

const evidence = [
  {
    action: 'Borrow',
    amount: '7,500 USDC',
    detail: 'Aave V3 · Ethereum #22,450,182',
  },
  {
    action: 'Repay',
    amount: '7,500 USDC',
    detail: 'Aave V3 · Ethereum #22,781,904',
  },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-background text-foreground">
      <header className="border-b border-white/8 bg-[#091511]/90 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-[1480px] items-center justify-between px-5 sm:px-8">
          <div className="flex items-center gap-3">
            <span className="grid size-9 place-items-center rounded-xl bg-[#b8f34a] text-[#0a1712]">
              <ShieldCheck className="size-5" strokeWidth={2.4} />
            </span>
            <div>
              <p className="text-[15px] font-semibold tracking-[-0.02em] text-white">
                Proof Bureau
              </p>
              <p className="text-[10px] font-medium uppercase tracking-[0.16em] text-white/45">
                Attestcoin evidence network
              </p>
            </div>
          </div>
          <Badge className="border border-[#b8f34a]/20 bg-[#b8f34a]/10 text-[#c9fa72]">
            CC3 testnet
          </Badge>
        </div>
      </header>

      <section className="border-b border-white/8 bg-[#091511] px-5 pb-24 pt-12 text-white sm:px-8 sm:pt-16">
        <div className="mx-auto max-w-[1480px]">
          <div className="mb-8 flex flex-wrap items-end justify-between gap-6">
            <div className="max-w-3xl">
              <div className="mb-4 flex items-center gap-2 text-xs font-medium text-[#b8f34a]">
                <span className="size-1.5 rounded-full bg-[#b8f34a] shadow-[0_0_12px_#b8f34a]" />
                Ethereum evidence finalized on Creditcoin
              </div>
              <h1 className="text-balance text-4xl font-semibold tracking-[-0.045em] sm:text-5xl lg:text-[62px] lg:leading-[1.02]">
                Lending terms that can show their work.
              </h1>
              <p className="mt-5 max-w-2xl text-[15px] leading-7 text-white/55 sm:text-base">
                Verified Aave performance becomes an explainable lending profile.
                Covenant violations become permanent, attributable records.
              </p>
            </div>
            <Button className="h-11 rounded-xl bg-[#b8f34a] px-4 text-[#0a1712] hover:bg-[#d0ff78]">
              Run covenant demo
              <ArrowRight data-icon="inline-end" />
            </Button>
          </div>

          <div className="grid gap-4 lg:grid-cols-[1.45fr_0.8fr]">
            <Card className="border-0 bg-[#f4f1e8] text-[#13231c] ring-0">
              <CardHeader className="border-b border-[#13231c]/10 pb-5 sm:grid-cols-[1fr_auto]">
                <div>
                  <div className="mb-3 flex flex-wrap items-center gap-2">
                    <Badge className="bg-[#13231c] text-white">Verified profile</Badge>
                    <Badge variant="outline" className="border-[#13231c]/15 font-mono text-[#536159]">
                      0x71C7…3A91
                    </Badge>
                  </div>
                  <CardTitle className="text-2xl font-semibold tracking-[-0.035em] sm:text-3xl">
                    Transparent performance, not a mystery score.
                  </CardTitle>
                  <CardDescription className="mt-2 max-w-2xl text-[#58665f]">
                    Two authenticated Aave events support this profile. They do not claim
                    completeness or current solvency.
                  </CardDescription>
                </div>
                <div className="mt-4 grid size-24 place-items-center rounded-full border-[7px] border-[#b8f34a] bg-white/70 lg:mt-0">
                  <div className="text-center">
                    <strong className="block text-2xl leading-none">2/2</strong>
                    <span className="text-[9px] font-bold uppercase tracking-wider text-[#65736b]">
                      events
                    </span>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="grid gap-3 pt-5 md:grid-cols-2">
                {evidence.map((item) => (
                  <div key={item.action} className="rounded-xl border border-[#13231c]/10 bg-white/60 p-4">
                    <div className="mb-4 flex items-center justify-between">
                      <span className="grid size-7 place-items-center rounded-full bg-[#dfffa6] text-[#17351f]">
                        <Check className="size-4" strokeWidth={2.7} />
                      </span>
                      <span className="font-mono text-[10px] uppercase tracking-wider text-[#728078]">
                        Merkle verified
                      </span>
                    </div>
                    <p className="text-xs font-semibold uppercase tracking-[0.13em] text-[#69766f]">
                      {item.action}
                    </p>
                    <p className="mt-1 text-xl font-semibold tracking-[-0.03em]">{item.amount}</p>
                    <p className="mt-2 font-mono text-[10px] text-[#718078]">{item.detail}</p>
                  </div>
                ))}
              </CardContent>
            </Card>

            <Card className="border border-white/10 bg-[#12221b] text-white ring-0">
              <CardHeader>
                <div className="mb-3 flex size-10 items-center justify-center rounded-xl bg-[#b8f34a]/12 text-[#b8f34a]">
                  <Landmark className="size-5" />
                </div>
                <CardTitle className="text-xl tracking-[-0.025em]">Credit terms unlocked</CardTitle>
                <CardDescription className="text-white/45">
                  Policy v1.0 · calculated from disclosed evidence
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="rounded-xl border border-white/8 bg-white/[0.035] p-4">
                  <p className="text-xs text-white/45">Required collateral</p>
                  <div className="mt-1 flex items-end justify-between gap-4">
                    <strong className="text-3xl tracking-[-0.04em]">132%</strong>
                    <span className="mb-1 text-xs text-[#b8f34a]">150% baseline ↓</span>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="rounded-xl border border-white/8 bg-white/[0.035] p-4">
                    <p className="text-xs text-white/45">Rate adjustment</p>
                    <strong className="mt-2 block text-lg">−1.4%</strong>
                  </div>
                  <div className="rounded-xl border border-white/8 bg-white/[0.035] p-4">
                    <p className="text-xs text-white/45">Evidence confidence</p>
                    <strong className="mt-2 flex items-center gap-1.5 text-lg text-[#c9fa72]">
                      <Sparkles className="size-4" /> High
                    </strong>
                  </div>
                </div>
                <p className="px-1 pt-1 text-[11px] leading-5 text-white/35">
                  Terms are policy outputs, not Attestcoin facts. Every adjustment links back
                  to the evidence and rule that produced it.
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-[1480px] px-5 py-8 sm:px-8">
        <div className="flex items-center gap-3 text-sm text-muted-foreground">
          <span className="font-medium text-foreground">Next in the docket</span>
          <ArrowRight className="size-4" />
          No-sandwich relay covenant
          <ArrowRight className="size-4" />
          FairExit FIFO covenant
        </div>
      </section>
    </main>
  );
}
