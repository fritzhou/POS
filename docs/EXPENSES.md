# Recorded business expenses

Phase 6A provides connected expense history, manually confirmed payment records and one full compensating reversal. Owner, Admin and Manager can use their currently authorized branches. Cashier and Inventory Staff cannot author or read expenses. Production services supply the verified membership, Supabase client, recovery-session check and encrypted actor/business operation journal; the design preview contains an explanatory empty state.

Amounts use positive integer minor units bounded by 9,007,199,254,740,991 in PHP, USD, EUR, GBP, AUD, CAD or SGD. Settings revisions are also bounded exact integers. Categories are Rent, Utilities, Wages, Transport, Maintenance, Fees and Other. A reason is trimmed, 3–1000 characters, and supports ordinary newlines and tabs; unsupported control characters are rejected. Noncash manual payment records require the actual operator-verified reference, 3–120 characters. Actor and activity times originate at the server; the client supplies neither.

The default funding source is **External funds**. This includes cash paid outside the POS drawer. External expenses and their reversals leave expected drawer cash unchanged. Recording an expense acknowledges a payment the operator already verified; it does not send money or establish a bank, card or wallet transaction.

**Own shift cash drawer** is optional and requires an explicit confirmation of an actual physical payout. The current actor must own an open shift in the selected branch and expense currency. The server derives expected cash from opening cash plus cash sales minus sale reversals minus drawer expenses plus drawer expense reversals. Expected cash is a projection, not proof of physical cash availability. Existing signed-grant reconciliation barriers still apply to closure.

A reversal appends the full original amount in its original currency, source and shift. The original remains visible in history. External compensation needs confirmation of a bookkeeping correction or verified reimbursement. Drawer compensation needs confirmation that all the original cash returned to the same original own open drawer; a new reversal after closure requires review and cannot change the closed count. A replay can still recover a successfully committed earlier record or reversal after that shift closed. Partial reversals, editing, deletion, automatic payout and provider-success claims are outside this workflow.

## Recovery and identity changes

`SupabaseExpenseRepository` prepares an immutable UUID and canonical parameters in the encrypted journal before dispatch and durably marks each attempt. A timeout, lost response, malformed success, wrong scope/actor/request or contradictory payment evidence leaves the request unresolved. A later replay denial cannot reject an earlier uncertain success. Only a definitive rollback on the first attempt releases the intent for a corrected new request.

Reversals also save the original expense proof under the private journal key `_nexapos_expense_original`. This nested proof is frozen and encrypted with the original request; it is removed from RPC parameters. Reopened-journal retries validate the saved amount, currency, source and shift against the original evidence, preserving the UUID and physical-transfer confirmation.

A pending expense record or reversal blocks a replacement expense until retry or review. A same-branch unresolved checkout or shift closure also blocks starting a new drawer payout. Retry cards tell the operator to keep the evidence and avoid repeating any physical payment or return. Account/business repository changes invalidate open record, reversal and history dialogs and discard the previous presentation results; durable requests remain with their original actor/business journal. Late responses cannot populate the replacement account's view.

History uses current server detail separately from immutable mutation responses. Dates are displayed as ISO UTC; selected inclusive end dates become the next UTC midnight for half-open queries. Category/date filters, paging, empty results, failures and pending-request controls adapt to 320px and desktop widths.

## Validation

After sourcing `tool/dev_env.sh`, run `flutter test test/expenses` and `flutter analyze lib/features/expenses test/expenses`.

The focused tests cover exact monetary and settings bounds, source/reference/manual-confirmation validation, multiline reason roundtrips, actual SQL context/original/reversal/current-detail fixtures, SDK RPC serialization, immutable journal preparation, malformed response retention, same-UUID conflicts, first rollback versus later denial, same-branch drawer blockers, encrypted physical SQLite close/reopen/retry, stale identity responses, and 320px/desktop empty/data/error/recovery/payment/return forms.

The isolated SQL harness separately verifies current role/branch/MFA, append-only originals and compensation, exact expected cash, stable replay, transaction rollback, full-reversal uniqueness, expense/reversal versus closure races and existing offline-grant barriers. See [PHASE6_CONTRACT.md](PHASE6_CONTRACT.md) and [VALIDATION.md](VALIDATION.md) for the final phase-wide outcomes and outstanding deployed/hardware acceptance gates. Local validation does not establish deployed PostgREST, real bank/provider payouts, or Windows/Android device behavior.
