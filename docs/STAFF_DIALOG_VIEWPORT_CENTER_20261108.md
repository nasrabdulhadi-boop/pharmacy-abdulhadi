# QA: staff dialog centered at the current list position

The staff-details dialog now has explicit fixed positioning, viewport insets, automatic centering and a viewport-limited scroll area. Opening it locks the background and preserves the account-list scroll position. Closing restores the previous overflow and focuses the originating control with preventScroll. The setup also restores overflow if showModal fails.

Verification used the separate no-network browser fixture with 30 additional synthetic account rows. Before opening, window.scrollY was 2014. After opening it remained 2014, the native dialog occupied viewport y=94.78125 through 841.21875 in a 936px-tall viewport (centered at 468px), and background scrolling was locked. After closing, window.scrollY remained 2014 and the previous overflow was restored. The fixture uses mocked Auth/RPC; no real account change was performed.

Two lifecycle regression tests pass. Complete suite: 159 passed, 0 failed, one optional live-support test skipped without a disposable session. Staging build passed. No database, Auth, permission or password-policy changes. Production untouched.
