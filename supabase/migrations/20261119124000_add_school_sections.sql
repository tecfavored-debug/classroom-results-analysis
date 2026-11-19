create table if not exists public.school_sections (
  id text primary key,
  name text not null unique,
  sort_order smallint not null unique
);

insert into public.school_sections (id, name, sort_order)
values
  ('lower-primary', 'Lower Primary', 1),
  ('upper-primary', 'Upper Primary', 2),
  ('junior-school', 'Junior School', 3),
  ('senior-school', 'Senior School', 4)
on conflict (id) do update
set name = excluded.name,
    sort_order = excluded.sort_order;

alter table public.school_classes
  add column if not exists section_id text references public.school_sections (id);

update public.school_classes
set section_id = 'junior-school'
where lower(btrim(name)) in ('grade 8', 'grade 9')
  and section_id is null;

do $$
begin
  if exists (select 1 from public.school_classes where section_id is null) then
    raise exception 'Every existing class must be assigned to a school section before this migration can continue.';
  end if;
end
$$;

alter table public.school_classes
  alter column section_id set not null;

create index if not exists school_classes_section_idx
  on public.school_classes (section_id, name);

alter table public.school_subjects
  add column if not exists section_id text references public.school_sections (id);

update public.school_subjects
set section_id = 'junior-school'
where section_id is null;

alter table public.school_subjects
  alter column section_id set not null;

drop index if exists public.school_subjects_name_lower_uidx;

create unique index if not exists school_subjects_section_name_lower_uidx
  on public.school_subjects (section_id, lower(name));

alter table public.school_sections enable row level security;

create policy "staff can read school sections"
on public.school_sections
for select to authenticated
using ((select public.has_staff_access()));

grant select on public.school_sections to authenticated;
