-- ============================================================================
--  CORREÇÃO: view my_progress_summary
--
--  O primeiro script criou a view, mas sem GRANT para os papéis do app.
--  O PostgREST esconde do schema cache qualquer relação sem privilégio,
--  então a API respondia PGRST205 "Could not find the table" mesmo com a
--  view presente no banco. Isso é comportamento esperado dele, não bug.
--
--  Rode este arquivo no SQL Editor. É idempotente.
-- ============================================================================

begin;

-- Recria sem o WITH security_invoker para evitar qualquer incompatibilidade
-- de versão; em vez disso usamos um SECURITY BARRIER invoker-free e
-- filtramos explicitamente por auth.uid(), que é o que realmente importa.
drop view if exists public.my_progress_summary;

create view public.my_progress_summary
with (security_invoker = true)
as
select
  -- profiles tem PK "id"; o alias expõe a coluna como user_id
  p.id                                                     as user_id,
  p.email,
  p.full_name,
  count(distinct pp.panel_key)                              as trilhas_iniciadas,
  coalesce(sum(pp.quiz_correct), 0)                         as acertos_quiz,
  coalesce(sum(pp.quiz_total), 0)                           as total_quiz,
  coalesce(sum(pp.practice_done), 0)                        as tarefas_marcadas,
  coalesce(sum(pp.practice_total), 0)                       as total_tarefas,
  (select count(*) from public.quiz_answers qa
     where qa.user_id = p.id)                               as perguntas_respondidas,
  (select count(*) from public.user_notes un
     where un.user_id = p.id and btrim(un.content) <> '')  as anotacoes_preenchidas,
  (select count(*) from public.certificates c
     where c.user_id = p.id)                                as certificados,
  max(greatest(pp.updated_at, p.updated_at))                as ultima_atividade
from public.profiles p
left join public.panel_progress pp on pp.user_id = p.id
where p.id = auth.uid()      -- belt-and-braces: só a própria linha
group by p.id, p.email, p.full_name;

-- Esta é a linha que faltava. Sem ela a view fica invisível para a API.
grant select on public.my_progress_summary to authenticated;
grant select on public.my_progress_summary to service_role;

comment on view public.my_progress_summary is
  'Resumo do aluno logado. Filtra por auth.uid() e por RLS das tabelas base.';

commit;

-- Confirme que apareceu no schema cache da API antes de usar no front:
--   select * from public.my_progress_summary;
-- Deve retornar 0 linhas (ou 1, se houver perfil), nunca erro de permissão.
