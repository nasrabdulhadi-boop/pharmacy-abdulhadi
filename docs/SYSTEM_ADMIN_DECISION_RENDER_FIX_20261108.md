# QA correction: populated manager decision list

The language rollout left `getSystemLanguage` unbound in `QaOperationsWorkbench.jsx`. The call occurs only for a request with `decided_at`, so the empty-table browser fixture and a successful build did not exercise it. Entering Overview with prior decisions could throw a ReferenceError and trigger the root error boundary.

Imported the existing shared helper; no Auth, permission, database or accounting changes. Translated the previously unexercised approved/rejected status labels. Extended the no-network local fixture with approved/rejected synthetic rows and added a binding check across all active JSX modules to catch locale calls missing imports. The check detects the previous commit's missing binding.

Browser verification used synthetic approved/rejected requests: dates render in Arabic and English without an application error. Existing QA code and the new regression check pass; one live support test is skipped without a disposable session. Staging build passes. This is local mocked UI verification, not a claim of a signed-in deployed browser session. Production remains untouched.
