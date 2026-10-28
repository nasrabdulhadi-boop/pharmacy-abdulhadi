# Preview authentication mutation safety gate

Auth mutations (password update and recovery-email dispatch) are disabled by default.

They require BOTH:
- VITE_ENABLE_AUTH_MUTATIONS=true on an explicitly isolated preview deployment
- VITE_SUPABASE_URL must NOT point to production project eewjjzgwoaxhojnjvzgq.

Do not set this flag on production or on preview deployments that use production Supabase.
This gate protects the current preview UI only; it is not an authorization boundary.
The existing app login and customer workflows remain unchanged.

Before enabling:
1. Provision an isolated no-cost Auth test environment.
2. Configure staging redirect allowlist and SMTP (or use test inbox).
3. Use test accounts and verify recovery redirect and password update end-to-end.
4. Run role/RLS/RPC denial tests and review the Root legacy admin email fallback.
5. Do not deploy to production without explicit approval.
