defmodule FullstackWeb.ChatLiveTest do
  use FullstackWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "ChatLive page" do
    test "page shell has no inline style attributes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/chat")

      # Parse HTML and check for style attributes
      parsed = Floki.parse_document!(html)

      # Assert NO element has a style attribute
      elements_with_style = Floki.find(parsed, "[style]")
      assert elements_with_style == [], "Found elements with inline style attribute"

      # Assert NO class contains hardcoded hex colors
      all_classes =
        parsed
        |> Floki.attribute("class")
        |> Enum.join(" ")

      refute String.contains?(all_classes, "#3D9970"), "Found hardcoded color #3D9970"
      refute String.contains?(all_classes, "#001f3f"), "Found hardcoded color #001f3f"
    end

    test "message_line renders DaisyUI chat bubbles for all variants" do
      # Test own message
      own_html =
        Phoenix.LiveViewTest.render_component(&FullstackWeb.ChatLive.message_line/1,
          message: %{id: 1, from: "abc123", text: "My message"},
          tmp_id: "abc123"
        )

      own_parsed = Floki.parse_document!(own_html)

      assert Floki.find(own_parsed, ".chat.chat-end") != [],
             "Own message should have chat chat-end"

      assert Floki.find(own_parsed, ".chat-bubble-primary") != [],
             "Own message should have chat-bubble-primary"

      # Test system message
      system_html =
        Phoenix.LiveViewTest.render_component(&FullstackWeb.ChatLive.message_line/1,
          message: %{id: 2, from: "Fullstack", text: "System message"},
          tmp_id: "abc123"
        )

      system_parsed = Floki.parse_document!(system_html)

      assert Floki.find(system_parsed, ".chat.chat-start") != [],
             "System message should have chat chat-start"

      # chat-bubble-info or chat-bubble-neutral both acceptable
      has_info = Floki.find(system_parsed, ".chat-bubble-info") != []
      has_neutral = Floki.find(system_parsed, ".chat-bubble-neutral") != []
      assert has_info or has_neutral, "System message should have chat-bubble-info or neutral"

      # Test other user message
      other_html =
        Phoenix.LiveViewTest.render_component(&FullstackWeb.ChatLive.message_line/1,
          message: %{id: 3, from: "xyz456", text: "Other's message"},
          tmp_id: "abc123"
        )

      other_parsed = Floki.parse_document!(other_html)

      assert Floki.find(other_parsed, ".chat.chat-start") != [],
             "Other user should have chat chat-start"

      assert Floki.find(other_parsed, ".chat-header") != [],
             "Other user should have chat-header with sender"

      assert Floki.find(other_parsed, ".chat-bubble") != [], "Other user should have chat-bubble"

      # Assert NO old hardcoded classes present
      all_classes =
        (own_html <> system_html <> other_html)
        |> String.downcase()

      refute String.contains?(all_classes, "max-w-40"), "Should not have max-w-40"
      refute String.contains?(all_classes, "max-w-96"), "Should not have max-w-96"
      refute String.contains?(all_classes, "max-w-2/3"), "Should not have max-w-2/3"
      refute String.contains?(all_classes, "bg-indigo-500"), "Should not have bg-indigo-500"
      refute String.contains?(all_classes, "bg-slate-400"), "Should not have bg-slate-400"
    end
  end
end
