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
Round 3 complete.

## Progress — Round 3 (2026-09-29)
Ported the finalized Artifact design
(/tmp/claude-1000/-home-phonnz-Code-phx-fullstack-fullstack/70c15917-678c-4145-896e-a0f9c47a633c/scratchpad/waitlist-design/index.html)
into `lib/fullstack_web/live/waitlist_live/index.html.heex`, keeping the real
LiveView form wiring intact.

**Scoping mechanism (T12):** a `.wl` wrapper class around the whole page
root, with the mockup's `:root` custom properties (`--ink`, `--paper`,
`--forest`, etc.) redeclared as plain properties on `.wl` itself instead of
on `:root` (so they never leak to other pages that share the same DOM
document/root). Every ported selector is written as `.wl .wl-<name>`
(prefixed, not just nested) to avoid any chance of an unprefixed class like
`.hero` or `.signup` colliding with something already in the app. Dark mode:
the app's root layout already toggles `data-theme` on `<html>` via inline
script (confirmed in `root.html.heex`) — since `.wl` sits *inside* `<html>`,
not on it, the mockup's own `:root[data-theme="dark"]` selector doesn't
apply as-is. Used the ancestor-combinator form instead:
`html[data-theme="dark"] .wl { --ink: ...; }` (and same pattern for the few
component-level dark overrides the mockup had inline, e.g. `.signup`'s dark
background). This reads the *existing* global toggle correctly without this
page adding, reading, or fighting any theme state of its own — confirmed by
reasoning through the selectors (T17) that nothing under `.wl` or prefixed
`wl-*` exists anywhere else in the codebase (grep confirmed zero matches
outside this file).

The CSS lives in a `<style>` block at the top of `index.html.heex` itself
(single page, no new asset file needed) rather than `assets/css/app.css`,
per the constraint against global stylesheet changes.

One extra scoping fix needed beyond the mockup's own CSS: `<.simple_form>`
(CoreComponents) wraps its content in a `<div class="mt-10 space-y-8
bg-base-100">` — daisyUI's `bg-base-100` utility would have painted a light
box inside the new dark signup card, so an explicit
`.wl .wl-signup form > div.bg-base-100 { background: transparent; }`
override was added. Similarly, `<.input>`/`<.label>`/`<.button>` from
CoreComponents hard-code daisyUI classes (`input input-bordered`, `select
select-bordered`, `btn btn-primary`, `text-base-content`, etc.) with no
`class`-override attribute — restyling them without touching the shared
component file meant writing higher-specificity `.wl`-scoped selectors
targeting those exact daisyUI class names (e.g. `.wl .wl-field .input`,
`.wl .wl-submit-btn.btn`), which reliably win via CSS specificity
(3 classes vs. 1) regardless of source order.

**Font-link fallback (T13):** needed. Checked `mix.exs`/`mix.lock` —
`phoenix_live_view 1.2.7`. This version has no per-LiveView `<head>`
injection mechanism, and `/waitlist` shares the single global root layout
(`plug :put_root_layout` in the `:browser` pipeline) and the same
`live_session :public` block as `/`, `/business-discovery`, and `/urls` —
there is no route-scoped way to swap in a different root layout just for
this page without restructuring the router's pipeline/scope, which would be
disproportionate for a font stylesheet load. Used the documented fallback:
added the Google Fonts `<link>` unconditionally to
`lib/fullstack_web/components/layouts/root.html.heex` (14 lines added, no
deletions, existing `data-theme` toggle script untouched). This is a
stylesheet load only — no new CSS rules, no global tokens — so it does not
violate the "no new global app theme" constraint; it is noted here as the
deviation the task anticipated.

**Copy/structure preserved exactly as approved** in the Artifact: hero
headline/subheadline, eyebrow, mocked report card, proof-row (including the
"Agentic specialist mesh" full-width item), signup section copy and layout
(email+submit primary row, country+discount-code secondary row, fine
print), the four "how it works" steps, and the EU/Spain framework strip —
all ported verbatim from the mockup's HTML text nodes into the `.heex`
structure, with the mockup's static `<input>`/`<select>`/`<button>`/`<form>`
replaced by `<.simple_form for={@form} ...>`, `<.input field={@form[...]}
...>`, `<.button>`, and the `@signed_up` conditional. `@country_options`
still comes from `FullstackWeb.WaitlistLive.Countries` (not the mockup's
6-option placeholder list).

