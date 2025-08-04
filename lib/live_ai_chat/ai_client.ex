defmodule LiveAiChat.AIClient do
  @moduledoc """
  A behaviour for clients that interact with an AI service.
  """

  @callback stream_reply(pid :: pid(), user_message :: map()) :: any()

  defmodule Dummy do
    @behaviour LiveAiChat.AIClient

    @canned_response "This is a dummy response from the AI, streamed to you one word at a time."

    @impl true
    def stream_reply(recipient_pid, _user_message) do
      Task.start(fn ->
        # Send the initial assistant message chunk
        assistant_message_id = System.unique_integer()
        send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}})

        # Stream the rest of the response
        for word <- String.split(@canned_response) do
          Process.sleep(5) # Use a shorter sleep for tests
          send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: " " <> word}})
        end

        send(recipient_pid, :ai_done)
      end)
    end
  end

  defmodule Gemini do
    @behaviour LiveAiChat.AIClient
    require Logger

    @impl true
    def stream_reply(recipient_pid, user_message) do
      Task.start(fn ->
        case call_gemini_api(user_message) do
          {:ok, response} ->
            stream_response(recipient_pid, response)
          {:error, reason} ->
            Logger.error("Gemini API error: #{inspect(reason)}")
            send_error_response(recipient_pid, reason)
        end
      end)
    end

    defp call_gemini_api(user_message) do
      project_id = get_project_id()
      location = get_location()
      model = get_model()

      url = "https://#{location}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{location}/publishers/google/models/#{model}:streamGenerateContent"

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{get_access_token()}"}
      ]

      body = %{
        contents: [
          %{
            role: "user",
            parts: [%{text: user_message.content}]
          }
        ],
        generationConfig: %{
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048
        },
        safetySettings: [
          %{
            category: "HARM_CATEGORY_HARASSMENT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_HATE_SPEECH",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          },
          %{
            category: "HARM_CATEGORY_DANGEROUS_CONTENT",
            threshold: "BLOCK_MEDIUM_AND_ABOVE"
          }
        ]
      }

      case Req.post(url, headers: headers, json: body) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}
        {:ok, %{status: status, body: body}} ->
          {:error, "HTTP #{status}: #{inspect(body)}"}
        {:error, reason} ->
          {:error, reason}
      end
    end

    defp stream_response(recipient_pid, response_body) do
      assistant_message_id = System.unique_integer()

      # Send initial chunk
      send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}})

      # Parse the streaming response
      case parse_streaming_response(response_body) do
        {:ok, text_content} ->
          # Simulate streaming by sending words with small delays
          words = String.split(text_content, " ")

          Enum.each(words, fn word ->
            Process.sleep(50) # Small delay to simulate streaming
            content = if word == List.first(words), do: word, else: " " <> word
            send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: content}})
          end)

        {:error, reason} ->
          Logger.error("Failed to parse Gemini response: #{inspect(reason)}")
          send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: "Sorry, I encountered an error processing the response."}})
      end

      send(recipient_pid, :ai_done)
    end

    defp parse_streaming_response(response_body) when is_list(response_body) do
      # Handle list of response objects (streaming format)
      content_parts = 
        response_body
        |> Enum.flat_map(&extract_text_content/1)
      
      case content_parts do
        [] -> {:error, "No content found in response"}
        parts -> {:ok, Enum.join(parts, "")}
      end
    end

    defp parse_streaming_response(response_body) when is_binary(response_body) do
      # Handle streaming response format - each line should be a JSON object
      lines = String.split(response_body, "\n")
      
      content_parts = 
        lines
        |> Enum.filter(&(String.trim(&1) != ""))
        |> Enum.map(&parse_json_line/1)
        |> Enum.filter(&(&1 != nil))
        |> Enum.flat_map(&extract_text_content/1)
      
      case content_parts do
        [] -> {:error, "No content found in response"}
        parts -> {:ok, Enum.join(parts, "")}
      end
    end

    defp parse_streaming_response(response_body) when is_map(response_body) do
      # Handle single JSON response
      case extract_text_content(response_body) do
        [] -> {:error, "No content found in response"}
        parts -> {:ok, Enum.join(parts, "")}
      end
    end

    defp parse_json_line(line) do
      case Jason.decode(line) do
        {:ok, json} -> json
        {:error, _} -> nil
      end
    end

    defp extract_text_content(%{"candidates" => candidates}) when is_list(candidates) do
      candidates
      |> Enum.flat_map(fn candidate ->
        case candidate do
          %{"content" => %{"parts" => parts}} when is_list(parts) ->
            Enum.map(parts, fn part ->
              case part do
                %{"text" => text} -> text
                _ -> ""
              end
            end)
          _ -> []
        end
      end)
    end

    defp extract_text_content(_), do: []

    defp send_error_response(recipient_pid, _reason) do
      assistant_message_id = System.unique_integer()
      send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}})
      send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: "Sorry, I'm having trouble connecting to the AI service right now. Please try again later."}})
      send(recipient_pid, :ai_done)
    end

    defp get_access_token do
      case Goth.fetch(LiveAiChat.Goth) do
        {:ok, %{token: token}} -> token
        {:error, reason} ->
          Logger.error("Failed to get access token: #{inspect(reason)}")
          raise "Failed to authenticate with Google Cloud: #{inspect(reason)}"
      end
    end

    defp get_project_id do
      Application.get_env(:live_ai_chat, :google_cloud_project) ||
        System.get_env("VERTEXAI_PROJECT") ||
        raise "VERTEXAI_PROJECT environment variable not set"
    end

    defp get_location do
      Application.get_env(:live_ai_chat, :google_cloud_location, "europe-west1")
    end

    defp get_model do
      Application.get_env(:live_ai_chat, :gemini_model, "gemini-2.5-flash")
    end
  end
end
