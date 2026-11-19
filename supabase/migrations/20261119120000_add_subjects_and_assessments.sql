create table if not exists public.school_subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 100),
  created_at timestamptz not null default now()
);

create unique index if not exists school_subjects_name_lower_uidx
  on public.school_subjects (lower(name));

create table if not exists public.school_assessments (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.school_subjects (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 120),
  assessment_date date,
  created_at timestamptz not null default now()
);

create unique index if not exists school_assessments_subject_name_lower_uidx
  on public.school_assessments (subject_id, lower(name));

create index if not exists school_assessments_date_idx
  on public.school_assessments (assessment_date);

alter table public.school_subjects enable row level security;
alter table public.school_assessments enable row level security;

create policy "staff can read subjects"
on public.school_subjects
for select to authenticated
using ((select public.has_staff_access()));

create policy "staff can add subjects"
on public.school_subjects
for insert to authenticated
with check ((select public.has_staff_access()));

create policy "staff can read assessments"
on public.school_assessments
for select to authenticated
using ((select public.has_staff_access()));

create policy "staff can add assessments"
on public.school_assessments
for insert to authenticated
with check ((select public.has_staff_access()));

grant select, insert on public.school_subjects to authenticated;
grant select, insert on public.school_assessments to authenticated;
