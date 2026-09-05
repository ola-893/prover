import { BrowserRouter, Navigate, Routes, Route } from 'react-router-dom';
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
import StandingPage from '@/pages/StandingPage';
import LeaderboardPage from '@/pages/LeaderboardPage';

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

          {/* Public proof workspace. A wallet is only needed when a future action signs or mints. */}
          <Route path="/dashboard" element={<DashboardLayout />}>
            <Route index element={<ProvePage />} />
            <Route path="prove" element={<ProvePage />} />
            <Route path="check" element={<StandingPage />} />
            <Route path="leaderboard" element={<LeaderboardPage />} />
            <Route path="covenant" element={<CovenantPage />} />
            <Route path="demo" element={<DemoPage />} />
            <Route path="contracts" element={<ContractsPage />} />
            <Route path="docs" element={<DocsPage />} />
          </Route>
          <Route path="/prove" element={<Navigate to="/dashboard/prove" replace />} />
          <Route path="/check" element={<Navigate to="/dashboard/check" replace />} />
          <Route path="/leaderboard" element={<Navigate to="/dashboard/leaderboard" replace />} />
        </Routes>
      </BrowserRouter>
    </WalletProvider>
  );
}
