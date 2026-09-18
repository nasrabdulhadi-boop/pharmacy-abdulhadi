# v4.2.3 — Cart Button Fix

Fixed the customer "إضافة للطلب" button. The previous build had an `onClickCapture` handler that called `preventDefault()` and `stopPropagation()`, which prevented the actual `onClick` handler from running.

No Supabase SQL changes are required.
