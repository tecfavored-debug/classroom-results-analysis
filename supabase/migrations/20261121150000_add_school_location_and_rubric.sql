begin;

alter table public.schools
  add column if not exists postal_address text not null default '',
  add column if not exists locality text not null default '',
  add column if not exists ward text not null default '',
  add column if not exists sub_county text not null default '',
  add column if not exists county text not null default '',
  add column if not exists grading_rubric jsonb not null default '[
    {"code":"EE1","descriptor":"Exceeding Expectations 1","minimum":90,"points":8,"teacherComment":"has demonstrated outstanding academic performance this term. Keep it up!"},
    {"code":"EE2","descriptor":"Exceeding Expectations 2","minimum":75,"points":7,"teacherComment":"has demonstrated excellent progress. Keep working hard to maintain this level."},
    {"code":"ME1","descriptor":"Meeting Expectations 1","minimum":58,"points":6,"teacherComment":"has shown very good progress. Aim even higher next term."},
    {"code":"ME2","descriptor":"Meeting Expectations 2","minimum":41,"points":5,"teacherComment":"is making steady progress. Regular practice will strengthen understanding."},
    {"code":"AE1","descriptor":"Approaching Expectations 1","minimum":31,"points":4,"teacherComment":"is developing essential skills. Consistent effort will lead to improvement."},
    {"code":"AE2","descriptor":"Approaching Expectations 2","minimum":21,"points":3,"teacherComment":"is beginning to grasp key concepts. Regular practice and support are encouraged."},
    {"code":"BE1","descriptor":"Below Expectations 1","minimum":11,"points":2,"teacherComment":"needs focused support in several learning areas. Work closely with the teacher on practice."},
    {"code":"BE2","descriptor":"Below Expectations 2","minimum":0,"points":1,"teacherComment":"requires extra support and regular guided practice to build foundational skills."}
  ]'::jsonb;

alter table public.schools
  add constraint schools_grading_rubric_eight_levels_check
  check (jsonb_typeof(grading_rubric) = 'array' and jsonb_array_length(grading_rubric) = 8);

commit;
