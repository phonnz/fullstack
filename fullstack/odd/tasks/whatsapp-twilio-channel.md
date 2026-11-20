# WhatsApp channel for JidoMarketAgents conversations (Twilio)

Objective: let a WhatsApp user drive the same `Conversation` pipeline as the Business Discovery
LiveView, through a Twilio webhook, with agent replies sent back over WhatsApp.
Branch: `whatsapp-twilio-channel`. Delivery: `ask-on-risk`. Test runner: `mix test` (ExUnit).

## Specs

- **S1 — Webhook endpoint.** `POST /webhooks/twilio/whatsapp` accepts Twilio's form-encoded
  inbound message. A missing or invalid `X-Twilio-Signature` (HMAC-SHA1 of the full public URL
  plus the sorted POST parameters, keyed by the auth token) returns 403 with no side effect.
  A valid request returns 200 with an empty TwiML `<Response></Response>` immediately; the
  agent reply is never sent in the webhook response (the LLM pipeline is asynchronous).
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
| T1 | S2, S3, S4 | inline | 1 (migration) | pending | |
| T2 | S1, S8 | inline | 2 (signature) | pending | |
| T3 | S1, S2, S4 | inline | 2 (public endpoint) | pending | |
| T4 | S5, S6 | inline | 4 (subscribe before broadcast) | pending | |
| T5 | S6, S7 | inline | 2 (auth) | pending | |

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
