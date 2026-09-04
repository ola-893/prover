import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useWallet } from '@/contexts/WalletContext';
import Hero from '@/components/Hero';
import StatsSection from '@/components/StatsSection';
import HowItWorks from '@/components/HowItWorks';
import ProofEngines from '@/components/ProofEngines';
import Infrastructure from '@/components/Infrastructure';
import CtaSection from '@/components/CtaSection';
import Footer from '@/components/Footer';

export default function LandingPage() {
  const { address } = useWallet();
  const navigate = useNavigate();

  useEffect(() => {
    if (address) navigate('/dashboard');
  }, [address, navigate]);

  return (
    <div className="min-h-screen bg-[#FAF9F6]">
      <Hero />
      <StatsSection />
      <HowItWorks />
      <ProofEngines />
      <Infrastructure />
      <CtaSection />
      <Footer />
    </div>
  );
}
