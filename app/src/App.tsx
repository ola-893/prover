import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { WalletProvider } from '@/contexts/WalletContext';
import Navbar from '@/components/Navbar';
import WalletModal from '@/components/WalletModal';
import DashboardLayout from '@/layouts/DashboardLayout';
import LandingPage from '@/pages/LandingPage';
import ProvePage from '@/pages/ProvePage';
import CovenantPage from '@/pages/CovenantPage';
import DemoPage from '@/pages/DemoPage';
import ContractsPage from '@/pages/ContractsPage';
import DocsPage from '@/pages/DocsPage';

export default function App() {
  return (
    <WalletProvider>
      <BrowserRouter>
        <WalletModal />
        <Routes>
          {/* Public landing page */}
          <Route
            path="/"
            element={
              <div className="min-h-screen bg-[#FAF9F6] text-[#111111] selection:bg-[#111111] selection:text-white flex flex-col font-sans relative">
                <Navbar />
                <main className="flex-1">
                  <LandingPage />
                </main>
              </div>
            }
          />

          {/* Authenticated dashboard */}
          <Route path="/dashboard" element={<DashboardLayout />}>
            <Route index element={<ProvePage />} />
            <Route path="prove" element={<ProvePage />} />
            <Route path="covenant" element={<CovenantPage />} />
            <Route path="demo" element={<DemoPage />} />
            <Route path="contracts" element={<ContractsPage />} />
            <Route path="docs" element={<DocsPage />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </WalletProvider>
  );
}
