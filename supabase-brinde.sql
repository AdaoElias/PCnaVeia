-- ============================================================================
--  BRINDE 1 — liberar a trilha "brinde-1" em panel_progress
--
--  O site já tem a aba Brinde 1, mas o banco recusa o placar dessa trilha
--  porque o CHECK da coluna panel_key só aceitava as oito trilhas antigas.
--  Rode este arquivo uma vez no SQL Editor do Supabase. É idempotente.
-- ============================================================================

begin;

alter table public.panel_progress
  drop constraint if exists panel_progress_panel_key_check;

alter table public.panel_progress
  add constraint panel_progress_panel_key_check check (panel_key in (
    'aula-1','extra-1','aula-2','extra-2',
    'aula-3','extra-3','aula-4','extra-4',
    'brinde-1'
  ));

commit;

-- Confirmação: deve retornar a lista com brinde-1.
--   select conname, pg_get_constraintdef(oid)
--   from pg_constraint
--   where conrelid = 'public.panel_progress'::regclass
--     and conname = 'panel_progress_panel_key_check';
-- ============================================================================
