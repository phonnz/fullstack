defmodule Fullstack.Channels.TwilioTest do
  use ExUnit.Case, async: true

  alias Fullstack.Channels.Twilio

  # Reference vector from Twilio's request validation docs and SDK tests.
  @url "https://mycompany.com/myapp.php?foo=1&bar=2"
  @params %{
    "CallSid" => "CA1234567890ABCDE",
    "Caller" => "+14158675309",
    "Digits" => "1234",
    "From" => "+14158675309",
    "To" => "+18005551212"
  }
  @signature "RSOYDt4T1cUTdK1PDd93/VVr8B8="

  describe "valid_signature?/4" do
    test "accepts the reference signature" do
      assert Twilio.valid_signature?(@url, @params, @signature, "12345")
    end

    test "rejects a tampered parameter, URL or token" do
      refute Twilio.valid_signature?(@url, %{@params | "Digits" => "9999"}, @signature, "12345")
      refute Twilio.valid_signature?(@url <> "&x=1", @params, @signature, "12345")
      refute Twilio.valid_signature?(@url, @params, @signature, "54321")
    end

    test "rejects nested parameters, which Twilio never sends, without raising" do
      params = Map.put(@params, "Nested", %{"a" => "b"})
      refute Twilio.valid_signature?(@url, params, @signature, "12345")
    end

    test "rejects a missing signature or a missing token" do
      refute Twilio.valid_signature?(@url, @params, nil, "12345")
      refute Twilio.valid_signature?(@url, @params, @signature, nil)
      refute Twilio.valid_signature?(@url, @params, @signature, "")
    end
  end

  describe "send_whatsapp/2" do
    test "posts the message to the Messages API with basic auth" do
      test_pid = self()

      Req.Test.stub(Twilio, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [auth] = Plug.Conn.get_req_header(conn, "authorization")
        send(test_pid, {:twilio, conn.method, conn.request_path, URI.decode_query(body), auth})
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM42"})
      end)

      assert Twilio.send_whatsapp("whatsapp:+5215512345678", "Hola") == {:ok, "SM42"}

      assert_received {:twilio, "POST", "/2010-04-01/Accounts/ACtest/Messages.json", params, auth}

      assert params == %{
               "From" => "whatsapp:+14155238886",
               "To" => "whatsapp:+5215512345678",
               "Body" => "Hola"
             }

      assert auth == "Basic " <> Base.encode64("ACtest:test_auth_token")
    end

    test "returns the status and body of a rejected request" do
      Req.Test.stub(Twilio, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"code" => 21_211})
      end)

      assert Twilio.send_whatsapp("whatsapp:+1", "Hi") ==
               {:error, {:http, 400, %{"code" => 21_211}}}
    end
  end
end
