import { withSupabase } from "npm:@supabase/server@1";

type Role = "owner" | "admin" | "teacher" | "pending";
type RequestBody = {
  action?: unknown;
  email?: unknown;
  role?: unknown;
  userId?: unknown;
  token?: unknown;
  schoolName?: unknown;
};
type Profile = {
  role: Role;
  school_id: string | null;
};

function respond(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}

function isRole(value: unknown): value is Role {
  return value === "owner" || value === "admin" || value === "teacher" || value === "pending";
}

function isSchoolAdmin(profile: Profile): boolean {
  return (profile.role === "owner" || profile.role === "admin") && typeof profile.school_id === "string";
}

function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hashToken(token: string): Promise<string> {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export default {
  fetch: withSupabase({ auth: "user" }, async (request, ctx) => {
    if (request.method !== "POST") return respond({ error: "Method not allowed." }, 405);

    const callerId = ctx.userClaims?.id;
    if (typeof callerId !== "string") return respond({ error: "Your session is invalid or expired." }, 401);

    let input: RequestBody;
    try {
      const body: unknown = await request.json();
      if (!body || typeof body !== "object" || Array.isArray(body)) {
        return respond({ error: "Request body must be a JSON object." }, 400);
      }
      input = body as RequestBody;
    } catch {
      return respond({ error: "Request body must be valid JSON." }, 400);
    }

    const { data: callerProfile, error: profileError } = await ctx.supabaseAdmin
      .from("profiles")
      .select("role, school_id")
      .eq("id", callerId)
      .maybeSingle();
    if (profileError) return respond({ error: "Could not verify your account role." }, 500);
    if (!callerProfile || !isRole(callerProfile.role)) {
      return respond({ error: "Your account has no valid role. Ask an administrator to check your account." }, 403);
    }

    const profile: Profile = callerProfile;

    if (input.action === "create-school-token") {
      if (profile.role !== "owner") return respond({ error: "Only the platform owner can create school setup tokens." }, 403);

      const token = newToken();
      const tokenHash = await hashToken(token);
      const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      const { error } = await ctx.supabaseAdmin.from("school_setup_tokens").insert({
        token_hash: tokenHash,
        created_by: callerId,
        expires_at: expiresAt
      });
      if (error) return respond({ error: "Could not create a school setup token." }, 500);
      return respond({ token, expiresAt }, 201);
    }

    if (input.action === "redeem-school-token") {
      if (profile.role !== "pending" || profile.school_id !== null) {
        return respond({ error: "This account is already assigned to a school." }, 403);
      }
      const token = typeof input.token === "string" ? input.token.trim().toLowerCase() : "";
      const schoolName = typeof input.schoolName === "string" ? input.schoolName.trim() : "";
      if (!/^[0-9a-f]{64}$/.test(token)) return respond({ error: "Enter a valid school setup token." }, 400);
      if (schoolName.length < 1 || schoolName.length > 160) {
        return respond({ error: "Enter a school name between 1 and 160 characters." }, 400);
      }

      const { data: schoolId, error } = await ctx.supabaseAdmin.rpc("redeem_school_setup_token", {
        token_digest: await hashToken(token),
        school_name: schoolName,
        redeeming_user_id: callerId
      });
      if (error) return respond({ error: error.message || "Could not redeem that school setup token." }, 400);
      return respond({ schoolId }, 201);
    }

    if (input.action === "list") {
      if (!isSchoolAdmin(profile)) return respond({ error: "Only school administrators can manage accounts." }, 403);
      const { data: users, error } = await ctx.supabaseAdmin
        .from("profiles")
        .select("id, email, role, created_at")
        .eq("school_id", profile.school_id)
        .order("created_at", { ascending: true });
      if (error) return respond({ error: "Could not retrieve school accounts." }, 502);
      const schoolUsers = users ?? [];
      if (schoolUsers.some((user) => !isRole(user.role) || user.role === "pending")) {
        return respond({ error: "An account has an invalid role. Repair it in Supabase before continuing." }, 500);
      }
      return respond({ users: schoolUsers });
    }

    if (input.action === "invite") {
      if (!isSchoolAdmin(profile)) return respond({ error: "Only school administrators can manage accounts." }, 403);
      const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond({ error: "Enter a valid email address." }, 400);
      if (input.role !== "admin" && input.role !== "teacher") return respond({ error: "Choose a valid account role." }, 400);

      const { data: existingProfile, error: existingProfileError } = await ctx.supabaseAdmin
        .from("profiles")
        .select("school_id")
        .ilike("email", email)
        .maybeSingle();
      if (existingProfileError) return respond({ error: "Could not check whether this email already has an account." }, 502);
      if (existingProfile) {
        return respond({
          error: existingProfile.school_id === null
            ? "This email already has a pending account. Sign in to it and finish school setup first."
            : existingProfile.school_id === profile.school_id
              ? "This email already has an account in your school."
              : "This email already has an account. Each account can belong to one school."
        }, 409);
      }

      const siteUrl = Deno.env.get("APP_SITE_URL");
      const options = siteUrl ? { redirectTo: siteUrl } : undefined;
      const { data: invitation, error: inviteError } = await ctx.supabaseAdmin.auth.admin.inviteUserByEmail(email, options);
      if (inviteError || !invitation.user) {
        return respond({ error: inviteError?.message || "Could not create the account invitation." }, 400);
      }
      const { error: saveRoleError } = await ctx.supabaseAdmin.from("profiles").upsert({
        id: invitation.user.id,
        email,
        role: input.role,
        school_id: profile.school_id
      });
      if (saveRoleError) {
        return respond({ error: "The invitation was created, but its school role could not be saved. Check the user profile in Supabase." }, 500);
      }
      return respond({ user: { id: invitation.user.id, email, role: input.role } }, 201);
    }

    if (input.action === "set-role") {
      if (!isSchoolAdmin(profile)) return respond({ error: "Only school administrators can manage accounts." }, 403);
      const userId = typeof input.userId === "string" ? input.userId : "";
      if (!userId || (input.role !== "admin" && input.role !== "teacher")) {
        return respond({ error: "Choose a valid account and role." }, 400);
      }
      if (userId === callerId) return respond({ error: "You cannot change your own account role." }, 400);

      const { error: updateError } = await ctx.supabaseAdmin.rpc("admin_set_profile_role", {
        target_user_id: userId,
        new_role: input.role,
        actor_user_id: callerId
      });
      if (updateError) return respond({ error: updateError.message }, updateError.code === "42501" ? 403 : 400);
      return respond({ userId, role: input.role });
    }

    return respond({ error: "Unsupported account-management action." }, 400);
  })
};
