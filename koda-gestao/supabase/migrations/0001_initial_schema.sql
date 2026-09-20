-- =========================================================
-- Koda Gestão — Schema inicial multi-tenant (multi-comércio)
-- =========================================================
-- Convenções:
--  - Toda tabela "de domínio" carrega business_id (FK -> businesses.id)
--  - RLS habilitado em todas as tabelas de domínio
--  - Acesso é resolvido via business_members (usuário <-> comércio <-> papel)
--  - UUIDs em todas as PKs, timestamps padronizados

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------
create type member_role as enum ('owner', 'admin', 'manager', 'employee');
create type appointment_status as enum ('agendado', 'confirmado', 'em_andamento', 'concluido', 'cancelado', 'faltou');
create type module_key as enum (
  'agenda', 'clientes', 'funcionarios', 'servicos',
  'financeiro', 'estoque', 'relatorios'
);

-- ---------------------------------------------------------
-- USERS (espelha auth.users do Supabase; perfil público)
-- ---------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- BUSINESSES (comércios)
-- ---------------------------------------------------------
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null,
  business_type text, -- ex: 'barbearia', 'salao', 'clinica', 'oficina'...
  phone text,
  email text,
  address text,
  currency text not null default 'BRL',
  opening_hours jsonb, -- estrutura flexível: {"mon": [["09:00","18:00"]], ...}
  logo_url text,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index businesses_owner_id_idx on public.businesses(owner_id);

-- ---------------------------------------------------------
-- BUSINESS_MEMBERS (usuário <-> comércio, com papel)
-- ---------------------------------------------------------
create table public.business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role member_role not null default 'owner',
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create index business_members_user_id_idx on public.business_members(user_id);
create index business_members_business_id_idx on public.business_members(business_id);

-- ---------------------------------------------------------
-- ENABLED_MODULES (módulos ativos por comércio)
-- ---------------------------------------------------------
create table public.enabled_modules (
  business_id uuid not null references public.businesses(id) on delete cascade,
  module module_key not null,
  enabled boolean not null default true,
  primary key (business_id, module)
);

-- ---------------------------------------------------------
-- EMPLOYEES
-- ---------------------------------------------------------
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null, -- opcional: login próprio
  name text not null,
  phone text,
  email text,
  role_title text, -- cargo/função
  specialties text[] default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index employees_business_id_idx on public.employees(business_id);

-- horários de trabalho por dia da semana (0=domingo ... 6=sábado)
create table public.employee_schedules (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time,
  end_time time,
  is_working boolean not null default true,
  created_at timestamptz not null default now(),
  unique (employee_id, weekday)
);

create index employee_schedules_business_id_idx on public.employee_schedules(business_id);

-- ---------------------------------------------------------
-- CLIENTS
-- ---------------------------------------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index clients_business_id_idx on public.clients(business_id);
create index clients_name_trgm_idx on public.clients using gin (name gin_trgm_ops);
create extension if not exists pg_trgm;

-- ---------------------------------------------------------
-- SERVICES
-- ---------------------------------------------------------
create table public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  price numeric(10,2) not null default 0,
  duration_minutes integer not null default 30,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index services_business_id_idx on public.services(business_id);