**Test changes (T18):** one assertion updated in
`test/fullstack_web/live/waitlist_live_test.exs` — the old copy check
`assert html =~ "entrepreneur"` no longer matches (the approved Artifact
copy doesn't use that word; it says "founders"/"founding cohort" instead),
so it was replaced with `assert html =~ "founding cohort"`. No coverage was
removed: still asserts page renders, form exists, discount_code input
exists, and (via the other 4 tests, unchanged) validate/submit/duplicate-
email/discount-code/country behavior all still pass.
`test/fullstack/waitlist_test.exs` (context/changeset tests) needed no
changes — confirmed via `git status` showing no diff on that file.

**Verification:**
- `mix test test/fullstack_web/live/waitlist_live_test.exs` → 5 tests,
  0 failures.
- `mix test test/fullstack/waitlist_test.exs` → 9 tests, 0 failures.
- Both together: 14 tests, 0 failures.
- `mix compile --warnings-as-errors` → fails (exit 1), but exactly 49
  warnings, same count as Round 1/2, all in unrelated pre-existing files;
  `grep -i waitlist` over the full compile output (stdout+stderr combined)
  returned zero matches — no new warning introduced by this change.
- Manual scoping verification (T17): grepped the codebase for `wl-` /
  `class="wl` outside this one file — zero matches, so no other route's
  markup or CSS can reference these selectors. `assets/css/app.css` has a
  0-line diff (untouched). `root.html.heex` diff is +14/-0, additive only,
  confined to the fallback font `<link>` — the existing `data-theme`
  resolution script above it is unmodified.

Files edited: `lib/fullstack_web/live/waitlist_live/index.html.heex`
(full rewrite: scoped `<style>` block + ported markup + real form
bindings), `lib/fullstack_web/components/layouts/root.html.heex` (fallback
font `<link>` only), `test/fullstack_web/live/waitlist_live_test.exs` (one
copy assertion updated).

Commit: (recorded after commit below).
(Self-referential: same caveat as Rounds 1 and 2 — this line is written
before the commit that contains it exists, so the SHA can't be embedded in
the tree it describes. Expected and harmless.)

### Round 3 — port Artifact design to LiveView (2026-09-29)
User asked for a "better UI proposal" via Claude Design/Artifact iteration.
Built a full visual redesign as a standalone HTML Artifact
(https://claude.ai/code/artifact/09b1a72a-54ef-4a7d-a983-23db414bfac2,
"Viability Report"), iterated through several rounds of viewer comments
(step-box restyle, signup form layout, proof-row full-width + copy change).
Now porting that finalized design into the real `lib/fullstack_web/live/
waitlist_live/index.html.heex`.

User decision: new palette/typography (Fraunces + Inter + JetBrains Mono;
forest green/paper/terracotta tokens) is scoped to `/waitlist` only, not
adopted as a new global app theme — rest of the app keeps its current
daisyUI look. This means: new CSS must not leak outside the waitlist page,
new Google Fonts `<link>` loaded only on this page (not in root.html.heex),
and the page's `data-theme` dark-mode handling must not collide with the
app's existing `<html data-theme>` global light/dark toggle (root layout
already sets `data-theme` on `<html>` site-wide via inline script —
confirmed by reading lib/fullstack_web/components/layouts/root.html.heex).

Design reference (full source of truth, already reviewed against the
subject and iterated with the user):
/tmp/claude-1000/-home-phonnz-Code-phx-fullstack-fullstack/70c15917-678c-4145-896e-a0f9c47a633c/scratchpad/waitlist-design/index.html

- [x] T12: Scope new CSS to `/waitlist` only (wrapping class on the page
      root, e.g. `.wl-design`, all new selectors nested/prefixed under it;
      do not touch app.css global tokens or root layout's `data-theme`
      logic)
- [x] T13: Load Fraunces + Inter + JetBrains Mono via a Google Fonts
      `<link>` placed only in the waitlist page's own template/head
      injection (not root.html.heex) — confirm the right mechanism in this
      app (e.g. a per-LiveView head hook, or a scoped `<link>` if templates
      support it) since root.html.heex currently owns the single global
      `<head>`
- [x] T14: Port hero (headline, subheadline, eyebrow, mocked report card,
      full-width proof-row with "Agentic specialist mesh" label) into
      index.html.heex, preserving real LiveView bindings (no changes to
      copy content already approved in the Artifact)
- [x] T15: Port signup form section (title/intro full width, email + submit
      emphasized row, country + discount code secondary row, fine print)
      — MUST keep real `<.simple_form>`/`@form`/`phx-change`/`phx-submit`
      bindings; only replace visual structure/classes, not the LiveView
      form wiring or field names
- [x] T16: Port "How it works" steps (green boxes, centered icon + title +
      description) and the EU/Spain framework strip
- [x] T17: Verify in both light and dark mode (this app's `data-theme`
      toggle) that the ported page reads correctly and no styles leak onto
      other routes (spot-check e.g. `/` or `/business-discovery` still
      render with the normal daisyUI look after this change)
- [x] T18: Tests — extend/adjust existing waitlist LiveView test only if
      selectors/copy the tests assert on changed structurally; run full
      waitlist test suite + `mix compile --warnings-as-errors`
- [x] T19: Work-unit commit (Conventional Commits, no co-author trailer)
