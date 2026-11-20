defmodule Fullstack.Observability.SentryScrubberTest do
  use ExUnit.Case, async: true

  alias Fullstack.Observability.SentryScrubber

  defp event(request) do
    Sentry.Event.create_event(message: "boom") |> Map.put(:request, request)
  end

  test "filters sensitive headers, nested params, cookies and query string" do
    scrubbed =
      SentryScrubber.before_send(
        event(%{
          headers: %{"Authorization" => "Bearer abc", "accept" => "text/html"},
          data: %{"user" => %{"email" => "a@b.c", "password" => "hunter2"}, "ok" => 1},
          cookies: %{"_fullstack_key" => "s3cr3t"},
          query_string: "token=abc"
        })
      )

    assert scrubbed.request.headers["Authorization"] == "[FILTERED]"
    assert scrubbed.request.headers["accept"] == "text/html"
    assert scrubbed.request.data["user"]["password"] == "[FILTERED]"
    assert scrubbed.request.data["user"]["email"] == "a@b.c"
    assert scrubbed.request.data["ok"] == 1
    assert scrubbed.request.cookies == "[FILTERED]"
    assert scrubbed.request.query_string == "[FILTERED]"
  end

  test "leaves events without request context untouched" do
    ev = Sentry.Event.create_event(message: "boom")
    assert SentryScrubber.before_send(ev) == ev
  end

  test "sentry has no DSN in the test environment" do
    assert Sentry.Config.dsn() == nil
  end
end
