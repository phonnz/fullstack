# WhatsApp channel (Twilio)

WhatsApp users talk to the same JidoMarketAgents conversation pipeline as the
Business Discovery web UI (`/business-discovery/evaluate`).

## How a message flows

1. Twilio posts the inbound message to `POST /webhooks/twilio/whatsapp`.
2. `FullstackWeb.TwilioWebhookController` rejects the request with 403 unless
   `X-Twilio-Signature` is valid, then answers right away with TwiML.
3. `Fullstack.Channels.WhatsApp`:
   - ignores a `MessageSid` it has already processed;
   - finds the sender, or creates a user for a new number
     (`wa-<digits>@whatsapp.invalid` with a random password), up to
     `max_new_per_hour` new senders per hour;
   - handles `/start`, `/nuevo` and `/new`: alone they clear the active
     conversation, followed by text they start a new conversation with that text;
   - starts the conversation's `Relay` and enqueues the text through
     `Conversations.start_or_resume/3`.
4. `Fullstack.Channels.WhatsApp.Relay` listens on the conversation topic and
   sends each new assistant message through the Twilio Messages API, in
   chunks of at most 1600 characters. For a stage result (market research,
   business analysis, systems or technology strategy) it sends a one-time
   login link instead of the JSON.
5. The link (`/whatsapp/login/:token`, valid 15 minutes, single use) shows a
   "Continue" button. The POST logs the user in and opens the conversation.

Each sender has one active conversation: the one used last over WhatsApp.

## Configuration

| Variable | Purpose |
|---|---|
| `TWILIO_ACCOUNT_SID` | Account SID for the Messages API |
| `TWILIO_AUTH_TOKEN` | API auth token; also verifies webhook signatures |
| `TWILIO_WHATSAPP_FROM` | Sender address, for example `whatsapp:+14155238886` (sandbox) |
| `TWILIO_WEBHOOK_BASE_URL` | Public base URL Twilio calls, when it differs from the endpoint URL (tunnel or proxy) |

Without `TWILIO_AUTH_TOKEN` every webhook request is rejected; without the
other variables replies are not sent (errors are logged).

The cap on new senders defaults to 50 per hour:

```elixir
config :fullstack, Fullstack.Channels, max_new_per_hour: 50
```

## Local testing with the Twilio sandbox

1. Join the WhatsApp sandbox in the Twilio console (Messaging > Try it out).
2. Expose the app, for example `cloudflared tunnel --url http://localhost:4000`.
3. Set the sandbox "When a message comes in" URL to
   `https://<tunnel-host>/webhooks/twilio/whatsapp` (HTTP POST).
4. Start the app with the variables above, with
   `TWILIO_WEBHOOK_BASE_URL=https://<tunnel-host>`.
5. Send a message from the joined phone.

## Known limits

- Single node: relays are registered in the local conversation registry.
- A reply is sent only while the conversation's relay runs (30 minutes after
  the last activity). Missed replies remain visible in the web view.
- Only text messages are read; media gets a "text only" reply.
