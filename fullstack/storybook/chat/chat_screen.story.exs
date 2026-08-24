defmodule Storybook.Chat.ChatScreen do
  use PhoenixStorybook.Story, :page

  def doc do
    """
    # Chat Screen Layout

    The ChatLive screen (`/chat`) uses inline DaisyUI + Tailwind markup for layout elements that are NOT yet extracted as reusable components.

    ## Page Shell Structure

    - **Outer container**: `flex flex-col h-screen bg-base-200`
    - **Header region**: Uses existing `<.header>` component with `badge badge-neutral badge-lg` for user identifier
    - **Messages region**: `flex-1 overflow-y-auto p-4 space-y-2` with `phx-update="append"` + `temporary_assigns` for streaming messages
    - **Footer region**: `shrink-0 border-t border-base-300 bg-base-100 p-4` (non-overlapping, flex child)

    ## Footer Components (Inline, Extraction Candidates)

    ### Presence/Stats Line
    - Classes: `text-sm text-base-content/60`
    - Displays: `@users_count users with @connections connections`
    - **Extraction candidate**: Could become a `<.presence_stats>` component

    ### Typing Indicator
    - ARIA: `role="status" aria-live="polite"`
    - Classes: `text-sm text-base-content/60`
    - Icon: `<span class="loading loading-dots loading-xs"></span>`
    - **Extraction candidate**: Could become a `<.typing_indicator>` component

    ### Chat Input
    - Uses native `<.form>` + `<input class="input input-bordered w-full">`
    - Submit button: `<button class="btn btn-primary">Send</button>`
    - **Extraction candidate**: Could become a `<.chat_input>` component
    - **Rationale for native form**: Shared `<.simple_form>` + `<.input>` from core_components.ex have hardcoded styling (`mt-10 bg-white`, zinc/rose colors) that conflicts with DaisyUI theme surfaces. This screen uses a local native input to avoid fighting shared component defaults.

    ## Message Bubbles

    See `message_line.story.exs` for the existing `message_line/1` function that renders DaisyUI chat bubbles.

    ## Notes

    - No inline `style="..."` attributes — all styling via DaisyUI/Tailwind classes
    - Theme: DaisyUI `light`/`dark` themes configured in `assets/tailwind.config.js`
    - Accessibility: Typing indicator is an ARIA live region; message stream uses semantic HTML
    - Future: Extract inline footer elements into reusable components when broader chat UI patterns emerge
    """
  end
end
