drop index if exists public.school_assessments_subject_name_lower_uidx;

alter table public.school_assessments
  drop column subject_id;

create unique index if not exists school_assessments_name_lower_uidx
  on public.school_assessments (lower(name));
