-- ============================================================================
--  PC na Veia | Trilha de manutenção
--  Schema do Supabase (PostgreSQL)
--
--  Como aplicar
--  -------------
--  1. Supabase Dashboard -> SQL Editor -> New query
--  2. Cole este arquivo inteiro
--  3. Clique em Run (ou Ctrl+Enter)
--
--  Este script é idempotente: pode rodar várias vezes sem quebrar nada.
--  A tabela auth.users e o schema auth são gerenciados pelo Supabase —
--  não alteramos, apenas lemos (references + trigger).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. profiles — extensão do usuário (criada automaticamente no cadastro)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text,
  full_name   text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Dados de perfil do aluno. Uma linha por usuário, criada via trigger no cadastro.';

-- ---------------------------------------------------------------------------
-- 2. panel_progress — placar agregado por trilha
--    Derivado do quiz + checklists. Serve para ranking e relatório do instrutor.
--    Chave: user_id + panel_key
-- ---------------------------------------------------------------------------
create table if not exists public.panel_progress (
  id            bigserial primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  panel_key     text not null check (panel_key in (
                  'aula-1','extra-1','aula-2','extra-2',
                  'aula-3','extra-3','aula-4','extra-4'
                )),
  quiz_correct  int not null default 0,
  quiz_total    int not null default 0,
  practice_done int not null default 0,
  practice_total int not null default 0,
  updated_at    timestamptz not null default now(),
  unique (user_id, panel_key)
);

-- ---------------------------------------------------------------------------
-- 3. quiz_answers — uma linha por pergunta respondida
--    Guarda a opção escolhida para restaurar o gabarito bloqueado.
--    Chave: user_id + panel_key + question_id
-- ---------------------------------------------------------------------------
create table if not exists public.quiz_answers (
  id           bigserial primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  panel_key    text not null,
  question_id  text not null,          -- ex.: a1-q1
  chosen_opt   int  not null check (chosen_opt between 0 and 3),
  is_correct   boolean not null,
  answered_at  timestamptz not null default now(),
  unique (user_id, panel_key, question_id)
);

-- ---------------------------------------------------------------------------
-- 4. checklist_items — uma linha por item marcado
--    Cobre os checklists (e1-data) e os desafios (a1-done).
--    O prefixo antes do "-" é o checklist_key.
--    Chave: user_id + checklist_key + item_key
-- ---------------------------------------------------------------------------
create table if not exists public.checklist_items (
  id             bigserial primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  checklist_key  text not null,
  item_key       text not null,        -- ex.: e1-data, a1-done
  checked        boolean not null default false,
  updated_at     timestamptz not null default now(),
  unique (user_id, checklist_key, item_key)
);

-- ---------------------------------------------------------------------------
-- 5. user_notes — anotações livres do aluno
--    Chave: user_id + note_key
-- ---------------------------------------------------------------------------
create table if not exists public.user_notes (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  note_key   text not null,            -- ex.: a1
  content    text not null default '',
  updated_at timestamptz not null default now(),
  unique (user_id, note_key)
);

-- ---------------------------------------------------------------------------
-- 6. ui_state — preferências de interface
--    Hoje usamos key = 'active_tab' para guardar a última trilha aberta.
-- ---------------------------------------------------------------------------
create table if not exists public.ui_state (
  id         bigserial primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  unique (user_id, key)
);

-- ---------------------------------------------------------------------------
-- 7. certificates — histórico de emissões (append-only)
--    Sem unique de propósito: reemitir guarda um novo registro, não sobrescreve.
--    O hash em payload é a prova de integridade exibida ao aluno.
-- ---------------------------------------------------------------------------
create table if not exists public.certificates (
  id               bigserial primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  certificate_type text not null,      -- ex.: 'trilha-completa'
  title            text not null,
  issued_at        timestamptz not null default now(),
  payload          jsonb not null default '{}'::jsonb
);

create index if not exists certificates_user_idx on public.certificates (user_id, issued_at desc);

