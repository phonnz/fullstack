# WhatsApp channel for JidoMarketAgents conversations (Twilio)

Objective: let a WhatsApp user drive the same `Conversation` pipeline as the Business Discovery
LiveView, through a Twilio webhook, with agent replies sent back over WhatsApp.
Branch: `whatsapp-twilio-channel`. Delivery: `exception-ok` (single PR, user decision L10). Test runner: `mix test` (ExUnit).

## Specs

- **S1 — Webhook endpoint.** `POST /webhooks/twilio/whatsapp` accepts Twilio's form-encoded
  inbound message. A missing or invalid `X-Twilio-Signature` (HMAC-SHA1 of the full public URL
  plus the sorted POST parameters, keyed by the auth token) returns 403 with no side effect.
  A valid request returns 200 with TwiML immediately: empty `<Response></Response>` when the
  agents will reply, or a `<Message>` for an immediate system reply (command acknowledgement,
  cap, text-only notice). The agent reply is never sent in the webhook response (the LLM
  pipeline is asynchronous). A signed request without `From` or `MessageSid` returns 400.
- **S2 — Idempotency.** A `MessageSid` already processed is acknowledged with 200 and has no
  further side effect (enforced by a unique index).
- **S3 — Identity (user decision "2").** An unknown WhatsApp number automatically gets a user:
  placeholder email `wa-<digits>@whatsapp.invalid` and a random, never-disclosed password,
  created through the existing registration changeset, plus a `channel_identities` row. A global
  cap on new WhatsApp users per hour (config) bounds LLM cost; over the cap the sender gets a
  short "try later" reply and no user is created.
