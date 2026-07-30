-- Advisor fixes for Agent Builder knowledge base objects.

create or replace function public.knowledge_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create index if not exists agent_knowledge_bases_knowledge_base_id_idx
on public.agent_knowledge_bases (knowledge_base_id);

drop policy if exists "authenticated users can create knowledge bases" on public.knowledge_bases;
create policy "authenticated users can create knowledge bases"
on public.knowledge_bases
for insert
to authenticated
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = (select auth.uid())
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
    or created_by = (select auth.uid())
  )
);

drop policy if exists "owners can update knowledge bases" on public.knowledge_bases;
create policy "owners can update knowledge bases"
on public.knowledge_bases
for update
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = (select auth.uid())
)
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = (select auth.uid())
);

drop policy if exists "owners can delete knowledge bases" on public.knowledge_bases;
create policy "owners can delete knowledge bases"
on public.knowledge_bases
for delete
to authenticated
using (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = (select auth.uid())
);

drop policy if exists "authenticated users can create sources for visible bases" on public.knowledge_base_sources;
create policy "authenticated users can create sources for visible bases"
on public.knowledge_base_sources
for insert
to authenticated
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and created_by = (select auth.uid())
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = knowledge_base_sources.knowledge_base_id
      and kb.account_id = knowledge_base_sources.account_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
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
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
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
    created_by = (select auth.uid())
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = (select auth.uid())
    )
  )
)
with check (
  account_id = '00000000-0000-0000-0000-000000000001'
  and (
    created_by = (select auth.uid())
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = (select auth.uid())
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
    created_by = (select auth.uid())
    or exists (
      select 1
      from public.knowledge_bases kb
      where kb.id = knowledge_base_sources.knowledge_base_id
        and kb.created_by = (select auth.uid())
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
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
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
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
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
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
  )
);

drop policy if exists "authenticated users can read agent knowledge mappings" on public.agent_knowledge_bases;
drop policy if exists "authenticated users can manage own agent knowledge mappings" on public.agent_knowledge_bases;

create policy "authenticated users can read agent knowledge mappings"
on public.agent_knowledge_bases
for select
to authenticated
using (
  created_by = (select auth.uid())
  or exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = agent_knowledge_bases.knowledge_base_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
  )
);

create policy "authenticated users can create own agent knowledge mappings"
on public.agent_knowledge_bases
for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = agent_knowledge_bases.knowledge_base_id
      and kb.status <> 'deleted'
      and (kb.visibility = 'public' or kb.created_by = (select auth.uid()))
  )
);

create policy "authenticated users can delete own agent knowledge mappings"
on public.agent_knowledge_bases
for delete
to authenticated
using (created_by = (select auth.uid()));

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
set search_path = public
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
