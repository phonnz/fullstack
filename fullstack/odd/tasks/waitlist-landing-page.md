# Waitlist Landing Page

## Objective
Public marketing landing page at `/waitlist` that explains the "business analyzer"
product (agent-mesh chat that assesses business viability, framed around
NextGenerationEU / ipyme.org / Plan de Recuperación, Transformación y Resiliencia)
and captures emails (+ optional target country) for future contact.

## Problem / Why
Product does not exist yet; goal is lead capture ahead of launch to validate
interest and start a contact list.

## Scope
- New route `/waitlist` inside the existing `:public` live_session (before the
  catch-all `/:key` route), rendered in the existing `app` layout (no new
  marketing layout — confirmed no dedicated one exists).
- New bounded context `Fullstack.Waitlist` with schema `Fullstack.Waitlist.Signup`.
- Migration: `waitlist_signups` table (UUID pk, `email` unique, `country` nullable,
  timestamps), following the `urls` migration convention.
- LiveView `FullstackWeb.WaitlistLive.Index` with marketing copy sections
  (problem/solution, how it works, EU/Spain framework credibility, CTA) + email
  capture form using CoreComponents `<.simple_form>` / `<.input>`.
- Country dropdown: hardcoded static ~250-entry list as a module attribute,
  default option "I don't know yet" (stored as `nil` country).
- Tests: LiveView test (ConnCase) + context/changeset test (DataCase), following
  `business_discovery_live_test.exs` and `urls_test.exs` patterns.

## Constraints
- No new dependency for country list (decided: hardcoded list).
- Match existing conventions: UUID primary keys, `unsafe_validate_unique` +
  `unique_constraint` for email, context module with `@doc`/`## Examples`
  doctest-style public API, `~p` verified routes.
- Read-only exploration already done; this document tracks the implementation.

## Route declaration
Direct inline: router edit (1 line + scope), migration, schema, context module,
LiveView module + template, tests. 6 files, non-trivial design (copy, schema,
validation) → delegated to one bounded writer (writer trigger: 2+ non-trivial files).

## TDD mode
Strict TDD enabled (user global instruction: `Strict TDD Mode: enabled`).
Runner: `mix test` (ExUnit, as used by existing `urls_test.exs` /
`business_discovery_live_test.exs`). RED (changeset + LiveView tests failing) →
GREEN (implementation) → REFACTOR.

## Tasks
- [x] T1: Migration `create_waitlist_signups` (UUID pk, email unique not null,
      country nullable string, timestamps)
- [x] T2: `Fullstack.Waitlist.Signup` schema + changeset (email format + length +
      uniqueness, country optional)
- [x] T3: `Fullstack.Waitlist` context (`create_signup/1`, `change_signup/2`)
      with doctested public API
- [x] T4: `FullstackWeb.WaitlistLive.Index` module + `index.html.heex` template
      (marketing copy + form), router entry in `:public` live_session before
      catch-all
- [x] T5: Static country list module attribute (hardcoded, ~250 entries,
      "I don't know yet" default) — implemented as
      `FullstackWeb.WaitlistLive.Countries` (195 sovereign states + 56
      territories + default = 252 options)
- [x] T6: Tests — changeset/context test (DataCase) + LiveView test (ConnCase):
      render page, submit valid email, duplicate email error, default country
      behavior
