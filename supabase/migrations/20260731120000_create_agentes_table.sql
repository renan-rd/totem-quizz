-- Agents created from the Agent Builder editor
-- Links to knowledge bases via public.agent_knowledge_bases

do $$
begin
  if not exists (select 1 from pg_type where typname = 'agent_channel') then
    create type public.agent_channel as enum ('widget', 'interno');
  end if;

  if not exists (select 1 from pg_type where typname = 'agent_status') then
    create type public.agent_status as enum ('ativo', 'rascunho');
  end if;
end $$;

create table if not exists public.agentes (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null default '00000000-0000-0000-0000-000000000001',
  created_by uuid default auth.uid(),
  nome text not null,
  descricao text,
  canal public.agent_channel not null default 'interno',
  conectores text[] not null default '{}'::text[],
  prompt text,
  status public.agent_status not null default 'rascunho',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint agentes_nome_not_blank check (length(btrim(nome)) > 0)
);

create index if not exists agentes_account_status_idx
on public.agentes (account_id, status);

create index if not exists agentes_created_at_idx
on public.agentes (created_at desc);

drop trigger if exists set_agentes_updated_at on public.agentes;
create trigger set_agentes_updated_at
before update on public.agentes
for each row execute function public.knowledge_set_updated_at();

alter table public.agent_knowledge_bases
  alter column created_by drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'agent_knowledge_bases_agent_id_fkey'
  ) then
    alter table public.agent_knowledge_bases
      add constraint agent_knowledge_bases_agent_id_fkey
      foreign key (agent_id) references public.agentes(id) on delete cascade;
  end if;
end $$;

alter table public.agentes enable row level security;

drop policy if exists "Allow public read on agentes" on public.agentes;
create policy "Allow public read on agentes"
on public.agentes
for select
to anon, authenticated
using (true);

drop policy if exists "Allow public insert on agentes" on public.agentes;
create policy "Allow public insert on agentes"
on public.agentes
for insert
to anon, authenticated
with check (account_id = '00000000-0000-0000-0000-000000000001');

drop policy if exists "Allow public update on agentes" on public.agentes;
create policy "Allow public update on agentes"
on public.agentes
for update
to anon, authenticated
using (account_id = '00000000-0000-0000-0000-000000000001')
with check (account_id = '00000000-0000-0000-0000-000000000001');

drop policy if exists "Allow public insert on agent knowledge mappings" on public.agent_knowledge_bases;
create policy "Allow public insert on agent knowledge mappings"
on public.agent_knowledge_bases
for insert
to anon, authenticated
with check (
  exists (
    select 1
    from public.agentes a
    where a.id = agent_knowledge_bases.agent_id
  )
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = agent_knowledge_bases.knowledge_base_id
      and kb.status <> 'deleted'
  )
);

drop policy if exists "Allow public read on agent knowledge mappings" on public.agent_knowledge_bases;
create policy "Allow public read on agent knowledge mappings"
on public.agent_knowledge_bases
for select
to anon, authenticated
using (true);

drop policy if exists "Allow public delete on agent knowledge mappings" on public.agent_knowledge_bases;
create policy "Allow public delete on agent knowledge mappings"
on public.agent_knowledge_bases
for delete
to anon, authenticated
using (true);
