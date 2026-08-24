# Plan — Improve `ChatLive` UI with DaisyUI + Tailwind + existing components

Target: `live "/chat", ChatLive` → `lib/fullstack_web/live/chat/chat_live.ex`
Scope: this LiveView only. **No new components.** Restyle inline markup, document gaps in Storybook.

---

## 0. Verified facts (read before starting)

- **DaisyUI is NOT installed.** Verified in:
  - `assets/css/app.css` → plain Tailwind v3 `@import "tailwindcss/base|components|utilities"`, no `@plugin "daisyui"`.
  - `assets/tailwind.config.js` → only `@tailwindcss/forms`.
  - `assets/package.json` → no `daisyui` dep.
- **Tailwind is standalone CLI v3.3.2** (hex `tailwind` package, `config/config.exs:51`), NOT an npm/esbuild Tailwind build. JS is built by esbuild; CSS by the standalone Tailwind binary using `--config=tailwind.config.js`.
  - Consequence: **use DaisyUI v4** (v5 requires Tailwind v4). The standalone v3 binary loads CommonJS plugins from `assets/node_modules` via `require()` in the config.
- Storybook = PhoenixStorybook, content in `storybook/`, backend `lib/fullstack_web/storybook.ex`, served at `/storybook` in dev routes (`router.ex` mounts `live_storybook("/storybook", ...)`; `/dev/storybook` would be wrong). Story format: `*.story.exs` with `%Variation{}` / `%VariationGroup{}`.
- Existing components available (DO NOT add new ones):
  - Core (`core_components.ex`): `header`, `simple_form`, `input`, `button`, `flash`, `icon`, etc.
  - Custom (`custom_components.ex`): `subheader`, `custom_button`.
  - Chat-local render helper already present: `FullstackWeb.ChatLive.message_line/1` (3 function clauses). This is an **existing function**, so styling it and writing a Storybook story for it does **not** count as adding a new component.
- Core form caveat: current `<.simple_form>` and `<.input>` are not neutral DaisyUI wrappers. `simple_form/1` hardcodes `mt-10 space-y-8 bg-white`, and `input/1` hardcodes zinc/rose Tailwind classes instead of accepting a clean DaisyUI `input input-bordered` override. For this screen, prefer a local `<.form>` with a native `<input class="input input-bordered ...">` and optional native DaisyUI submit button. This is still **no new component** and is a better fit than fighting shared core component defaults.

### Current ChatLive markup problems (`chat_live.ex:28-75`, `:125-156`)
- Inline `style="..."` strings mixed with classes (`:38`, `:43`); one invalid declaration `height:500px` inside `class` (`:43`).
- Hardcoded colors `#3D9970` bg / `#001f3f` text → poor contrast, not themeable.
- Inconsistent bubble widths: `max-w-40`, `max-w-96`, `max-w-2/3`.
- No semantic chat structure, no ARIA live region for typing indicator.
- Layout uses fixed `h-2/3` + `fixed bottom-0` instead of a flex column shell.

---

## Phase 0 — Install DaisyUI v4 (prerequisite, chosen: "add DaisyUI first")

1. Install into the assets workspace (already has `package.json` + `node_modules`):
   ```bash
   cd assets && npm install -D daisyui@^4
   ```
2. Register plugin + pick a small theme set in `assets/tailwind.config.js`:
   ```js
   content: [
     // existing lib/js globs...
     "../storybook/**/*.*exs",
   ],
   plugins: [
     require("@tailwindcss/forms"),
     require("daisyui"),
     // ...existing heroicons plugin stays
   ],
   daisyui: { themes: ["light", "dark"], logs: false },
   ```
   Add the Storybook content glob because the new stories may contain DaisyUI-only examples; without it, Tailwind's standalone v3 build can purge classes used only under `storybook/`.
3. No `app.css` change required for v4 (plugin injects into the components layer). Keep existing `@import "tailwindcss/*"` lines.
4. Rebuild + verify:
   ```bash
   mix assets.build
   ```
   Sanity check after restyling: confirm generated CSS includes DaisyUI selectors/classes used by the page (or visually confirm `/chat`). Do **not** add a temporary button to app code; the final ChatLive changes are enough to prove the plugin works.

