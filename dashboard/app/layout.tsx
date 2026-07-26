import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Memory Observatory",
  description: "Codex Memory & Improvement 本地状态中心",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
