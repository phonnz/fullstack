defmodule Storybook.Chat.MessageLine do
  use PhoenixStorybook.Story, :component

  def function, do: &FullstackWeb.ChatLive.message_line/1

  def variations do
    [
      %Variation{
        id: :own,
        description: "Own message (chat-end, primary bubble)",
        attributes: %{
          message: %{id: 1, from: "abc123", text: "Hello! This is my message."},
          tmp_id: "abc123"
        }
      },
      %Variation{
        id: :system,
        description: "System message (chat-start, info bubble)",
        attributes: %{
          message: %{id: 2, from: "Fullstack", text: "xyz456 joined the chat!"},
          tmp_id: "abc123"
        }
      },
      %Variation{
        id: :other_user,
        description: "Other user message (chat-start, neutral bubble with header)",
        attributes: %{
          message: %{id: 3, from: "xyz456", text: "Hey, how's it going?"},
          tmp_id: "abc123"
        }
      },
      %VariationGroup{
        id: :all_message_types,
        description: "All three message types in sequence",
        variations: [
          %Variation{
            id: :own_grouped,
            attributes: %{
              message: %{id: 4, from: "abc123", text: "My message"},
              tmp_id: "abc123"
            }
          },
          %Variation{
            id: :system_grouped,
            attributes: %{
              message: %{id: 5, from: "Fullstack", text: "System message"},
              tmp_id: "abc123"
            }
          },
          %Variation{
            id: :other_grouped,
            attributes: %{
              message: %{id: 6, from: "xyz456", text: "Other's message"},
              tmp_id: "abc123"
            }
          }
        ]
      }
    ]
  end
end