-- ---------------------------------------------------------------------------
-- Índices de leitura (o cliente filtra sempre por user_id)
-- ---------------------------------------------------------------------------
create index if not exists panel_progress_user_idx  on public.panel_progress (user_id);
create index if not exists quiz_answers_user_idx     on public.quiz_answers (user_id, panel_key);
create index if not exists quiz_answers_question_idx on public.quiz_answers (user_id, question_id);
create index if not exists checklist_items_user_idx  on public.checklist_items (user_id, checklist_key);
create index if not exists user_notes_user_idx       on public.user_notes (user_id);
create index if not exists ui_state_user_idx        on public.ui_state (user_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Cada aluno só enxerga e altera as próprias linhas.
-- ---------------------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.panel_progress   enable row level security;
alter table public.quiz_answers     enable row level security;
alter table public.checklist_items  enable row level security;
alter table public.user_notes       enable row level security;
alter table public.ui_state         enable row level security;
alter table public.certificates     enable row level security;

drop policy if exists "own" on public.profiles;
drop policy if exists "own" on public.panel_progress;
drop policy if exists "own" on public.quiz_answers;
drop policy if exists "own" on public.checklist_items;
drop policy if exists "own" on public.user_notes;
drop policy if exists "own" on public.ui_state;
drop policy if exists "own" on public.certificates;

-- FOR ALL usa a mesma expressão para USING e WITH CHECK:
-- permite select, insert, update e delete apenas do próprio usuário.
create policy "own" on public.profiles
  for all to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "own" on public.panel_progress
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own" on public.quiz_answers
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own" on public.checklist_items
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own" on public.user_notes
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own" on public.ui_state
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own" on public.certificates
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Permissões
-- RLS sozinho não basta: o papel também precisa de privilégio na tabela.
-- service_role (backend) ignora RLS e enxerga tudo.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on
  public.profiles, public.panel_progress, public.quiz_answers,
  public.checklist_items, public.user_notes, public.ui_state,
  public.certificates
  to authenticated;

-- O papel anon NÃO recebe privilégio aqui de propósito: o app exige login,
-- e o RLS já bloquearia tudo mesmo se recebesse. Se o Auth "Enable email
-- confirmations" estiver ligado, use apenas a service_role no backend.

grant usage, select on sequence public.panel_progress_id_seq,
  public.quiz_answers_id_seq, public.checklist_items_id_seq,
  public.user_notes_id_seq, public.ui_state_id_seq, public.certificates_id_seq
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Trigger: updated_at automático
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated        on public.profiles;
drop trigger if exists trg_panel_progress_updated  on public.panel_progress;
drop trigger if exists trg_checklist_items_updated on public.checklist_items;
drop trigger if exists trg_user_notes_updated      on public.user_notes;
drop trigger if exists trg_ui_state_updated        on public.ui_state;

create trigger trg_profiles_updated
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger trg_panel_progress_updated
  before update on public.panel_progress
  for each row execute function public.set_updated_at();

create trigger trg_checklist_items_updated
  before update on public.checklist_items
  for each row execute function public.set_updated_at();

create trigger trg_user_notes_updated
  before update on public.user_notes
  for each row execute function public.set_updated_at();

create trigger trg_ui_state_updated
  before update on public.ui_state
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Trigger: cria o perfil automaticamente no cadastro
-- security definer porque o INSERT roda como o dono da tabela,
-- e o aluno ainda não tem policy válida naquele instante do cadastro.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1)),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- View: resumo do aluno
--
-- IMPORTANTE: a view precisa de GRANT SELECT explícito para
-- authenticated. O PostgREST esconde do schema cache qualquer relação sem
-- privilégio para o papel, e o sintoma é um PGRST205 "Could not find the
-- table" que parece tabela inexistente, mas não é. Não use bloco DO aqui:
-- ele engole o erro e deixa o script "verde" com a view faltando.
-- ---------------------------------------------------------------------------
drop view if exists public.my_progress_summary;

create view public.my_progress_summary
with (security_invoker = true)
as
select
    -- profiles tem PK "id"; o alias mantém a coluna como user_id para o front
    p.id                                               as user_id,
    p.email,
    p.full_name,
    count(distinct pp.panel_key)                        as trilhas_iniciadas,
    coalesce(sum(pp.quiz_correct), 0)                   as acertos_quiz,
    coalesce(sum(pp.quiz_total), 0)                     as total_quiz,
    coalesce(sum(pp.practice_done), 0)                  as tarefas_marcadas,
    coalesce(sum(pp.practice_total), 0)                 as total_tarefas,
    (select count(*) from public.quiz_answers qa where qa.user_id = p.id)      as perguntas_respondidas,
    (select count(*) from public.user_notes un where un.user_id = p.id
       and btrim(un.content) <> '')                     as anotacoes_preenchidas,
    (select count(*) from public.certificates c where c.user_id = p.id)        as certificados,
    max(greatest(pp.updated_at, p.updated_at))          as ultima_atividade
  from public.profiles p
  left join public.panel_progress pp on pp.user_id = p.id
  where p.id = auth.uid()
  group by p.id, p.email, p.full_name;

grant select on public.my_progress_summary to authenticated;
grant select on public.my_progress_summary to service_role;

comment on view public.my_progress_summary is
  'Resumo do aluno logado. Filtra por auth.uid() e pelo RLS das tabelas base.';

commit;

-- ============================================================================
--  PRÓXIMOS PASSOS
--
--  1. Authentication -> URL Configuration
--     Site URL:        https://SEU_USUARIO.github.io/SEU_REPO/
--     Redirect URLs:   https://SEU_USUARIO.github.io/SEU_REPO/**
--                      http://localhost:8000/**
--
--  2. Authentication -> Providers
--     Email: habilitado
--     GitHub / Google: habilitado (redirect nas duas chaves acima)
--
--  3. Settings -> API
--     Copie Project URL e a chave "anon public" para o supabase-client.js
--
--  4. Se aparecer erro de permissão depois disso, confira o console do
--     navegador: 401 = URL/chave errada; 403 = RLS ou grant faltando.
-- ============================================================================