**Risk:** if the standalone binary fails to resolve `daisyui` from `node_modules`, confirm `cd: assets` (it is, `config.exs:58`) and that `npm install` populated `assets/node_modules/daisyui`. No switch to Tailwind v4 in this plan.

---

## Phase 1 — Restyle `ChatLive.render/1` and `message_line/1`

Constraint: use DaisyUI classes, raw Tailwind utilities, existing components where they fit, and native HEEx/HTML where shared components would fight the desired UI. Edit markup in place; do not extract new functions/components.

### 1.1 Page shell (`chat_live.ex:30-54`)
- Replace `h-screen flex-1` + `h-2/3` + inline-styled scroll div with a DaisyUI/Tailwind flex column:
  - Outer: `flex flex-col h-screen bg-base-200`.
  - Header region: keep `<.header>`; restyle the identifier `<span>` from `bg-slate-200 p-2 rounded-lg` → `badge badge-neutral` (or `badge badge-lg`).
  - Messages region: `flex-1 overflow-y-auto p-4 space-y-2` (delete the inline `style=` strings and the invalid `height:500px` class). Keep `phx-update="append"` and `id="messages"`. Use normal document order; do **not** add `flex-col-reverse` because the current reverse flex is on a wrapper with only one child, so it does not actually reverse messages, and combining reverse order with `phx-update="append"` would make future ordering harder to reason about. Auto-scroll can be a later JS hook if needed.
- Remove hardcoded `#3D9970`/`#001f3f`; rely on `bg-base-100`/`text-base-content`.

### 1.2 Message bubbles — `message_line/1` (3 clauses, `:125-156`)
Map all three to DaisyUI `chat` component (themeable, accessible, consistent widths):

| Clause | Today | DaisyUI target |
|---|---|---|
| own (`sender == me`, `:125`) | `justify-end ... bg-indigo-500 max-w-40` | `<div class="chat chat-end">` + `<div class="chat-bubble chat-bubble-primary">` |
| system (`from: "Fullstack"`, `:135`) | `bg-white max-w-96` | `<div class="chat chat-start">` + `<div class="chat-bubble chat-bubble-info">` (or `chat-bubble-neutral`) |
| other user (`:145`) | `bg-slate-400` label + `bg-white` | `<div class="chat chat-start">` + `<div class="chat-header">{from}</div>` + `<div class="chat-bubble">{text}</div>` |

- Drop the manual `justify-end` toggle in the wrapper `:48` since `chat-start`/`chat-end` handle alignment; keep the `:for`/`id` wrapper but simplify its class to just the row container if still needed.
- Unifies widths (no more `max-w-40/96/2-3`) — `chat-bubble` self-sizes.

### 1.3 Input + status footer (`chat_live.ex:55-72`)
- Replace `fixed bottom-0 ... p-4` footer with a non-overlapping flex child: `shrink-0 border-t border-base-300 bg-base-100 p-4`.
- Presence line (`:56`): wrap counts in `<div class="stats stats-horizontal">` or simpler `text-sm text-base-content/60`. Keep values `@users_count`, `@connections`.
- Typing indicator (`:59`): make it an ARIA live region and use DaisyUI loading dots:
  `<p :if={@typing_users != ""} role="status" aria-live="polite" class="text-sm text-base-content/60"><span class="loading loading-dots loading-xs"></span> {@typing_users} typing...</p>`
- Form: replace `<.simple_form>` + `<.input>` with a local `<.form for={@form} phx-change="change" phx-submit="save" class="mt-3 flex gap-2">` and a native input:
  - `<input type="text" name={@form[:message].name} id={@form[:message].id} value={@text_value} class="input input-bordered w-full" ... />`
  - Optional submit affordance: `<button type="submit" class="btn btn-primary">Send</button>`.
  - Rationale: this is the narrowest way to get a DaisyUI input/footer without changing shared `core_components.ex`. It also avoids the current `simple_form/1` `mt-10 bg-white` wrapper, which would fight the DaisyUI footer surface. Preserve `phx-mounted={JS.focus()}`, `placeholder`, `autocomplete`, and the current event names/params (`%{"form" => %{"message" => value}}`) by keeping the same form field name.