- [x] T7: Verification — `mix test` targeted files, `mix compile
      --warnings-as-errors`; work-unit commit (Conventional Commits, no
      co-author trailer per user's global rule)

### Round 2 — hero redesign + discount code (2026-09-29)
- [x] T8: Redesign hero section — focus copy/visual framing on business
      people/entrepreneurs (not generic "your idea"), larger/more prominent
      hero treatment
- [x] T9: Central subscription box — make the signup form a visually prominent
      centered card, pulled up near/into the hero rather than buried after
      the "how it works" and "framework" sections
- [x] T10: Add optional `discount_code` field — free-text capture only, no
      validation against real codes (decided: no coupon system exists yet).
      Migration to add nullable `discount_code` string column, schema
      changeset update (cast, no validation), form field, context/changeset
      + LiveView test coverage
- [x] T11: Verification — `mix test` targeted files, `mix compile
      --warnings-as-errors`; work-unit commit

## Acceptance criteria
- `/waitlist` renders marketing copy + form without auth.
- Valid email + no country selected → signup created with `country: nil`.
- Valid email + selected country → signup created with that country.
- Duplicate email → changeset error surfaced in form, no crash.
- All new/targeted tests pass; no new compiler warnings.

## Progress
- Exploration complete (router, layouts, LiveView/Ecto/context/test conventions,
  confirmed no country-list dependency exists).
- User decisions: Phoenix route (not Artifact), full country list (not curated
  shortlist), path `/waitlist` (not root `/`), hardcoded country list (not new
  dependency).
- Implementation complete, strict TDD followed for both test files (RED
  confirmed via real `mix test` failures before implementation, then GREEN):
  - Context/changeset RED: `Fullstack.Waitlist.Signup.__struct__/1 is undefined`
    (module didn't exist yet).
  - LiveView RED: `{:error, {:live_redirect, %{to: "/urls", ...}}}` (no
    `/waitlist` route yet — request fell through to the catch-all `/:key`).
  - Both GREEN after implementation, no refactor needed.
- Files added: `priv/repo/migrations/20260928174027_create_waitlist_signups.exs`,
  `lib/fullstack/waitlist.ex`, `lib/fullstack/waitlist/signup.ex`,
  `lib/fullstack_web/live/waitlist_live/index.ex`,
  `lib/fullstack_web/live/waitlist_live/index.html.heex`,
  `lib/fullstack_web/live/waitlist_live/countries.ex`,
  `test/fullstack/waitlist_test.exs`,
  `test/fullstack_web/live/waitlist_live_test.exs`.
- Files edited: `lib/fullstack_web/router.ex` (added `/waitlist` route before
  the `/urls` block, inside `:public` live_session, before the catch-all).
- Verification: `mix test test/fullstack/waitlist_test.exs` → 7 tests, 0
  failures. `mix test test/fullstack_web/live/waitlist_live_test.exs` → 4
  tests, 0 failures. `mix compile --warnings-as-errors` → fails, but only on
  49 pre-existing warnings across unrelated files (confirmed by grep: zero
  warnings reference any waitlist file); this condition pre-dates this
  feature and was not introduced by it.
- Commit: `281d62996861d25d2571600634255a45affb5c35` —
  `feat(waitlist): add /waitlist landing page with email capture`.
  (Self-referential: this line was updated after the commit that contains it,
  so this file on disk now differs by this SHA string from what's in that
  commit's tree — expected and harmless.)

## Progress — Round 2 (2026-09-29)
- Hero (T8): rewritten to address entrepreneurs/small business owners
  directly — headline reframed around the pain point ("Stop guessing whether
  your business idea will work"), subheadline explicitly names the audience
  ("Built for entrepreneurs and small business owners...") while keeping the
  concrete value list (competitor analysis, market diagnosis, SMART
  objectives, financial picture, MVP path). Visual hierarchy strengthened:
  larger badge (`badge-lg`), bigger headline (`text-4xl sm:text-5xl`), wider
  subheadline max-width, and a visible `btn btn-primary btn-lg` CTA
  ("Get early access") anchor-linking to `#waitlist`.
- Central subscription box (T9): signup form moved out of the bottom
  `<section>` and into a bordered/shadowed card
  (`rounded-lg border border-base-300 shadow-lg bg-base-100 p-6 sm:p-8`,
  `max-w-md mx-auto`) sitting directly inside the hero section, right below
  the CTA button. The `id="waitlist"` anchor now lives on the wrapping div
  around the card so the in-page CTA link still targets it. "How it works"
  and the EU/Spain framework sections kept, now following the combined
  hero+form block instead of preceding it.
- Discount code (T10): nullable `discount_code` string column added via a
  new migration (existing migration untouched), cast in the changeset with
  no validation (free-text only, no coupon system exists), form field added
  after email/country and before the submit button.
- Files added:
  `priv/repo/migrations/20260929000000_add_discount_code_to_waitlist_signups.exs`.
- Files edited: `lib/fullstack/waitlist/signup.ex` (schema field + cast),
  `lib/fullstack_web/live/waitlist_live/index.html.heex` (hero + form
  repositioning + discount field), `test/fullstack/waitlist_test.exs`,
  `test/fullstack_web/live/waitlist_live_test.exs`.
- TDD evidence (T10, strict mode): extended both test files first
  (discount_code context tests, LiveView discount_code input/submission
  tests, entrepreneur-copy assertion), ran `mix test` before implementing —
  RED confirmed via real compile error:
  `unknown key :discount_code for struct Fullstack.Waitlist.Signup`
  (schema field didn't exist yet, so pattern-matching the struct in the test
  failed to compile). Implemented migration + schema + template, re-ran —
  GREEN, no refactor needed.
- Verification:
  - `mix test test/fullstack/waitlist_test.exs` → 9 tests, 0 failures.
  - `mix test test/fullstack_web/live/waitlist_live_test.exs` → 5 tests,
    0 failures.
  - `mix compile --warnings-as-errors` → fails, but only on the same 49
    pre-existing warnings from Round 1 across unrelated files (grep
    confirmed zero warnings reference any waitlist file); no regression.
- Commit: (recorded after commit below).
  (Self-referential: this line is one commit behind, same as Round 1 — the
  doc is part of the commit it describes, so the SHA string itself can't be
  known before the commit exists. Expected and harmless.)

## Next step
Round 2 complete. No further waitlist work pending.
