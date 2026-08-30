import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.SITE_URL ??
      'https://prover-defi-court.yellow-haven-4898.chatgpt.site',
  ),
  title: 'PROVER — Prove the order. Enforce the promise.',
  description:
    'A cross-chain bureau of fulfilled and breached financial promises, led by authenticated sandwich and FairExit ordering verdicts.',
  alternates: { canonical: '/' },
  openGraph: {
    title: 'PROVER — Prove the order. Enforce the promise.',
    description:
      'Merkle paths prove sandwich ordering. FairExit proves queue inversion. Exact financial promises become typed evidence.',
    url: '/',
    type: 'website',
    images: [
      {
        url: '/og.png',
        width: 1200,
        height: 630,
        alt: 'PROVER cross-chain promise bureau',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'PROVER — Prove the order. Enforce the promise.',
    description:
      'Merkle paths prove sandwich ordering. FairExit proves queue inversion. Exact financial promises become typed evidence.',
    images: ['/og.png'],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
