begin;

create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 160),
  created_at timestamptz not null default now()
);

insert into public.schools (name)
select 'Existing School'
where not exists (select 1 from public.schools);

alter table public.profiles
  add column if not exists school_id uuid references public.schools (id) on delete restrict;

update public.profiles
set school_id = (select id from public.schools order by created_at, id limit 1)
where school_id is null
  and role <> 'pending';

alter table public.profiles
  alter column role drop default,
  alter column role set default 'pending',
  drop constraint if exists profiles_role_check,
  add constraint profiles_role_check check (role in ('owner', 'admin', 'teacher', 'pending')),
  add constraint profiles_membership_check check (
    (role = 'pending' and school_id is null)
    or (role <> 'pending' and school_id is not null)
  );

create or replace function public.current_school_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select school_id
  from public.profiles
  where id = (select auth.uid())
    and role in ('owner', 'admin', 'teacher')
$$;

revoke all on function public.current_school_id() from public, anon;
grant execute on function public.current_school_id() to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('owner', 'admin')
      and school_id is not null
  );
$$;

create or replace function public.has_staff_access()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role in ('owner', 'admin', 'teacher')
      and school_id is not null
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
revoke all on function public.has_staff_access() from public, anon;
grant execute on function public.has_staff_access() to authenticated;

alter table public.school_classes
  add column if not exists school_id uuid references public.schools (id) on delete cascade;
alter table public.school_streams
  add column if not exists school_id uuid references public.schools (id) on delete cascade;
alter table public.school_students
  add column if not exists school_id uuid references public.schools (id) on delete cascade;
alter table public.school_results
  add column if not exists school_id uuid references public.schools (id) on delete cascade;
alter table public.school_subjects
  add column if not exists school_id uuid references public.schools (id) on delete cascade;
alter table public.school_assessments
  add column if not exists school_id uuid references public.schools (id) on delete cascade;

do $$
declare
  legacy_school_id uuid;
begin
  select id into strict legacy_school_id
  from public.schools
  order by created_at, id
  limit 1;

  update public.school_classes set school_id = legacy_school_id;
  update public.school_streams set school_id = legacy_school_id;
  update public.school_students set school_id = legacy_school_id;
  update public.school_results set school_id = legacy_school_id;
  update public.school_subjects set school_id = legacy_school_id;
  update public.school_assessments set school_id = legacy_school_id;
end
$$;

alter table public.school_classes
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null,
  add constraint school_classes_id_school_key unique (id, school_id);
alter table public.school_streams
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null,
  add constraint school_streams_id_class_school_key unique (id, class_id, school_id);
alter table public.school_students
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null,
  add constraint school_students_id_school_key unique (id, school_id);
alter table public.school_results
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null;
alter table public.school_subjects
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null;
alter table public.school_assessments
  alter column school_id set default public.current_school_id(),
  alter column school_id set not null;

alter table public.school_streams
  drop constraint if exists school_streams_class_id_fkey,
  add constraint school_streams_class_school_fkey
    foreign key (class_id, school_id)
    references public.school_classes (id, school_id) on delete cascade;
alter table public.school_students
  drop constraint if exists school_students_class_id_fkey,
  drop constraint if exists school_students_stream_id_class_id_fkey,
  add constraint school_students_class_school_fkey
    foreign key (class_id, school_id)
    references public.school_classes (id, school_id) on delete cascade,
  add constraint school_students_stream_class_school_fkey
    foreign key (stream_id, class_id, school_id)
    references public.school_streams (id, class_id, school_id) on delete cascade;
alter table public.school_results
  drop constraint if exists school_results_student_id_fkey,
  add constraint school_results_student_school_fkey
    foreign key (student_id, school_id)
    references public.school_students (id, school_id) on delete cascade;

drop index if exists public.school_classes_name_lower_uidx;
create unique index school_classes_school_name_lower_uidx
  on public.school_classes (school_id, lower(name));
drop index if exists public.school_streams_class_name_lower_uidx;
create unique index school_streams_school_class_name_lower_uidx
  on public.school_streams (school_id, class_id, lower(name));
drop index if exists public.school_students_admission_number_lower_uidx;
create unique index school_students_school_admission_number_lower_uidx
  on public.school_students (school_id, lower(admission_number))
  where admission_number is not null;
drop index if exists public.school_subjects_section_name_lower_uidx;
create unique index school_subjects_school_section_name_lower_uidx
  on public.school_subjects (school_id, section_id, lower(name));
drop index if exists public.school_assessments_name_lower_uidx;
create unique index school_assessments_school_name_lower_uidx
  on public.school_assessments (school_id, lower(name));
alter table public.school_results
  drop constraint if exists school_results_student_id_subject_assessment_assessment_date_key;
create unique index school_results_school_student_subject_assessment_date_uidx
  on public.school_results (school_id, student_id, subject, assessment, assessment_date);

create table if not exists public.school_setup_tokens (
  token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users (id) on delete set null,
  school_id uuid references public.schools (id) on delete set null,
  check (
    (redeemed_at is null and redeemed_by is null and school_id is null)
    or (redeemed_at is not null and redeemed_by is not null and school_id is not null)
  )
);

alter table public.schools enable row level security;
alter table public.school_setup_tokens enable row level security;

revoke all on table public.school_setup_tokens from anon, authenticated;
grant all on table public.school_setup_tokens to service_role;

