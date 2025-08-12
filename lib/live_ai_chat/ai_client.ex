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

        send(
          recipient_pid,
          {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}}
        )

        # Stream the rest of the response
        for word <- String.split(@canned_response) do
          # Use a shorter sleep for tests
          Process.sleep(5)
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

    @doc """
    Get a text completion from Gemini using a text prompt.
    Returns a synchronous response instead of streaming.

    ## Parameters
    - prompt: The text prompt for completion

    Returns {:ok, response_text} on success or {:error, reason} on failure.
    """
    @spec get_completion(String.t()) :: {:ok, String.t()} | {:error, term()}
    def get_completion(prompt) do
      case call_gemini_text_api(prompt) do
        {:ok, response} ->
          case parse_extraction_response(response) do
            {:ok, text_content} -> {:ok, text_content}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Gemini text completion API error: #{inspect(reason)}")
          {:error, reason}
      end
    end

    @doc """
    Extract content from a document using Gemini's multimodal capabilities.
    Returns a synchronous response instead of streaming.

    ## Parameters
    - binary_content: The binary content of the PDF file
    - extraction_prompt: The prompt for content extraction

    Returns {:ok, response_text} on success or {:error, reason} on failure.
    """
    @spec extract_document_content(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
    def extract_document_content(binary_content, extraction_prompt) do
      case call_gemini_extraction_api(binary_content, extraction_prompt) do
        {:ok, response} ->
          case parse_extraction_response(response) do
            {:ok, text_content} -> {:ok, text_content}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Gemini document extraction API error: #{inspect(reason)}")
          {:error, reason}
      end
    end

    defp call_gemini_api(user_message) do
      project_id = get_project_id()
      location = get_location()
      model = get_model()

      url =
        "https://#{location}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{location}/publishers/google/models/#{model}:streamGenerateContent"

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{get_access_token()}"}
      ]

      # Build parts array - handle multimodal content if present
      parts = build_message_parts(user_message)

      body = %{
        contents: [
          %{
            role: "user",
            parts: parts
          }
        ],
        generationConfig: %{
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048,
          thinkingConfig: %{thinkingBudget: 0}
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
      send(
        recipient_pid,
        {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}}
      )

      # Parse the streaming response
      case parse_streaming_response(response_body) do
        {:ok, text_content} ->
          # Simulate streaming by sending words with small delays
          words = String.split(text_content, " ")

          Enum.each(words, fn word ->
            # Small delay to simulate streaming
            Process.sleep(50)
            content = if word == List.first(words), do: word, else: " " <> word
            send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: content}})
          end)

        {:error, reason} ->
          Logger.error("Failed to parse Gemini response: #{inspect(reason)}")

          send(
            recipient_pid,
            {:ai_chunk,
             %{
               id: assistant_message_id,
               content: "Sorry, I encountered an error processing the response."
             }}
          )
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

          _ ->
            []
        end
      end)
    end

    defp extract_text_content(_), do: []

    # Build message parts - handles both text-only and multimodal content
    defp build_message_parts(user_message) do
      # Start with the text content
      text_part = %{text: user_message.content}

      # Add file attachments as inline_data parts if present
      file_parts = case Map.get(user_message, :attachments) do
        nil -> []
        [] -> []
        filenames when is_list(filenames) ->
          Enum.map(filenames, &build_file_part/1)
      end

      [text_part | file_parts]
    end

    defp build_file_part(filename) do
      try do
        case LiveAiChat.FileStorage.read_file(filename) do
          {:ok, binary_content} ->
            mime_type = get_mime_type(filename)
            base64_content = Base.encode64(binary_content)

            %{
              inline_data: %{
                mime_type: mime_type,
                data: base64_content
              }
            }

          {:error, _reason} ->
            Logger.warning("Failed to read file #{filename} for AI request")
            # Return a text part indicating the file couldn't be read
            %{text: "[File #{filename} could not be read]"}
        end
      rescue
        error ->
          Logger.error("Error reading file #{filename}: #{inspect(error)}")
          %{text: "[Error reading file #{filename}]"}
      end
    end

    defp get_mime_type(filename) do
      case String.downcase(Path.extname(filename)) do
        ".pdf" -> "application/pdf"
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".png" -> "image/png"
        ".gif" -> "image/gif"
        ".txt" -> "text/plain"
        ".md" -> "text/markdown"
        _ -> "application/octet-stream"
      end
    end

    defp send_error_response(recipient_pid, _reason) do
      assistant_message_id = System.unique_integer()

      send(
        recipient_pid,
        {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}}
      )

      send(
        recipient_pid,
        {:ai_chunk,
         %{
           id: assistant_message_id,
           content:
             "Sorry, I'm having trouble connecting to the AI service right now. Please try again later."
         }}
      )

      send(recipient_pid, :ai_done)
    end

    defp get_access_token do
      case Goth.fetch(LiveAiChat.Goth) do
        {:ok, %{token: token}} ->
          token

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

    defp call_gemini_text_api(prompt) do
      project_id = get_project_id()
      location = get_location()
      model = get_model()

      # Use generateContent endpoint for synchronous text completion
      url =
        "https://#{location}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{location}/publishers/google/models/#{model}:generateContent"

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{get_access_token()}"}
      ]

      body = %{
        contents: [
          %{
            role: "user",
            parts: [%{text: prompt}]
          }
        ],
        generationConfig: %{
          temperature: 0.3,
          thinkingConfig: %{thinkingBudget: 0}
          # topK: 40,
          # topP: 0.95,
          # maxOutputTokens: 4096
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

      case Req.post(url, headers: headers, json: body, receive_timeout: 60_000) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: status, body: body}} ->
          {:error, "HTTP #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp call_gemini_extraction_api(binary_content, extraction_prompt) do
      project_id = get_project_id()
      location = get_location()
      model = get_model()

      # Use generateContent endpoint instead of streamGenerateContent for synchronous extraction
      url =
        "https://#{location}-aiplatform.googleapis.com/v1/projects/#{project_id}/locations/#{location}/publishers/google/models/#{model}:generateContent"

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{get_access_token()}"}
      ]

      # Encode the PDF binary as base64
      file_base64 = Base.encode64(binary_content)

      body = %{
        contents: [
          %{
            role: "user",
            parts: [
              %{text: extraction_prompt},
              %{
                inline_data: %{
                  mime_type: "application/pdf",
                  data: file_base64
                }
              }
            ]
          }
        ],
        generationConfig: %{
          temperature: 0.1,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 4096,
          thinkingConfig: %{thinkingBudget: 0}
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

      # Set timeout to 180 seconds for PDF extraction (can be large files)
      case Req.post(url, headers: headers, json: body, receive_timeout: 180_000) do
        {:ok, %{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %{status: status, body: body}} ->
          {:error, "HTTP #{status}: #{inspect(body)}"}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp parse_extraction_response(response_body) when is_map(response_body) do
      # Handle single JSON response for generateContent endpoint
      case extract_text_content(response_body) do
        [] -> {:error, "No content found in extraction response"}
        parts -> {:ok, Enum.join(parts, "")}
      end
    end

    defp parse_extraction_response(response_body) do
      # Fallback for other response formats
      {:error, "Unexpected response format: #{inspect(response_body)}"}
    end
  end
end
