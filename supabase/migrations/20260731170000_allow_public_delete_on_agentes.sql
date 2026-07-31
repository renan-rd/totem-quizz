-- Allow prototype clients to delete agents for the default account.

drop policy if exists "Allow public delete on agentes" on public.agentes;
create policy "Allow public delete on agentes"
on public.agentes
for delete
to anon, authenticated
using (account_id = '00000000-0000-0000-0000-000000000001');
