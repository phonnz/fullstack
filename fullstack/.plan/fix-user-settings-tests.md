# Plan: Fix user_settings_live_test.exs (11 failures)

## Root Cause Analysis

**All 11 tests fail with the same error:**
```
MatchError - {:ok, _view, _html} no match on {:error, {:redirect, ...}}
```

### Primary Issue: Route Path Mismatch

The settings routes are defined under the `/admin` scope in `lib/fullstack_web/router.ex:97-128`:

```elixir
scope "/admin", FullstackWeb do
  pipe_through [:browser, :require_authenticated_user]
  live_session :require_authenticated_user,
    on_mount: [{FullstackWeb.UserAuth, :ensure_authenticated}] do
    live "/users/settings", UserSettingsLive, :edit
    live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
  end
end
```

**Actual routes:** `/admin/users/settings` and `/admin/users/settings/confirm_email/:token`

**Tests use:** `~p"/users/settings"` → resolves to `/users/settings` (non-existent)

When a non-existent path is requested, Phoenix returns a redirect (404 or to home), producing `{:error, {:redirect, ...}}` instead of the expected `{:ok, lv, html}`.

### Secondary Issue: Authentication in LiveView Mount

Even with correct paths, the `on_mount: [{FullstackWeb.UserAuth, :ensure_authenticated}]` hook checks the session for `user_token`. The test helper `log_in_user/2` in `ConnCase` properly sets this in the Plug session, but the LiveView mount uses the session from the WebSocket connection, which may not carry the token correctly if the conn setup is incomplete.

---

## Solution

**Fix the test paths** to match the actual router configuration. The routes live under `/admin`, so tests must use `/admin/users/settings`.

### Files to Modify

1. **`test/fullstack_web/live/user_settings_live_test.exs`** — Update all `~p` paths

### Changes

| Line(s) | Current Path | New Path |
|---------|-------------|----------|
| 13 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 22 | `~p"/users/log_in"` | `~p"/users/log_in"` (no change — this is correct) |
| 38 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 53 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 69 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 95 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 111 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 122 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 141 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 175 | `~p"/users/settings/confirm_email/#{token}"` | `~p"/admin/users/settings/confirm_email/#{token}"` |
| 178 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 185 | `~p"/users/settings/confirm_email/#{token}"` | `~p"/admin/users/settings/confirm_email/#{token}"` |
| 187 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 193 | `~p"/users/settings/confirm_email/oops"` | `~p"/admin/users/settings/confirm_email/oops"` |
| 195 | `~p"/users/settings"` | `~p"/admin/users/settings"` |
| 203 | `~p"/users/settings/confirm_email/#{token}"` | `~p"/admin/users/settings/confirm_email/#{token}"` |

### Test-by-Test Expected Outcome

| # | Test | Status After Fix |
|---|------|-----------------|
| 1 | Settings page renders settings page | ✅ Authenticated user accesses `/admin/users/settings` → renders |
| 2 | Settings page redirects if user is not logged in | ✅ Unauthenticated → `on_mount` redirects to `/users/log_in` |
| 3 | update email form updates the user email | ✅ Form submits correctly |
| 4 | update email form renders errors (phx-change) | ✅ Validation errors render |
| 5 | update email form renders errors (phx-submit) | ✅ Validation errors render |
| 6 | update password form updates the user password | ✅ Password update works |
| 7 | update password form renders errors (phx-change) | ✅ Validation errors render |
| 8 | update password form renders errors (phx-submit) | ✅ Validation errors render |
| 9 | confirm email updates the user email once | ✅ Token confirmation works |
| 10 | confirm email does not update email with invalid token | ✅ Invalid token handling |
| 11 | confirm email redirects if user is not logged in | ✅ Unauthenticated redirect |

---

## Verification

```bash
mix test test/fullstack_web/live/user_settings_live_test.exs
```

Expected: 11 tests, 0 failures.

---

## Risk Assessment

- **Low risk**: Only test paths change, no production code modified
- **No side effects**: Other test files are independent
- **If secondary auth issues appear**: Check that `ConnCase.log_in_user/2` properly sets `user_token` in session that LiveView can access via `on_mount`
