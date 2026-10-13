# Employee administration

The Employees module uses a verified organization-scoped `EmployeeRepository`. It loads confirmed memberships and authorized active branches from the backend. A preview or missing repository displays an empty Not Yet Connected state with Add Employee disabled. There are no sample staff, optimistic roster entries, public employee registrations or client-side membership grants.

Owner and Admin can open the roster. Owner can invite and manage non-Owner employees, including Admins. Admin can invite and manage Manager, Cashier and Inventory Staff, within their authorized branches. The UI disables managing Owner, Admin targets for an Admin actor, the current membership, pending memberships and employees whose existing branches fall outside the Admin's visible scope. PostgreSQL independently enforces role, status, branch and organization permissions. Owner transfer and changing an Owner membership are deferred.

## Invitations

Add Employee requires full name, valid email, an allowed role, at least one authorized branch and a reason. Employee ID and phone are optional. Owner may grant an Admin all branches or a selected branch scope. Staff roles require selected branches.

The form submits `EmployeeInvitationInput` to the `employee-invitations` Edge Function through the repository. It retains a generated request UUID and the submitted inputs across transport retries, preventing a retry from creating another delivery request. Input validation occurs before submission. The form waits for the server; a timeout, unknown exception or failed response never produces a success message or grants access.

- HTTP 200 with `delivery_state: sent` displays **Invitation submitted to Supabase Auth. Email delivery has not been confirmed.** This is confirmation of the server/provider operation, not confirmation that an email reached an inbox.
- HTTP 202 with `delivery_state: sending` displays a pending result requiring manual review and warns against sending a duplicate request.
- An unknown transport result keeps the request available for a safe retry with the same UUID. Public repository messages are shown for permission or input errors; raw backend errors are never displayed.

The recipient must use the invited verified email, sign in and explicitly accept the pending invitation in the authentication flow. Acceptance obtains role and branches from the server-side invitation; the client does not choose them. The roster reloads server records after a result, without inventing a new employee membership.

## Access changes

Manage access updates role, active/disabled status and branches with a required reason. Every update carries the roster record's expected revision. If another administrator changed that membership, a conflict keeps the form open and instructs the user to close it, refresh the roster and review the latest access before saving again. No local fallback reports success.

Employee PIN reset and new PIN-based offline employee sign-in remain Coming Soon. Phase 4 separately permits verified grant-backed device workspace resume for an existing remembered identity and online-opened shift; it does not implement new offline employee authentication. There is no simulated reset or stub success.

## Contacts

The Suppliers and Customers modules use `PeopleRepository` with name search, status filters, server pagination and branch scope. Desktop widths show tables; phone widths show cards. Owner, Admin, Manager and Inventory Staff may manage suppliers. Owner, Admin and Manager may manage customers; Cashier receives read-only customer lookup. Manager and Inventory Staff must choose an assigned branch when writing contacts. Active/inactive changes are part of a contact update with its expected revision. Conflicts require a refreshed record.

## Verification

Widget tests cover disconnected previews, role restrictions, input validation, asynchronous confirmation, invitation 200/202 states, sanitized unknown failures, UUID-preserving retries, revision conflicts, search/pagination and 320-pixel phone layouts. These tests use explicit repository fixtures. They do not validate real Supabase email delivery, Auth callbacks, physical devices or deployment configuration; those need a configured non-production Supabase project and target devices.
