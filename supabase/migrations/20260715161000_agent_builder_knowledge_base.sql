-- Agent Builder: knowledge base MVP
-- This migration creates a new, isolated set of `knowledge_*` tables.
-- Existing Supabase tables are intentionally left untouched.

create extension if not exists vector;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'knowledge_visibility') then
    create type public.knowledge_visibility as enum ('public', 'private');
  end if;

  if not exists (select 1 from pg_type where typname = 'knowledge_base_status') then
    create type public.knowledge_base_status as enum ('active', 'archived', 'deleted');
  end if;

  if not exists (select 1 from pg_type where typname = 'knowledge_source_type') then
    create type public.knowledge_source_type as enum ('file', 'qa', 'site', 'page', 'youtube', 'audio');
  end if;

  if not exists (select 1 from pg_type where typname = 'knowledge_source_status') then
    create type public.knowledge_source_status as enum ('draft', 'queued', 'processing', 'ready', 'failed');
  end if;

  if not exists (select 1 from pg_type where typname = 'knowledge_job_status') then
    create type public.knowledge_job_status as enum ('queued', 'processing', 'done', 'failed');
  end if;
end $$;

create or replace function public.knowledge_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.knowledge_bases (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null default '00000000-0000-0000-0000-000000000001',
  created_by uuid not null default auth.uid(),
  name text not null,
  description text,
  visibility public.knowledge_visibility not null default 'private',
  status public.knowledge_base_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_bases_name_not_blank check (length(btrim(name)) > 0)
);

create table if not exists public.knowledge_base_sources (
  id uuid primary key default gen_random_uuid(),
  knowledge_base_id uuid not null references public.knowledge_bases(id) on delete cascade,
  account_id uuid not null default '00000000-0000-0000-0000-000000000001',
  type public.knowledge_source_type not null,
  title text not null,
  source_url text,
  storage_bucket text,
  storage_path text,
  mime_type text,
  size_bytes bigint,
  status public.knowledge_source_status not null default 'queued',
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_base_sources_title_not_blank check (length(btrim(title)) > 0),
  constraint knowledge_base_sources_size_non_negative check (size_bytes is null or size_bytes >= 0)
);

create table if not exists public.knowledge_base_chunks (
  id uuid primary key default gen_random_uuid(),
  knowledge_base_id uuid not null references public.knowledge_bases(id) on delete cascade,
  source_id uuid not null references public.knowledge_base_sources(id) on delete cascade,
  account_id uuid not null default '00000000-0000-0000-0000-000000000001',
  chunk_index integer not null,
  content text not null,
  content_hash text,
  token_count integer,
  embedding vector,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint knowledge_base_chunks_chunk_index_non_negative check (chunk_index >= 0),
  constraint knowledge_base_chunks_content_not_blank check (length(btrim(content)) > 0),
  constraint knowledge_base_chunks_token_count_non_negative check (token_count is null or token_count >= 0)
);

create table if not exists public.knowledge_ingestion_jobs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.knowledge_base_sources(id) on delete cascade,
  account_id uuid not null default '00000000-0000-0000-0000-000000000001',
  status public.knowledge_job_status not null default 'queued',
  attempts integer not null default 0,
  started_at timestamptz,
  finished_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint knowledge_ingestion_jobs_attempts_non_negative check (attempts >= 0)
);

create table if not exists public.agent_knowledge_bases (
  agent_id uuid not null,
  knowledge_base_id uuid not null references public.knowledge_bases(id) on delete cascade,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (agent_id, knowledge_base_id)
);

drop trigger if exists set_knowledge_bases_updated_at on public.knowledge_bases;
create trigger set_knowledge_bases_updated_at
before update on public.knowledge_bases
for each row execute function public.knowledge_set_updated_at();

drop trigger if exists set_knowledge_base_sources_updated_at on public.knowledge_base_sources;
create trigger set_knowledge_base_sources_updated_at
before update on public.knowledge_base_sources
for each row execute function public.knowledge_set_updated_at();

