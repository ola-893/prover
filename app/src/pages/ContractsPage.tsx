import { cc3Deployment, sepoliaDeployment, cc3AddressUrl, sepoliaAddressUrl } from '@/lib/deployment';
import { ExternalLink, Shield, CheckCircle2 } from 'lucide-react';

export default function ContractsPage() {
  return (
    <div className="max-w-5xl mx-auto px-6 sm:px-10 lg:px-16 py-12 sm:py-16">
      {/* Header */}
      <div className="mb-12">
        <span className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.3em] mb-3 block">
          Infrastructure
        </span>
        <h1 className="font-serif text-3xl sm:text-4xl lg:text-5xl text-[#111111] tracking-tight leading-[1.1]">
          Contract <span className="italic text-[#888888]">Explorer</span>
        </h1>
        <p className="text-sm text-[#888888] mt-3 max-w-2xl">
          All contracts are live on Creditcoin CC3 testnet with public, verifiable bytecode.
          Every address links to the block explorer.
        </p>
      </div>

      {/* CC3 Testnet */}
      <div className="mb-16">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-8 h-8 bg-[#111111] text-white flex items-center justify-center font-mono text-[10px] font-bold">
            CC3
          </div>
          <div>
            <h2 className="font-serif text-xl text-[#111111]">{cc3Deployment.network}</h2>
            <span className="font-mono text-[10px] text-[#BBBBBB]">Chain ID: {cc3Deployment.chainId}</span>
          </div>
        </div>

        {/* Promise Contracts */}
        <div className="mb-8">
          <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-4">
            Promise System
          </h3>
          <div className="border border-[#E5E5E5] divide-y divide-[#E5E5E5] bg-white">
            {cc3Deployment.promiseContracts.map((c) => (
              <div key={c.address} className="p-4 flex items-center justify-between hover:bg-[#FAF9F6] transition-colors group">
                <div className="flex items-center gap-3">
                  <Shield className="w-4 h-4 text-[#AAAAAA] group-hover:text-[#111111] transition-colors" strokeWidth={1.5} />
                  <div>
                    <div className="font-mono text-xs font-bold text-[#111111]">{c.label}</div>
                    <div className="font-mono text-[10px] text-[#BBBBBB]">{c.address}</div>
                  </div>
                </div>
                <a
                  href={cc3AddressUrl(c.address)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-mono text-[10px] text-[#CCCCCC] hover:text-[#111111] flex items-center gap-1 transition-colors"
                >
                  Explorer
                  <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            ))}
          </div>
        </div>

        {/* Core Contracts */}
        <div>
          <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-4">
            Core Infrastructure
          </h3>
          <div className="border border-[#E5E5E5] divide-y divide-[#E5E5E5] bg-white">
            {cc3Deployment.contracts.map((c) => (
              <div key={c.address} className="p-4 flex items-center justify-between hover:bg-[#FAF9F6] transition-colors group">
                <div className="flex items-center gap-3">
                  <CheckCircle2 className="w-4 h-4 text-[#1B8A5A] shrink-0" strokeWidth={1.5} />
                  <div>
                    <div className="font-mono text-xs font-bold text-[#111111]">{c.label}</div>
                    <div className="font-mono text-[10px] text-[#BBBBBB]">{c.address}</div>
                  </div>
                </div>
                <a
                  href={cc3AddressUrl(c.address)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-mono text-[10px] text-[#CCCCCC] hover:text-[#111111] flex items-center gap-1 transition-colors"
                >
                  Explorer
                  <ExternalLink className="w-3 h-3" />
                </a>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Sepolia */}
      <div className="mb-16">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-8 h-8 border border-[#E5E5E5] bg-white flex items-center justify-center font-mono text-[10px] font-bold text-[#111111]">
            SEP
          </div>
          <div>
            <h2 className="font-serif text-xl text-[#111111]">{sepoliaDeployment.network}</h2>
            <span className="font-mono text-[10px] text-[#BBBBBB]">Chain ID: {sepoliaDeployment.chainId}</span>
          </div>
        </div>

        <div className="border border-[#E5E5E5] divide-y divide-[#E5E5E5] bg-white">
          {sepoliaDeployment.contracts.map((c) => (
            <div key={c.address} className="p-4 flex items-center justify-between hover:bg-[#FAF9F6] transition-colors group">
              <div className="flex items-center gap-3">
                <CheckCircle2 className="w-4 h-4 text-[#1B8A5A] shrink-0" strokeWidth={1.5} />
                <div>
                  <div className="font-mono text-xs font-bold text-[#111111]">{c.label}</div>
                  <div className="font-mono text-[10px] text-[#BBBBBB]">{c.address}</div>
                </div>
              </div>
              <a
                href={sepoliaAddressUrl(c.address)}
                target="_blank"
                rel="noopener noreferrer"
                className="font-mono text-[10px] text-[#CCCCCC] hover:text-[#111111] flex items-center gap-1 transition-colors"
              >
                Explorer
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          ))}
        </div>
      </div>

      {/* Policy Status */}
      <div className="border border-[#E5E5E5] bg-white p-6">
        <h3 className="font-mono text-[10px] text-[#BBBBBB] uppercase tracking-[0.2em] mb-5">
          Policy Status
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[
            { label: 'RFQ Policy', value: 'r1 Active' },
            { label: 'Settlement Policy', value: 'r1 Active' },
            { label: 'Native Proofs', value: '0 submitted' },
            { label: 'Evidence SBT', value: 'Live on CC3', green: true },
          ].map((item) => (
            <div key={item.label} className="p-3 border border-[#E5E5E5]">
              <div className="font-mono text-[9px] text-[#BBBBBB] uppercase tracking-widest">{item.label}</div>
              <div className={`font-mono text-xs font-bold mt-1 ${item.green ? 'text-[#1B8A5A]' : 'text-[#111111]'}`}>
                {item.value}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
