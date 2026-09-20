import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Koda Gestão",
  description: "Gestão para pequenos e médios comércios",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
