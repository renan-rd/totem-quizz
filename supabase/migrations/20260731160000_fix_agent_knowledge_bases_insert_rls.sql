-- Allow agent↔knowledge linking for the public prototype client.
-- The previous WITH CHECK used EXISTS on knowledge_bases, which fails for anon
-- because knowledge_bases only has SELECT policies for authenticated.

create or replace function public.agent_kb_link_allowed(p_knowledge_base_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.knowledge_bases kb
    where kb.id = p_knowledge_base_id
      and kb.status <> 'deleted'
  );
$$;

revoke all on function public.agent_kb_link_allowed(uuid) from public;
grant execute on function public.agent_kb_link_allowed(uuid) to anon, authenticated;

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
  and public.agent_kb_link_allowed(agent_knowledge_bases.knowledge_base_id)
);