drop trigger if exists set_knowledge_ingestion_jobs_updated_at on public.knowledge_ingestion_jobs;
create trigger set_knowledge_ingestion_jobs_updated_at
before update on public.knowledge_ingestion_jobs
for each row execute function public.knowledge_set_updated_at();

create index if not exists knowledge_bases_account_status_idx
on public.knowledge_bases (account_id, status, visibility);

create index if not exists knowledge_bases_created_by_idx
on public.knowledge_bases (created_by);

create index if not exists knowledge_base_sources_base_status_idx
on public.knowledge_base_sources (knowledge_base_id, status);

create index if not exists knowledge_base_sources_account_type_idx
on public.knowledge_base_sources (account_id, type);

create index if not exists knowledge_base_chunks_base_idx
on public.knowledge_base_chunks (knowledge_base_id);

create index if not exists knowledge_base_chunks_source_idx
on public.knowledge_base_chunks (source_id);

create index if not exists knowledge_ingestion_jobs_source_status_idx
on public.knowledge_ingestion_jobs (source_id, status);

alter table public.knowledge_bases enable row level security;
alter table public.knowledge_base_sources enable row level security;
alter table public.knowledge_base_chunks enable row level security;
alter table public.knowledge_ingestion_jobs enable row level security;
alter table public.agent_knowledge_bases enable row level security;

drop policy if exists "authenticated users can create knowledge bases" on public.knowledge_bases;
create policy "authenticated users can create knowledge bases"
on public.knowledge_bases
for insert
to authenticated
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = auth.uid()
);

drop policy if exists "authenticated users can read visible knowledge bases" on public.knowledge_bases;
create policy "authenticated users can read visible knowledge bases"
on public.knowledge_bases
for select
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and status <> 'deleted'
  and (
    visibility = 'public'
    or created_by = auth.uid()
  )
);

drop policy if exists "owners can update knowledge bases" on public.knowledge_bases;
create policy "owners can update knowledge bases"
on public.knowledge_bases
for update
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = auth.uid()
)
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = auth.uid()
);

drop policy if exists "owners can delete knowledge bases" on public.knowledge_bases;
create policy "owners can delete knowledge bases"
on public.knowledge_bases
for delete
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = auth.uid()
);

drop policy if exists "authenticated users can create sources for visible bases" on public.knowledge_base_sources;
create policy "authenticated users can create sources for visible bases"
on public.knowledge_base_sources
for insert
to authenticated
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = auth.uid()
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = knowledge_base_sources.knowledge_base_id
      and kb.account_id = knowledge_base_sources.account_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "authenticated users can read sources from visible bases" on public.knowledge_base_sources;
create policy "authenticated users can read sources from visible bases"
on public.knowledge_base_sources
for select
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = knowledge_base_sources.knowledge_base_id
      and kb.account_id = knowledge_base_sources.account_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "source owners or base owners can update sources" on public.knowledge_base_sources;
create policy "source owners or base owners can update sources"
on public.knowledge_base_sources
for update
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and (
    created_by = auth.uid()
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = auth.uid()
    )
  )
)
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and (
    created_by = auth.uid()
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = auth.uid()
    )
  )
);

drop policy if exists "source owners or base owners can delete sources" on public.knowledge_base_sources;
create policy "source owners or base owners can delete sources"
on public.knowledge_base_sources
for delete
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and (
    created_by = auth.uid()
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = auth.uid()
    )
  )
);

drop policy if exists "authenticated users can read chunks from visible bases" on public.knowledge_base_chunks;
create policy "authenticated users can read chunks from visible bases"
on public.knowledge_base_chunks
for select
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = knowledge_base_chunks.knowledge_base_id
      and kb.account_id = knowledge_base_chunks.account_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "authenticated users can read jobs for visible bases" on public.knowledge_ingestion_jobs;