- **S4 — Active conversation (user decision, verbatim):** "let the use use `/start` `/nuevo` or
  `/new` to start a new conversation and the user will have one active conversation (the last
  updated one over whatsapp." Each identity points at one active conversation; any other
  message continues it. A command (case-insensitive, first token) starts a new conversation:
  with trailing text, that text is its first message; bare, the bot acknowledges and the next
  message creates it.
- **S5 — Outbound relay.** Assistant messages produced by the conversation after an inbound
  message are sent to the sender through the Twilio Messages API, each at most once. Plain text
  is sent as is, split into chunks of at most 1600 characters. A rate-limit event gets a short
  reply.
- **S6 — Stage results as a link (user decision "3").** Assistant messages carrying a stage
  result (`market_research`, `business_analysis`, `systems_strategy`, `tech_strategy`) are not
  sent as JSON: the sender gets a short notice plus a one-time login link to
  `/business-discovery/evaluate/:id`.
- **S7 — One-time login link.** The token is hashed in `users_tokens` (context
  `"whatsapp_login"`), valid 15 minutes, single use. `GET` renders a confirmation page and does
  not consume the token (WhatsApp link previews fetch URLs). `POST` consumes it, logs the user
  in and redirects to the conversation. An expired, unknown or used token is rejected.
- **S8 — Configuration and docs.** `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`,
  `TWILIO_WHATSAPP_FROM` from the environment (runtime config); the setup is documented.
- **Assumption A2.** Bot system replies (acknowledgement, cap, rate limit, notices) are in
  English, matching the existing UI copy.

## Tasks

| ID | Specs | Route | Risk | Status | Commit |
|----|-------|-------|------|--------|--------|
| T1 | S2, S3, S4 | inline | 1 (migration) | done | `6b0ec67` |
| T2 | S1, S8 | inline | 2 (signature) | done | `f51fd39` |
| T3 | S1, S2, S4 | inline | 2 (public endpoint) | done | `b410dd1` |
| T4 | S5, S6 | inline | 4 (subscribe before broadcast) | done | `34bee87`, baseline fix in `b410dd1` |
| T5 | S6, S7 | inline | 2 (auth) | done | `55a3d08` |
| T6 | S8 | inline | none (docs) | done | docs commit |
| V1 | all | delegated verifier | items 1, 2, 4 | done: pass, 0 blockers | fixes `3255a30` |

Route evidence: no Writer trigger reason; units share `router.ex` and config, so they run
inline in order. One independent verifier runs at the feature's end (high-risk items 1, 2, 4).
Forecast: about 1100 authored changed lines, so `ask-on-risk` applies before pushing.

## Log

- **L1 (2026-11-19, user):** "Make a plan to enable the conversation for JidoMarketAgents from
  an API to receive messages from Twilio integration with WhatsApp and not only from the UI
  interface. ASk for any clarification."
- **L2 (2026-11-19, user, identity mapping):** "2" (auto-create a user per phone number).
- **L3 (2026-11-19, user, stage results):** "3" (notice plus link to the web view).
- **L4 (2026-11-20, user):** "Yes let the use use `/start` `/nuevo` or `/new` to start a new
  conversation and the user will have one active conversation (the last updated one over
  whatsapp. Continue"
- **L5 (2026-11-20):** Baseline on `whatsapp-twilio-channel` (branched from `fix-stale-tests`
  with an unrelated dirty tree): `mix test` 828 tests, 0 failures. Unrelated uncommitted changes
  in `config/runtime.exs`, `config/test.exs` and others are never staged; only this feature's
  hunks are committed.
- **L6 (2026-11-20, decisions):** placeholder email via `Accounts.register_user/1` (no `users`
  schema change); relays run under the existing `ConversationSupervisor` and register in
  `ConversationRegistry` as `{:whatsapp_relay, id}` (no `application.ex` change); a new
  conversation is created before its relay subscribes, so no broadcast can precede the
  subscription; the login URL is passed to the relay as a function, like the existing
  `deliver_*_instructions` url funs.
- **L7 (2026-11-20, evidence):** RED observed before each GREEN: T1 (module missing), T2
  (module missing), T4 (module missing; DB-baseline test failed on the previous relay), T5
  (functions/routes missing), T3 (11/11 failing with the code stashed). GREEN: channels 12,
  twilio 5, relay 8, login token 5 + controller 5, webhook 11. Relay and webhook suites stable
  over 9 to 16 repeated runs. Full suite: 874 tests, 0 failures (baseline 828). Changes to
  pre-existing files are additions only (accounts, user_token, router, config), so no
  differential check applies. Twilio signature algorithm checked against the twilio-python
  reference vector (`RSOYDt4T1cUTdK1PDd93/VVr8B8=`).
- **L8 (2026-11-20, decisions):** system replies go back as TwiML `<Message>` (no API call);
  S1 updated. The relay's baseline is read from the running conversation, or from persisted
  messages when it is stopped, so `start_or_resume/3` stays the only thing that starts
  conversations. Setup documented in `lib/fullstack/channels/README.md`. The branch sits on
  `f45475b` (main merged into `fix-stale-tests`); feature range `f45475b..HEAD`, about 1700
  added lines in 6 commits, not pushed. Pending: manual Twilio sandbox run (needs the user's
  credentials and a tunnel).
- **L9 (2026-11-20, verification):** independent verifier verdict pass, S1-S8 PASS, no
  blockers; probes outside the workspace, migration round trip clean. Fixed in `3255a30`
  (RED then GREEN): (1) placeholder-email squatting, since web sign-up and email change now
  reject `.invalid` and channel users use `Accounts.register_channel_user/1`; (5) nested
  params raised 500, now fail the signature check; (6) a deleted user crashed the relay, now
  the notice is sent without a link. Accepted advisories, open: the hourly cap is soft under
  concurrency; grapheme-based chunking may exceed Twilio's limit for emoji-heavy text; two
  simultaneous first messages can create two conversations; an idle relay can exit right
  after a touch; expired `whatsapp_login` tokens are not purged; phone numbers appear in logs.
  Full suite 880 tests: 0 failures in 5 of 7 runs; the intermittent failures are the
  documented pre-existing `ConversationPipelineTest` timing flakes (same seed passes on rerun).
- **L10 (2026-11-20, user):** "Look into .env and see if the twilio credentials works to you.
  One PR size exception is ok". `.env` has no `TWILIO_*` variables (names checked only; a
  second read was denied by permissions). Single PR to `main` with all 8 commits.
- **L11 (2026-11-20, user):** "source .env and you will find the Twilio vars". Read-only
  checks (HTTP status only, no values printed): `TWILIO_ACCOUNT_SID` + `TWILIO_AUTH_TOKEN` ->
  401 (code 20003); `TWILIO_SID` + `TWILIO_AUTH_TOKEN` -> 200, account active, type Full.
  `TWILIO_WHATSAPP_FROM` lacks the `whatsapp:` prefix. Needed in `.env` before a sandbox run:
  `TWILIO_ACCOUNT_SID` set to the `TWILIO_SID` value, and `TWILIO_WHATSAPP_FROM` prefixed with
  `whatsapp:`. No message sent.
