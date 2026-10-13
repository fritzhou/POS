# Email design previews

These five standalone HTML files are **Placeholder / DESIGN PREVIEW** designs. Open them locally in a browser. Their buttons are deliberately inert spans; no recovery, invitation or verification URL is embedded. The `{{ field_name }}` text shows future rendering fields, not the Supabase template syntax. No emails are sent and no provider secrets are needed.

Supabase Auth's configured built-in sender handles real verification and recovery today. These previews have **not** replaced that project's email templates. A future deployment must map verified Supabase template parameters, such as `{{ .ConfirmationURL }}`, to the appropriate action and test real links, redirect allowlists, expiration, HTML escaping, deliverability and plain-text fallbacks. Do not copy literal preview tokens into live templates.

Phase 2 implements the privileged invitation endpoint and verified-email business acceptance. Deployment, Auth Invite/Magic Link template configuration and real email/callback validation are still required; see [INVITATIONS.md](../../docs/INVITATIONS.md). Password-changed and suspicious-login notifications need authenticated server events and actual monitoring; a static design is not evidence that those events are detected or delivered.

`security@nexapos.com` is an example sender, not a configured domain. Custom SMTP, Resend, Postmark, SendGrid and SES are future providers. Sender authentication and credentials belong in backend environment settings, never Flutter.
