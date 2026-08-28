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
  metadataBase: new URL(process.env.SITE_URL ?? 'http://localhost:3000'),
  title: 'PROVER — Prove the order. Enforce the promise.',
  description:
    'An Attestcoin-powered ordering court that proves relay sandwiches and FIFO queue inversions, enforces bonded promises, and carries rulings into future financial terms.',
  openGraph: {
    title: 'PROVER — Prove the order. Enforce the promise.',
    description:
      'Merkle paths prove sandwich ordering. FairExit proves queue inversion. Bonded promises become enforceable evidence.',
    type: 'website',
    images: [{ url: '/og.png', width: 1200, height: 630, alt: 'PROVER ordering court' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'PROVER — Prove the order. Enforce the promise.',
    description:
      'Merkle paths prove sandwich ordering. FairExit proves queue inversion. Bonded promises become enforceable evidence.',
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
