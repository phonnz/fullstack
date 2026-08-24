# Test Failures Report

**Date:** 2026-06-25
**Total:** 219 tests, 72 failures, 2 skipped

| # | Test File | Failing Test | Error |
|---|-----------|--------------|-------|
| 1 | `test/fullstack_web/live/user_settings_live_test.exs` | update password form renders errors with invalid data (phx-submit) | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 2 | `test/fullstack_web/live/user_settings_live_test.exs` | Settings page redirects if user is not logged in | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 3 | `test/fullstack_web/live/user_settings_live_test.exs` | confirm email redirects if user is not logged in | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 4 | `test/fullstack_web/live/user_settings_live_test.exs` | Settings page renders settings page | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 5 | `test/fullstack_web/live/user_settings_live_test.exs` | update email form renders errors with invalid data (phx-change) | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 6 | `test/fullstack_web/live/user_settings_live_test.exs` | update email form updates the user email | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 7 | `test/fullstack_web/live/user_settings_live_test.exs` | confirm email updates the user email once | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 8 | `test/fullstack_web/live/user_settings_live_test.exs` | update email form renders errors with invalid data (phx-submit) | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 9 | `test/fullstack_web/live/user_settings_live_test.exs` | update password form renders errors with invalid data (phx-change) | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 10 | `test/fullstack_web/live/user_settings_live_test.exs` | confirm email does not update email with invalid token | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 11 | `test/fullstack_web/live/user_settings_live_test.exs` | update password form updates the user password | `MatchError` - `{:ok, _view, _html}` no match on `{:error, {:redirect, ...}}` |
| 12 | `test/fullstack/financial_test.exs` | transactions delete_transaction/1 deletes the transaction | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 13 | `test/fullstack/financial_test.exs` | transactions create_transaction/1 with valid data creates a transaction | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 14 | `test/fullstack/financial_test.exs` | transactions update_transaction/2 with valid data updates the transaction | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 15 | `test/fullstack/financial_test.exs` | transactions create_transaction/1 with invalid data returns error changeset | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 16 | `test/fullstack/financial_test.exs` | transactions update_transaction/2 with invalid data returns error changeset | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 17 | `test/fullstack/financial_test.exs` | transactions list_transactions/0 returns all transactions | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 18 | `test/fullstack/financial_test.exs` | transactions change_transaction/1 returns a transaction changeset | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 19 | `test/fullstack/financial_test.exs` | transactions get_transaction!/1 returns the transaction with given id | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` is undefined or private |
| 20 | `test/fullstack/urls_test.exs` | ulrs change_url/1 returns a url changeset | `FunctionClauseError` - no function clause matching |
| 21 | `test/fullstack/urls_test.exs` | ulrs get_url!/1 returns the url with given id | `FunctionClauseError` - no function clause matching |
| 22 | `test/fullstack/urls_test.exs` | ulrs list_ulrs/0 returns all ulrs | `FunctionClauseError` - no function clause matching |
| 23 | `test/fullstack/urls_test.exs` | ulrs create_url/1 with valid data creates a url | `FunctionClauseError` - no function clause matching |
| 24 | `test/fullstack/urls_test.exs` | ulrs update_url/2 with valid data updates the url | `FunctionClauseError` - no function clause matching |
| 25 | `test/fullstack/urls_test.exs` | ulrs delete_url/1 deletes the url | `FunctionClauseError` - no function clause matching |
| 26 | `test/fullstack/urls_test.exs` | ulrs update_url/2 with invalid data returns error changeset | `FunctionClauseError` - no function clause matching |
| 27 | `test/fullstack_web/live/url_live_test.exs` | Index saves new url | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 28 | `test/fullstack_web/live/url_live_test.exs` | Index lists all ulrs | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 29 | `test/fullstack_web/live/url_live_test.exs` | Index deletes url in listing | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 30 | `test/fullstack_web/live/url_live_test.exs` | Index updates url in listing | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 31 | `test/fullstack_web/live/url_live_test.exs` | Show displays url | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 32 | `test/fullstack_web/live/url_live_test.exs` | Show updates url within modal | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 33 | `test/fullstack_web/live/post_live_test.exs` | Index saves new post | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 34 | `test/fullstack_web/live/post_live_test.exs` | Index lists all posts | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 35 | `test/fullstack_web/live/post_live_test.exs` | Index deletes post in listing | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 36 | `test/fullstack_web/live/post_live_test.exs` | Index updates post in listing | `MatchError` - `{:error, {:live_redirect, ...}}` |
| 37 | `test/fullstack_web/live/post_live_test.exs` | Show displays post | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 38 | `test/fullstack_web/live/post_live_test.exs` | Show updates post within modal | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 39 | `test/fullstack_web/live/device_live_test.exs` | Index saves new device | `AssertionError` - render_click fails |
| 40 | `test/fullstack_web/live/device_live_test.exs` | Index lists all devices | `AssertionError` - HTML mismatch |
| 41 | `test/fullstack_web/live/device_live_test.exs` | Index deletes device in listing | `AssertionError` - render_click fails |
| 42 | `test/fullstack_web/live/device_live_test.exs` | Index updates device in listing | `AssertionError` - render_click fails |
| 43 | `test/fullstack_web/live/pos_live_test.exs` | Index saves new pos | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 44 | `test/fullstack_web/live/pos_live_test.exs` | Index lists all poss | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 45 | `test/fullstack_web/live/pos_live_test.exs` | Index deletes pos in listing | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 46 | `test/fullstack_web/live/pos_live_test.exs` | Index updates pos in listing | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 47 | `test/fullstack_web/live/pos_live_test.exs` | Show displays pos | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 48 | `test/fullstack_web/live/pos_live_test.exs` | Show updates pos within modal | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 49 | `test/fullstack_web/live/customer_live_test.exs` | Index saves new customer | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 50 | `test/fullstack_web/live/customer_live_test.exs` | Index lists all customers | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 51 | `test/fullstack_web/live/customer_live_test.exs` | Index deletes customer in listing | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 52 | `test/fullstack_web/live/customer_live_test.exs` | Index updates customer in listing | `MatchError` - `{:error, {:live_redirect, %{to: "/urls", ...}}}` |
| 53 | `test/fullstack_web/live/customer_live_test.exs` | Show displays customer | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 54 | `test/fullstack_web/live/customer_live_test.exs` | Show updates customer within modal | `FunctionClauseError` - `connect_from_static_token/2` (404) |
| 55 | `test/fullstack/counters_test.exs` | Basic counter operations increase and decrease identified counter values | `ArgumentError` - ETS key `"user_0"` not found in table |
| 56 | `test/fullstack_web/live/transaction_live_test.exs` | Index saves new transaction | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 57 | `test/fullstack_web/live/transaction_live_test.exs` | Index lists all transactions | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 58 | `test/fullstack_web/live/transaction_live_test.exs` | Index deletes transaction in listing | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 59 | `test/fullstack_web/live/transaction_live_test.exs` | Index updates transaction in listing | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 60 | `test/fullstack_web/live/transaction_live_test.exs` | Show displays transaction | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 61 | `test/fullstack_web/live/transaction_live_test.exs` | Show updates transaction within modal | `UndefinedFunctionError` - `Fullstack.Financial.create_transaction/1` undefined |
| 62 | `test/fullstack/blog_test.exs` | posts change_post/1 returns a post changeset | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 63 | `test/fullstack/blog_test.exs` | posts get_post!/1 returns the post with given id | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 64 | `test/fullstack/blog_test.exs` | posts list_posts/0 returns all posts | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 65 | `test/fullstack/blog_test.exs` | posts create_post/1 with valid data creates a post | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 66 | `test/fullstack/blog_test.exs` | posts update_post/2 with valid data updates the post | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 67 | `test/fullstack/blog_test.exs` | posts delete_post/1 deletes the post | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 68 | `test/fullstack/blog_test.exs` | posts update_post/2 with invalid data returns error changeset | `MatchError` - `author_id: {"can't be blank", [validation: :required]}` |
| 69 | `test/fullstack_web/channels/group_channel_test.exs` | shout broadcasts to group:lobby | `MatchError` - `{:error, %{reason: "join crashed"}}` |
| 70 | `test/fullstack_web/channels/group_channel_test.exs` | ping replies with status ok | `MatchError` - `{:error, %{reason: "join crashed"}}` |
| 71 | `test/fullstack_web/channels/group_channel_test.exs` | broadcasts are pushed to the client | `MatchError` - `{:error, %{reason: "join crashed"}}` |
| 72 | `test/fullstack_web/controllers/page_controller_test.exs` | GET / | `AssertionError` - expected "Peace of mind from prototype to production" in response |

## Summary by File

| Test File | Failures |
|-----------|----------|
| `test/fullstack_web/live/user_settings_live_test.exs` | 11 |
| `test/fullstack/financial_test.exs` | 8 |
| `test/fullstack/urls_test.exs` | 7 |
| `test/fullstack_web/live/url_live_test.exs` | 6 |
| `test/fullstack_web/live/post_live_test.exs` | 6 |
| `test/fullstack_web/live/device_live_test.exs` | 4 |
| `test/fullstack_web/live/pos_live_test.exs` | 6 |
| `test/fullstack_web/live/customer_live_test.exs` | 6 |
| `test/fullstack/counters_test.exs` | 1 |
| `test/fullstack_web/live/transaction_live_test.exs` | 6 |
| `test/fullstack/blog_test.exs` | 7 |
| `test/fullstack_web/channels/group_channel_test.exs` | 3 |
| `test/fullstack_web/controllers/page_controller_test.exs` | 1 |
| **Total** | **72** |