create policy "authenticated users can read jobs for visible bases"
on public.knowledge_ingestion_jobs
for select
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and exists (
    select 1
    from public.knowledge_base_sources s
    join public.knowledge_bases kb on kb.id = s.knowledge_base_id
    where s.id = knowledge_ingestion_jobs.source_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "authenticated users can create jobs for visible bases" on public.knowledge_ingestion_jobs;
create policy "authenticated users can create jobs for visible bases"
on public.knowledge_ingestion_jobs
for insert
to authenticated
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and exists (
    select 1
    from public.knowledge_base_sources s
    join public.knowledge_bases kb on kb.id = s.knowledge_base_id
    where s.id = knowledge_ingestion_jobs.source_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "authenticated users can read agent knowledge mappings" on public.agent_knowledge_bases;
create policy "authenticated users can read agent knowledge mappings"
on public.agent_knowledge_bases
for select
to authenticated
using (
  created_by = auth.uid()
  or exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = agent_knowledge_bases.knowledge_base_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = auth.uid())
  )
);

drop policy if exists "authenticated users can manage own agent knowledge mappings" on public.agent_knowledge_bases;
create policy "authenticated users can manage own agent knowledge mappings"
on public.agent_knowledge_bases
for all
to authenticated
using (created_by = auth.uid())
with check (created_by = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'knowledge-raw',
  'knowledge-raw',
  false,
  52428800,
  array[
    'application/pdf',
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "authenticated users can read single account knowledge files" on storage.objects;
create policy "authenticated users can read single account knowledge files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'knowledge-raw'
  and (storage.foldername(name))[1] = 'accounts'
  and (storage.foldername(name))[2] = '00000000-0000-0000-0000-000000000001'
);

drop policy if exists "authenticated users can upload single account knowledge files" on storage.objects;
create policy "authenticated users can upload single account knowledge files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'knowledge-raw'
  and (storage.foldername(name))[1] = 'accounts'
  and (storage.foldername(name))[2] = '00000000-0000-0000-0000-000000000001'
);

drop policy if exists "authenticated users can update single account knowledge files" on storage.objects;
create policy "authenticated users can update single account knowledge files"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'knowledge-raw'
  and (storage.foldername(name))[1] = 'accounts'
  and (storage.foldername(name))[2] = '00000000-0000-0000-0000-000000000001'
)
with check (
  bucket_id = 'knowledge-raw'
  and (storage.foldername(name))[1] = 'accounts'
  and (storage.foldername(name))[2] = '00000000-0000-0000-0000-000000000001'
);

drop policy if exists "authenticated users can delete single account knowledge files" on storage.objects;
create policy "authenticated users can delete single account knowledge files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'knowledge-raw'
  and (storage.foldername(name))[1] = 'accounts'
  and (storage.foldername(name))[2] = '00000000-0000-0000-0000-000000000001'
);

create or replace function public.match_knowledge_chunks(
  p_query_embedding vector,
  p_knowledge_base_ids uuid[] default null,
  p_match_count integer default 8,
  p_similarity_threshold double precision default 0.72
)
returns table (
  chunk_id uuid,
  knowledge_base_id uuid,
  source_id uuid,
  content text,
  similarity double precision,
  metadata jsonb,
  source_title text,
  source_type public.knowledge_source_type
)
language sql
stable
as $$
  select
    c.id as chunk_id,
    c.knowledge_base_id,
    c.source_id,
    c.content,
    1 - (c.embedding <=> p_query_embedding) as similarity,
    c.metadata,
    s.title as source_title,
    s.type as source_type
  from public.knowledge_base_chunks c
  join public.knowledge_base_sources s on s.id = c.source_id
  join public.knowledge_bases kb on kb.id = c.knowledge_base_id
  where c.account_id = '00000000-0000-0000-0000-000000000001'
    and c.embedding is not null
    and s.status = 'ready'
    and kb.status = 'active'
    and (p_knowledge_base_ids is null or c.knowledge_base_id = any(p_knowledge_base_ids))
    and 1 - (c.embedding <=> p_query_embedding) >= p_similarity_threshold
  order by c.embedding <=> p_query_embedding
  limit p_match_count;
$$;
