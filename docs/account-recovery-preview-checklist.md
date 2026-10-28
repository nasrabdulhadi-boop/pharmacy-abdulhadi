# Authentication recovery preview checklist

- Login now exposes an optional **Forgot password?** request.
- Uses Supabase Auth resetPasswordForEmail(email, {redirectTo: window.location.origin + '/#admin'}).
- No email is sent until the user submits the recovery form.
- UI uses a generic successful response that does not reveal account existence.
- The recovery email flow depends on the Supabase Auth SMTP configuration, allowed redirect URLs, email template, and rate limits.
- Reset link processing and setting the new password need a full browser end-to-end test; **not verified yet**.
- A Vercel preview may use production Supabase credentials: a preview branch is not a database isolation boundary. Never run actual password reset tests on the owner's account without explicit approval.
- Current root gate still uses legacy admin metadata or hard-coded owner email; do not add technical-support logins before server authorization is reviewed.
- Account recovery must require verified ownership of the email; MFA/re-authentication should be added for high-risk operations.
- No changes were made to production Auth configuration or database.