### 1.4 Files touched
- `lib/fullstack_web/live/chat/chat_live.ex` only (render + 3 `message_line` clauses).
- `assets/tailwind.config.js`, `assets/package.json`, `assets/package-lock.json` (Phase 0).
- `storybook/chat/index.exs`, `storybook/chat/message_line.story.exs`, `storybook/chat/chat_screen.story.exs` (Phase 2).
- No edits to `core_components.ex` / `custom_components.ex`.

---

## Phase 2 — Storybook documentation for what this LiveView is missing

Goal: document chat UI pieces that currently have **no** Storybook coverage, without creating new components.

1. **`storybook/chat/` folder** (new `index.exs`, mirror `custom_components/index.exs` pattern; icon e.g. `:chat-bubble-left-right`).

2. **`storybook/chat/message_line.story.exs`** — `:component` story pointing at the existing function:
   ```elixir
   def function, do: &FullstackWeb.ChatLive.message_line/1
   ```
   Variations (one per clause): `own`, `system`, `other_user`, plus a `VariationGroup` showing all three stacked. Each variation passes `attributes: %{message: %{...}, tmp_id: "..."}`. This documents the bubble variants with zero new components.

3. **`storybook/chat/chat_screen.story.exs`** — a `:page` (markdown) story documenting the parts that are pure inline markup (not standalone components): page shell layout, presence/stats line, typing indicator pattern, input footer. Captures intended DaisyUI classes + accessibility notes so the screen is documented even though we are not extracting components yet. Flag these as "extraction candidates" for a future change.

4. Verify stories render at `/storybook` under the new "Chat" folder.

> Note on tension: "document in Storybook" vs "no new components". Resolved by (a) storying the **already-existing** `message_line/1`, and (b) using a Storybook **page** doc for inline-only elements. No new component modules are introduced.

---

## DaisyUI class cheat-sheet for this screen

- Bubbles: `chat`, `chat-start`, `chat-end`, `chat-bubble`, `chat-bubble-primary|info|neutral`, `chat-header`.
- Surfaces: `bg-base-100`, `bg-base-200`, `text-base-content`, `border-base-300`.
- Badge (identifier): `badge badge-neutral badge-lg`.
- Typing: `loading loading-dots loading-xs`.
- Stats (optional): `stats stats-horizontal`.
- Buttons/inputs: `btn btn-primary`, `input input-bordered`.

---

## Risks & gotchas

- Standalone Tailwind v3 + DaisyUI v4 plugin resolution depends on `assets/node_modules/daisyui` existing and `require("daisyui")` in config. Run `mix assets.build` and confirm before restyling.
- Do not edit shared `core_components.ex` just to make this screen look like DaisyUI. Use a local native input in `ChatLive` instead, because this keeps the change scoped and avoids surprising other screens.
- `phx-update="append"` + `temporary_assigns: [messages: []]` (`:23`) must be preserved — purely a styling change, do not touch message-stream logic.
- DaisyUI theme defaults to `light`; ensure contrast acceptable, otherwise set explicit `data-theme` on the root or `<html>`.

---

## Acceptance criteria

- [ ] DaisyUI v4 installed, `mix assets.build` succeeds, DaisyUI classes render.
- [ ] ChatLive has zero inline `style="..."` and no hardcoded hex colors.
- [ ] All 3 message variants use `chat`/`chat-bubble`; consistent sizing; alignment via `chat-start`/`chat-end`.
- [ ] Footer no longer `fixed`-overlapping; typing indicator is an ARIA live region.
- [ ] No new component modules; `core_components.ex` / `custom_components.ex` unchanged.
- [ ] Storybook: `message_line` component story (3 variants) + chat-screen page doc render at `/storybook`.
- [ ] `mix format` clean.

## Out of scope (future changes)

- Extracting reusable `chat_bubble` / `chat_input` components.
- Restyling `ChannelsChatLive`.
- Adding Storybook stories for core components broadly.
- Migrating to Tailwind v4 / DaisyUI v5.
