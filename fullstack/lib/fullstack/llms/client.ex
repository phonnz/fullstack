defmodule Fullstack.Llms.Client.Local do
  @default_question "What's the capital of Mexico?"
  def call(text \\ @default_question) do
    data =
      %{
        "model" => "deepseek-r1",
        "prompt" => text
      }
      |> Jason.encode!()

    req =
      Finch.build(:post, "http://localhost:11434/api/generate", [], data)

    with {:ok, %{response: body}} <-
           Finch.stream(
             req,
             Fullstack.Finch,
             %{thinking: true, response: "", think: ""},
             fn
               {:status, value}, acc ->
                 IO.inspect(value)
                 acc

               {:headers, value}, acc ->
                 acc

               {:data, value}, %{thinking: thinking} = acc ->
                 word = Jason.decode!(value) |> Map.fetch!("response")

                 case word do
                   "</think>" ->
                     IO.puts("Answering...")
                     %{acc | thinking: false}

                   "<think>" ->
                     IO.puts("Thinking...")
                     acc

                   new_word when thinking ->
                     Map.update(acc, :think, new_word, &(&1 <> " #{new_word}"))

                   new_word when not thinking ->
                     Map.update(acc, :response, new_word, &(&1 <> " #{new_word}"))
                 end

               {:done, value}, _ ->
                 IO.inspect(value, label: :DONE)
             end,
             pool_timeout: 60_000,
             receive_timeout: 60_000
           ) do
      {
        :ok,
        body
      }
    else
      x ->
        IO.inspect("Error: #{x}")
    end
  end
end
