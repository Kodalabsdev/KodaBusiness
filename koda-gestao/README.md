# Koda Gestão

SaaS multi-tenant de gestão para pequenos/médios comércios e prestadores de
serviço (barbearias, salões, clínicas, estúdios, oficinas, lojas). Um usuário
pode possuir múltiplos comércios; cada comércio tem seus módulos, dados e
isolamento próprios (RLS por `business_id`).

## Passo a passo para rodar localmente

1. **Instalar dependências**
   ```bash
   npm install
   ```

2. **Criar projeto no Supabase** (supabase.com) e pegar:
   - Project URL
   - anon public key
   - service_role key (uso restrito, nunca no client)

3. **Configurar variáveis de ambiente**
   ```bash
   cp .env.example .env.local
   # preencher NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY
   ```

4. **Aplicar a migration inicial**
   - Via Supabase CLI (recomendado):
     ```bash
     supabase link --project-ref <seu-project-ref>
     supabase db push
     ```
   - Ou cole o conteúdo de `supabase/migrations/0001_initial_schema.sql`
     diretamente no SQL Editor do painel Supabase.

5. **Gerar os types do banco**
   ```bash
   npm run db:types
   ```

6. **Rodar o projeto**
   ```bash
   npm run dev
   ```

## Estrutura

- `supabase/migrations/` — schema SQL versionado (fonte de verdade do banco).
- `lib/supabase/` — clientes Supabase (browser e server).
- `lib/modules.ts` — registro central dos módulos ativáveis por comércio.
- `middleware.ts` — protege rotas autenticadas e mantém a sessão.
- `app/(auth)/` — login e cadastro.
- `app/(app)/[businessId]/` — todas as telas de um comércio específico
  (dashboard, agenda, clientes, funcionários, serviços, financeiro, estoque,
  configurações), isoladas pelo segmento de rota.

## Modelo de dados (resumo)

`businesses` → `business_members` (papel: owner/admin/manager/employee) →
`employees`, `clients`, `services`, `appointments`, `completed_services`,
`enabled_modules`, `business_settings`. Toda tabela de domínio carrega
`business_id` e tem RLS restringindo acesso a membros daquele comércio
(`is_business_member()`), então nunca dependa apenas de filtro no frontend.

Agendamentos têm uma exclusion constraint no banco (`no_overlap_per_employee`)
que impede dois horários sobrepostos para o mesmo funcionário — a garantia
final é no banco, não só na UI.

## Próximos passos (não implementados ainda)

- Telas de auth (login/cadastro) e seleção/criação de comércio.
- CRUDs de clientes, funcionários, serviços.
- UI de agenda (calendário) consumindo `appointments`.
- Dashboard com resumo do dia.
- Integração futura com Koda App Store para verificação de licença.