create table public.employee_services (
  employee_id uuid not null references public.employees(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  primary key (employee_id, service_id)
);

-- ---------------------------------------------------------
-- APPOINTMENTS
-- ---------------------------------------------------------
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  service_id uuid not null references public.services(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  price numeric(10,2) not null,
  status appointment_status not null default 'agendado',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index appointments_business_id_idx on public.appointments(business_id);
create index appointments_employee_time_idx on public.appointments(employee_id, starts_at, ends_at);

-- impede dois agendamentos sobrepostos para o mesmo funcionário
-- (exclusion constraint via btree_gist)
create extension if not exists btree_gist;

alter table public.appointments
  add constraint no_overlap_per_employee
  exclude using gist (
    employee_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status not in ('cancelado', 'faltou'));

-- ---------------------------------------------------------
-- COMPLETED_SERVICES (walk-ins / serviços sem agendamento prévio)
-- ---------------------------------------------------------
create table public.completed_services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  employee_id uuid references public.employees(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  service_name_snapshot text not null, -- preserva nome mesmo se o serviço mudar depois
  price numeric(10,2) not null,
  performed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index completed_services_business_id_idx on public.completed_services(business_id);
create index completed_services_client_id_idx on public.completed_services(client_id);

-- ---------------------------------------------------------
-- BUSINESS_SETTINGS (configurações livres/expansíveis)
-- ---------------------------------------------------------
create table public.business_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- FUNÇÃO HELPER: usuário é membro do comércio?
-- ---------------------------------------------------------
create or replace function public.is_business_member(target_business_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.business_members bm
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
  );
$$;

create or replace function public.member_role_for(target_business_id uuid)
returns member_role
language sql
security definer
stable
as $$
  select role from public.business_members
  where business_id = target_business_id and user_id = auth.uid()
  limit 1;
$$;

-- ---------------------------------------------------------
-- RLS
-- ---------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.enabled_modules enable row level security;
alter table public.employees enable row level security;
alter table public.employee_schedules enable row level security;
alter table public.clients enable row level security;
alter table public.services enable row level security;
alter table public.employee_services enable row level security;
alter table public.appointments enable row level security;
alter table public.completed_services enable row level security;
alter table public.business_settings enable row level security;

-- profiles: cada usuário só vê/edita o próprio perfil
create policy "profiles_select_own" on public.profiles for select using (id = auth.uid());
create policy "profiles_update_own" on public.profiles for update using (id = auth.uid());
create policy "profiles_insert_own" on public.profiles for insert with check (id = auth.uid());

-- businesses: só membros veem; só owner/admin atualizam; criação livre (dono = auth.uid())
create policy "businesses_select_members" on public.businesses
  for select using (public.is_business_member(id));

create policy "businesses_insert_self_owner" on public.businesses
  for insert with check (owner_id = auth.uid());

create policy "businesses_update_admins" on public.businesses
  for update using (public.member_role_for(id) in ('owner', 'admin'));

create policy "businesses_delete_owner" on public.businesses
  for delete using (public.member_role_for(id) = 'owner');

-- business_members: membros do comércio podem ver a lista; só owner/admin gerenciam
create policy "members_select_same_business" on public.business_members
  for select using (public.is_business_member(business_id));

create policy "members_insert_admins" on public.business_members
  for insert with check (public.member_role_for(business_id) in ('owner', 'admin') or user_id = auth.uid());

create policy "members_update_admins" on public.business_members
  for update using (public.member_role_for(business_id) in ('owner', 'admin'));

create policy "members_delete_admins" on public.business_members
  for delete using (public.member_role_for(business_id) in ('owner', 'admin'));

-- genérica para as tabelas de domínio: select/insert/update/delete por membros do comércio
-- (ajuste fino de permissão por papel pode vir depois; hoje qualquer membro do comércio acessa)
do $$
declare
  t text;
begin
  foreach t in array array[
    'enabled_modules', 'employees', 'employee_schedules', 'clients',
    'services', 'employee_services', 'appointments', 'completed_services',
    'business_settings'
  ]
  loop
    execute format($f$
      create policy "%1$s_select_members" on public.%1$s
        for select using (public.is_business_member(business_id));
      create policy "%1$s_insert_members" on public.%1$s
        for insert with check (public.is_business_member(business_id));
      create policy "%1$s_update_members" on public.%1$s
        for update using (public.is_business_member(business_id));
      create policy "%1$s_delete_members" on public.%1$s
        for delete using (public.is_business_member(business_id));
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------
-- TRIGGER: ao criar um business, cria membership owner + módulos padrão
-- ---------------------------------------------------------
create or replace function public.handle_new_business()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.business_members (business_id, user_id, role)
  values (new.id, new.owner_id, 'owner');

  insert into public.enabled_modules (business_id, module, enabled)
  select new.id, m, true
  from unnest(enum_range(null::module_key)) as m;

  insert into public.business_settings (business_id, data)
  values (new.id, '{}'::jsonb);

  return new;
end;
$$;

create trigger on_business_created
  after insert on public.businesses
  for each row execute function public.handle_new_business();

-- updated_at automático
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['profiles','businesses','employees','employee_schedules','clients','services','appointments']
  loop
    execute format(
      'create trigger set_updated_at before update on public.%1$s for each row execute function public.set_updated_at();',
      t
    );
  end loop;
end $$;
