-- ============================================================================
--  PAINEL DE INSTRUTOR - RODE NO SQL EDITOR
--
--  1. Adiciona coluna role em profiles (student por padrão)
--  2. Função is_instructor() com security definer (quebra a recursão de RLS)
--  3. Políticas que deixam o instrutor ler TUDO (todas as tabelas)
--  4. Marca adaoelias@gmail.com como instrutor
--
--  Segurança: alunos continuam vendo só o próprio material. A única conta
--  com leitura total é a marcada como instructor.
--  Clique no link VERDE (Confirm) para aplicar.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Coluna role
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists role text not null default 'student';

alter table public.profiles
  drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('student', 'instructor'));

-- ---------------------------------------------------------------------------
-- 2. Função is_instructor()  — vê se o usuário logado é instrutor
--    security definer: roda como dono (postgres), então NÃO dispara o RLS
--    de profiles de novo (evita recursão de política). É o padrão Supabase.
-- ---------------------------------------------------------------------------
create or replace function public.is_instructor()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'instructor'
  );
$$;

grant execute on function public.is_instructor() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Políticas de leitura total para o instrutor, em todas as tabelas
-- ---------------------------------------------------------------------------
drop policy if exists "instructor_read_profiles" on public.profiles;
create policy "instructor_read_profiles"
  on public.profiles for select to authenticated
  using (public.is_instructor());

drop policy if exists "instructor_read_panel_progress" on public.panel_progress;
create policy "instructor_read_panel_progress"
  on public.panel_progress for select to authenticated
  using (public.is_instructor());

drop policy if exists "instructor_read_quiz_answers" on public.quiz_answers;
create policy "instructor_read_quiz_answers"
  on public.quiz_answers for select to authenticated
  using (public.is_instructor());

drop policy if exists "instructor_read_checklist_items" on public.checklist_items;
create policy "instructor_read_checklist_items"
  on public.checklist_items for select to authenticated
  using (public.is_instructor());

drop policy if exists "instructor_read_user_notes" on public.user_notes;
create policy "instructor_read_user_notes"
  on public.user_notes for select to authenticated
  using (public.is_instructor());

drop policy if exists "instructor_read_certificates" on public.certificates;
create policy "instructor_read_certificates"
  on public.certificates for select to authenticated
  using (public.is_instructor());

-- ui_state é interno (aba ativa etc. do próprio usuário); o instrutor
-- também pode ler, para debug. Sem necessidade de reescrita.

-- ---------------------------------------------------------------------------
-- 4. Marca o instrutor (adicione outros emails aqui se quiser mais de um)
-- ---------------------------------------------------------------------------
insert into public.profiles (id, email, full_name, role)
select id, email, coalesce(raw_user_meta_data ->> 'full_name', split_part(email, '@', 1)), 'instructor'
from auth.users
where email = 'adaoelias@gmail.com'
  and not exists (select 1 from public.profiles p where p.id = auth.users.id);

update public.profiles
set role = 'instructor'
where email = 'adaoelias@gmail.com';

commit;

-- ---------------------------------------------------------------------------
-- VERIFICAÇÃO
-- ---------------------------------------------------------------------------
-- Rode e confira que retorna 1 linha com role = instructor:
--   select id, email, role from public.profiles where email = 'adaoelias@gmail.com';
--
-- Confira se a função existe:
--   select public.is_instructor();
--   (volta true só se o usuário logado no SQL Editor for o instrutor)
-- ============================================================================