create or replace function public.redeem_school_setup_token(
  token_digest text,
  school_name text,
  redeeming_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched_token public.school_setup_tokens%rowtype;
  created_school_id uuid;
begin
  if token_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'That school setup token is invalid or expired.' using errcode = '22023';
  end if;
  if length(btrim(school_name)) not between 1 and 160 then
    raise exception 'Enter a school name between 1 and 160 characters.' using errcode = '22023';
  end if;

  select * into matched_token
  from public.school_setup_tokens
  where token_hash = token_digest
    and redeemed_at is null
    and expires_at > now()
  for update;
  if not found then
    raise exception 'That school setup token is invalid, expired or already used.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = redeeming_user_id
      and role = 'pending'
      and school_id is null
  ) then
    raise exception 'This account has already been assigned to a school.' using errcode = '42501';
  end if;

  insert into public.schools (name)
  values (btrim(school_name))
  returning id into created_school_id;

  update public.school_setup_tokens
  set redeemed_at = now(),
      redeemed_by = redeeming_user_id,
      school_id = created_school_id
  where token_hash = token_digest;

  update public.profiles
  set school_id = created_school_id,
      role = 'admin'
  where id = redeeming_user_id;

  return created_school_id;
end;
$$;

revoke all on function public.redeem_school_setup_token(text, text, uuid) from public, anon, authenticated;
grant execute on function public.redeem_school_setup_token(text, text, uuid) to service_role;

create or replace function public.admin_set_profile_role(
  target_user_id uuid,
  new_role text,
  actor_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_school_id uuid;
  existing_role text;
  admin_count integer;
begin
  if new_role not in ('admin', 'teacher') then
    raise exception 'Choose a valid account role.' using errcode = '22023';
  end if;
  if target_user_id = actor_user_id then
    raise exception 'You cannot change your own account role.' using errcode = '22023';
  end if;

  select school_id into actor_school_id
  from public.profiles
  where id = actor_user_id
    and role in ('owner', 'admin');
  if not found then
    raise exception 'Only school administrators can manage accounts.' using errcode = '42501';
  end if;

  select role into existing_role
  from public.profiles
  where id = target_user_id
    and school_id = actor_school_id
    and role in ('admin', 'teacher')
  for update;
  if not found then
    raise exception 'The selected account was not found in your school.' using errcode = 'P0002';
  end if;

  if existing_role = 'admin' and new_role = 'teacher' then
    select count(*) into admin_count
    from public.profiles
    where school_id = actor_school_id
      and role in ('owner', 'admin');
    if admin_count <= 1 then
      raise exception 'Promote another administrator before changing the last admin account.' using errcode = '23514';
    end if;
  end if;

  update public.profiles
  set role = new_role
  where id = target_user_id
    and school_id = actor_school_id;
end;
$$;

revoke all on function public.admin_set_profile_role(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_set_profile_role(uuid, text, uuid) to service_role;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, role, school_id)
  values (new.id, new.email, 'pending', null)
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$;

drop policy if exists "profiles_select_self_or_admin" on public.profiles;
create policy "profiles_select_self"
on public.profiles
for select
to authenticated
using (id = (select auth.uid()));

drop policy if exists "staff can read classes" on public.school_classes;
drop policy if exists "staff can add classes" on public.school_classes;
create policy "staff can read classes"
on public.school_classes
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add classes"
on public.school_classes
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read streams" on public.school_streams;
drop policy if exists "staff can add streams" on public.school_streams;
create policy "staff can read streams"
on public.school_streams
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add streams"
on public.school_streams
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read students" on public.school_students;
drop policy if exists "staff can add students" on public.school_students;
create policy "staff can read students"
on public.school_students
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add students"
on public.school_students
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read results" on public.school_results;
drop policy if exists "staff can add results" on public.school_results;
drop policy if exists "staff can correct results" on public.school_results;
create policy "staff can read results"
on public.school_results
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add results"
on public.school_results
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can correct results"
on public.school_results
for update to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()))
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read subjects" on public.school_subjects;
drop policy if exists "staff can add subjects" on public.school_subjects;
create policy "staff can read subjects"
on public.school_subjects
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add subjects"
on public.school_subjects
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read assessments" on public.school_assessments;
drop policy if exists "staff can add assessments" on public.school_assessments;
create policy "staff can read assessments"
on public.school_assessments
for select to authenticated
using (school_id = (select public.current_school_id()) and (select public.has_staff_access()));
create policy "staff can add assessments"
on public.school_assessments
for insert to authenticated
with check (school_id = (select public.current_school_id()) and (select public.has_staff_access()));

drop policy if exists "staff can read school sections" on public.school_sections;
create policy "staff can read school sections"
on public.school_sections
for select to authenticated
using ((select public.has_staff_access()));

create policy "members can read own school"
on public.schools
for select to authenticated
using (id = (select public.current_school_id()));
create policy "admins can rename own school"
on public.schools
for update to authenticated
using (id = (select public.current_school_id()) and (select public.is_admin()))
with check (id = (select public.current_school_id()) and (select public.is_admin()));

revoke all on table public.schools from anon, authenticated;
grant select, update on public.schools to authenticated;
grant select, insert on public.school_classes to authenticated;
grant select, insert on public.school_streams to authenticated;
grant select, insert on public.school_students to authenticated;
grant select, insert, update on public.school_results to authenticated;
grant select, insert on public.school_subjects to authenticated;
grant select, insert on public.school_assessments to authenticated;

commit;
