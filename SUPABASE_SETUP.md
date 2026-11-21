# Supabase school workspaces and email login

The app uses Supabase Auth for email/password sign-in. A platform owner creates one-time school setup tokens; a token holder creates one school and becomes its first administrator. Every user and school record is scoped to one school by database row-level security. The browser never receives the Supabase service-role key.

These upgrade steps assume the current Supabase project already has the app's profiles and school-data tables.

## 1. Configure the Supabase project

1. Enable the Email provider and email sign-ups. New sign-ups have a `pending` profile and cannot read or write school data until they redeem a valid setup token.
2. Keep email confirmation enabled and configure SMTP so school administrators can verify their email and receive staff invitations.
3. Set the project **Site URL** and allowed redirect URLs to the app's HTTPS origin. For local testing, serve the folder over HTTP and allow that localhost URL; do not use `file://`.
4. Set the Supabase password minimum to 6 characters. The app accepts passwords from 6 to 8 characters; passwords shorter than 8 are less resistant to guessing.
5. Apply migrations with `npx supabase db push --remote`. Migration `20261119170000_add_school_tenants_and_setup_tokens.sql` preserves existing school records in an `Existing School` workspace. Migration `20261121150000_add_school_location_and_rubric.sql` adds report-card location fields and the eight-level CBC rubric.

## 2. Bootstrap the platform owner

Choose which existing administrator will issue school setup tokens, then promote that account to `owner` in the SQL Editor (replace the email). This avoids automatically giving platform-wide setup-token privileges to an arbitrary administrator:

```sql
update public.profiles
set role = 'owner'
where lower(email) = lower('your.admin@school.ac.ke')
  and role = 'admin'
returning id, email, role, school_id;
```

Confirm exactly one row was returned. Rename the old workspace from **Account management → School name**.

If there is no existing administrator, create an Auth user and assign it to the preserved workspace:

```sql
update public.profiles
set role = 'owner',
    school_id = (select id from public.schools order by created_at, id limit 1)
where lower(email) = lower('first.admin@school.ac.ke');
```

Confirm that exactly one row was updated. The platform owner can create school setup tokens. A token expires after seven days and can be redeemed once.

## 3. Deploy the account and token function

From this folder, deploy the account-management function to the linked project and configure the deployed app's URL:

```powershell
npx supabase functions deploy admin-users --use-api
npx supabase secrets set APP_SITE_URL=https://your-app-domain.example
```

The Edge Function uses Supabase's managed publishable/secret key environment variables. Do not copy secret keys into application files.

## 4. Create and share school workspaces

1. Sign in as the platform owner and open **Account management**.
2. Select **Create setup token** and copy the token. It is shown only once and expires in seven days.
3. Send it securely to the first administrator for that school.
4. That person creates an app account and enters the token and school name on the same form. If email confirmation is required, they confirm and sign in before creating the school; the details are temporarily kept in that browser tab and prefilled for completion.
5. The school administrator can invite teachers and other administrators from that school's **Account management** panel. These invitations do not give access to any other school.

Each account can belong to one school. A person already assigned to another school needs a separate account to work in a second school.

## 5. Configure and serve the app

Set the project URL and public anon/publishable key in `supabase-config.js`:

```js
window.APP_CONFIG = {
  supabaseUrl: "https://YOUR_PROJECT_REF.supabase.co",
  supabaseAnonKey: "YOUR_PUBLIC_PUBLISHABLE_KEY"
};
```

Serve `index.html` and `supabase-config.js` from the allowed site URL. The public frontend contains only the Supabase URL and public anon/publishable key, not service-role credentials.

Invited staff can set a 6–8 character password from **Set / change password** after following the invitation link. The **Forgot password?** link sends a reset email; reset passwords must also be 6–8 characters.

## School data

The app stores classes, streams, students and assessment results in Supabase. Row-level security limits school data to authenticated users with a `teacher`, `admin`, or `owner` profile in that school; they can correct assessment results. A `pending` account has no school access. The public frontend does not contain student records or a service-role key.

Add classes, then streams, then students in **School settings**. School administrators can also enter the school's postal address, locality, ward, sub-county and county, and edit the eight CBC rubric levels and the automatic class-teacher comment for each level. The initial thresholds are EE1 90–100, EE2 75–89, ME1 58–74, ME2 41–57, AE1 31–40, AE2 21–30, BE1 11–20 and BE2 0–10; verify or adjust them for your approved school rubric. CSV results are matched to existing students by `AdmissionNumber` when provided; otherwise the student name must be unique within any supplied class and stream. Required CSV columns are `Student`, `Subject` and `Score`. Optional columns are `AdmissionNumber`, `Class`, `Stream`, `Assessment`, `MaxScore` and `Date` (`YYYY-MM-DD`). Re-importing the same student, subject, assessment and date updates that result.

Class and stream reports summarize all subjects and assessments. The average is weighted by possible marks; counts for each of the eight CBC levels are per assessment result. Report-card class-teacher comments are generated from each learner's overall level using the matching editable comment. Ensure the school's student-data privacy requirements are met before storing identifiable results.
