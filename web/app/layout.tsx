import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Nyota — Digital Guest & Gift Manager",
  description: "Fast, simple guest and gift management for Indian events.",
  icons: { icon: "/logo.png", apple: "/logo.png" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
