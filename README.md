# Classroom Results Analysis

A GitHub Pages results dashboard with Supabase email/password sign-in and shared school data.

Authorized staff can manage classes, streams and students across Lower Primary, Upper Primary, Junior School and Senior School; add section-specific subjects and school-wide examinations; enter class scores in a grid with one column per subject; import assessment results; review CBE-style summaries; and print individual report cards and sample-style class or stream analysis. The score grid lets staff set each subject's maximum marks and skips blank cells when saving. Class analysis includes a full roster, class mean, overall CBE level, best subject, stream means, subject rankings, learner positions, and each learner's percentage for every subject in the report; the subject analysis appears after the learner positions. Edge's print dialog can save reports as PDF. Individual cards show all recorded assessments for that learner; KCPE marks, points conversion, teacher remarks and signatures are left for the school to complete. School records are stored in Supabase with row-level security; the public site uses the frontend and public Supabase key, not a copy of the student records.

Before using the subject and examination controls, apply the migrations in `supabase/migrations` to the Supabase project. Existing Grade 8/9 classes and current subjects are assigned to Junior School; new classes and subjects must be assigned to a school section.

CSV results are matched to students and require a subject registered for that student's school section. `SchoolSection` is optional when importing; `Student`, `Subject` and `Score` are required.

Never put passwords, access tokens, service-role keys, or student records in this repository. Follow your school's student-data privacy requirements before entering identifiable results. CBE percentage bands are reporting aids and should be checked against the school's assessment rubric.
