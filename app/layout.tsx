import type { Metadata } from 'next';
import './tailwind-built.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Datastraw CX Copilot | AI Operations & Policy Guardrail Engine',
  description: 'Enterprise multi-brand AI reply assistant and CX copilot with strict tenant isolation and deterministic policy guardrails.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="antialiased bg-[#000000] text-zinc-100" suppressHydrationWarning>
        {children}
      </body>
    </html>
  );
}
