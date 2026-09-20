// Registro central dos módulos que um comércio pode ativar/desativar.
// Usado para montar a sidebar e para checagem de acesso a cada rota.

export type ModuleKey =
  | "agenda"
  | "clientes"
  | "funcionarios"
  | "servicos"
  | "financeiro"
  | "estoque"
  | "relatorios";

export interface ModuleDefinition {
  key: ModuleKey;
  label: string;
  path: string; // relativo a /[businessId]/...
  icon: string; // nome do ícone (lucide-react), resolvido no componente
}

export const MODULES: ModuleDefinition[] = [
  { key: "agenda", label: "Agenda", path: "agenda", icon: "Calendar" },
  { key: "clientes", label: "Clientes", path: "clientes", icon: "Users" },
  { key: "funcionarios", label: "Funcionários", path: "funcionarios", icon: "UserCog" },
  { key: "servicos", label: "Serviços", path: "servicos", icon: "Scissors" },
  { key: "financeiro", label: "Financeiro", path: "financeiro", icon: "Wallet" },
  { key: "estoque", label: "Estoque", path: "estoque", icon: "Package" },
  { key: "relatorios", label: "Relatórios", path: "relatorios", icon: "BarChart3" },
];

export function getEnabledModules(
  enabledMap: Record<string, boolean>
): ModuleDefinition[] {
  return MODULES.filter((m) => enabledMap[m.key] !== false);
}
