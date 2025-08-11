# Request (20250811_210426)

```
pdf_extraction has to be implemented using gemini as in @simple-knowledge-pool-ai_1_prototype.md 
```

# Response


Okay, I understand. You want to integrate PDF extraction using Google Gemini into your Elixir Phoenix LiveView application, following the pattern established in the provided SvelteKit prototype.

Here's a step-by-step plan to achieve this:

1.  **Update `LiveAiChat.AIClient` behaviour:** Add a new callback for synchronous document extraction.
2.  **Implement `LiveAiChat.AIClient.Gemini.extract_document_content/2`:** This function will handle sending PDF binaries to the Gemini API for extraction.
3.  **Modify `LiveAiChat.Knowledge.Extractor.extract_from_pdf/2`:** Update it to use the new Gemini extraction function.
4.  **Refine `LiveAiChat.Knowledge.Extractor.parse_ai_extraction_response/1`:** Ensure it correctly parses the JSON output from Gemini's extraction.
5.  **Adjust `test/live_ai_chat/knowledge/extractor_test.exs`:** Update the PDF test case to mock the Gemini client and assert the expected successful extraction.
6.  **Clean up `test_pdf_extraction.exs`:** Remove the outdated `pdftotext` manual test.

Let's start with the modifications.

***

### Step 1: Update `lib/live_ai_chat/ai_client.ex`

I will add the `extract_document_content` callback to the `AIClient` behaviour and implement it in the `Gemini` module.

```elixir
# File: lib/live_ai_chat/ai_client.ex
defmodule LiveAiChat.AIClient do
  @moduledoc """
  A behaviour for clients that interact with an AI service.
  """

  @callback stream_reply(pid :: pid(), user_message :: map()) :: any()
  @callback extract_document_content(binary(), String.t()) :: {:ok, String.t()} | {:error, term()} # Added callback

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

    @impl true # Dummy implementation for the new callback
    def extract_document_content(_binary_content, _extraction_prompt) do
      {:ok, """
        {
          "summary": "This is a dummy summary from a PDF.",
          "keyPoints": ["Dummy point 1", "Dummy point 2"],
          "topics": ["dummy", "pdf"],
          "concepts": ["dummy concept"],
          "difficulty": "beginner",
          "estimatedReadTime": "1 minute"
        }
      """}
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
    Extract content from a document using Gemini's multimodal capabilities.
    Returns a synchronous response instead of streaming.

    ## Parameters
    - binary_content: The binary content of the PDF file
    - extraction_prompt: The prompt for content extraction

    Returns {:ok, response_text} on success or {:error, reason} on failure.
    """
    @impl true # Implemented callback
    def extract_document_content(binary_content, extraction_prompt) do
      case call_gemini_extraction_api(binary_content, extraction_prompt) do
        {:ok, response} ->
          # The response from generateContent is a single JSON object, not a stream
          case extract_text_content(response) do
            [] -> {:error, "No content found in extraction response"}
            parts -> {:ok, Enum.join(parts, "")}
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

      contents =
        user_message
        |> Map.get(:content)
        |> List.wrap()
        |> Enum.map(fn text -> %{role: "user", parts: [%{text: text}]} end)

      body = %{
        contents: contents,
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
          maxOutputTokens: 4096
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
  end
end
```

### Step 2: Modify `lib/live_ai_chat/knowledge/extractor.ex`

I will update `extract_from_pdf/2` to use the new Gemini extraction function and refine `parse_ai_extraction_response/1`.

```elixir
# File: lib/live_ai_chat/knowledge/extractor.ex
defmodule LiveAiChat.Knowledge.Extractor do
  @moduledoc """
  Module for extracting content and metadata from uploaded files using AI.
  Runs extraction tasks in the background to avoid blocking the upload process.
  """

  require Logger

  @task_supervisor LiveAiChat.TaskSupervisor
  @ai_client LiveAiChat.AIClient # Use the behaviour directly

  @doc """
  Enqueues a file for content extraction in a background task.

  ## Parameters
  - filename: The name of the uploaded file
  - binary_content: The binary content of the file

  Returns the Task reference for the background extraction process.
  """
  @spec enqueue(String.t(), binary()) :: {:ok, Task.t()} | {:error, term()}
  def enqueue(filename, binary_content) do
    Task.Supervisor.start_child(@task_supervisor, fn ->
      extract_and_save(filename, binary_content)
    end)
  end

  @doc """
  Extracts content from a file synchronously (mainly for testing).

  ## Parameters
  - filename: The name of the file
  - binary_content: The binary content of the file

  Returns {:ok, metadata} on success or {:error, term()} on failure.
  """
  @spec extract_content(String.t(), binary()) :: {:ok, map()} | {:error, term()}
  def extract_content(filename, binary_content) do
    case determine_file_type(filename) do
      {:ok, file_type} ->
        perform_extraction(filename, binary_content, file_type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Private Functions -----------------------------------------------------

  defp extract_and_save(filename, binary_content) do
    Logger.info("Starting content extraction for #{filename}")

    case extract_content(filename, binary_content) do
      {:ok, metadata} ->
        LiveAiChat.TagStorage.save_extraction(filename, metadata)
        Logger.info("Successfully extracted and saved metadata for #{filename}")
        {:ok, metadata}

      {:error, reason} ->
        Logger.error("Content extraction failed for #{filename}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_extraction(filename, binary_content, file_type) do
    case file_type do
      :text ->
        extract_with_ai(filename, binary_content, "text file")

      :pdf ->
        extract_with_ai_pdf(filename, binary_content, "pdf")

      :markdown ->
        extract_with_ai(filename, binary_content, "markdown document")

      unsupported ->
        {:error, {:unsupported_file_type, unsupported}}
    end
  end

  # This function now acts as a fallback for text/markdown or if AI extraction fails
  defp extract_with_ai(filename, content, content_type) do
    # For now, we'll create a simple extraction since we need to adapt the AI client
    # to support extraction vs. chat completion
    # TODO: Integrate with actual AI client for enhanced extraction
    {:ok, metadata} = extract_using_simple_analysis(content)

    enhanced_metadata =
      Map.merge(metadata, %{
        "filename" => filename,
        "contentType" => content_type,
        "extractedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "extractorVersion" => "1.0.0-simple"
      })

    {:ok, enhanced_metadata}
  end

  defp extract_with_ai_pdf(filename, binary_content, content_type) do
    prompt = build_pdf_extraction_prompt()

    case @ai_client.extract_document_content(binary_content, prompt) do
      {:ok, response_text} ->
        case parse_ai_extraction_response(response_text) do
          {:ok, metadata} ->
            enhanced_metadata =
              Map.merge(metadata, %{
                "filename" => filename,
                "contentType" => content_type,
                "extractedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
                "extractorVersion" => "2.0.0-gemini"
              })

            {:ok, enhanced_metadata}

          {:error, reason} ->
            Logger.warning("Failed to parse AI extraction response for #{filename}: #{inspect(reason)}, falling back to simple analysis")
            # Fallback to simple analysis with placeholder content
            extract_with_ai(filename, "[PDF file analyzed by Gemini - parsing failed]", content_type)
        end

      {:error, reason} ->
        Logger.error("Gemini PDF extraction failed for #{filename}: #{inspect(reason)}")
        # Fallback to simple analysis
        extract_with_ai(filename, "[PDF file - Gemini extraction failed]", content_type)
    end
  end

  defp build_pdf_extraction_prompt do
    """
    Please analyze this PDF document and extract the following information in JSON format:

    {
      "summary": "A concise 2-3 sentence summary of the main content and purpose of this document",
      "keyPoints": ["List of 3-7 key points or main topics covered in the document"],
      "categories": ["List of 2-5 relevant categories or tags that describe the document type, subject area, or domain"]
    }

    Allowed categories:
    - "AI Knowledge Management"
    - "AI Agents"
    - "AI Automation"
    - "AI Tools"
    - "Psychology"
    - "Leadership"
    - "Communication"
    - "Teamwork"
    - "Decision Making"
    - "Problem Solving"
    - "Creativity"
    - "Innovation"
    - "Organisation"
    - "Productivity"
    - "Research"
    - "Strategy"
    - "Marketing"
    - "Sales"
    - "Customer Support"

    Guidelines:
    - Summary should be informative but brief
    - Key points should capture the most important information or topics
    - Categories should be general enough to group similar documents together
    - Return only valid JSON, no additional text or explanation
    """
  end

  defp parse_ai_extraction_response(response_text) do
    try do
      # Extract JSON from the response (LLM might include some text before/after JSON)
      json_match = Regex.run(~r/\{[\s\S]*\}/, response_text)

      case json_match do
        [json_string] ->
          case Jason.decode(json_string) do
            {:ok, parsed_json} ->
              # Validate required fields and convert to expected format
              metadata = %{
                "summary" => Map.get(parsed_json, "summary", "Summary not available"),
                "keyPoints" => Map.get(parsed_json, "keyPoints", []),
                "topics" => Map.get(parsed_json, "categories", ["general"]), # Use 'categories' from AI response as 'topics'
                "concepts" => Map.get(parsed_json, "concepts", []), # Keep if AI returns it
                "difficulty" => Map.get(parsed_json, "difficulty", "intermediate"),
                "estimatedReadTime" => Map.get(parsed_json, "estimatedReadTime", "5 minutes"),
                "extractionMethod" => "gemini_ai"
              }

              {:ok, metadata}

            {:error, decode_error} ->
              Logger.warning("Failed to decode JSON from AI response: #{inspect(decode_error)}")
              {:error, :json_decode_error}
          end

        nil ->
          Logger.warning("No JSON found in AI response: #{response_text}")
          {:error, :no_json_found}
      end
    rescue
      error ->
        Logger.error("Error parsing AI extraction response: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  # Simple content analysis without AI (fallback/placeholder)
  defp extract_using_simple_analysis(content) do
    content_str = to_string(content)
    word_count = content_str |> String.split() |> length()

    # Simple heuristics for content analysis
    summary = extract_first_sentences(content_str, 2)
    key_points = extract_bullet_points(content_str)
    topics = extract_common_topics(content_str)

    metadata = %{
      "summary" => summary,
      "keyPoints" => key_points,
      "topics" => topics,
      "wordCount" => word_count,
      "estimatedReadTime" => "#{max(1, div(word_count, 200))} minutes",
      "difficulty" => determine_difficulty(content_str),
      "extractionMethod" => "simple_analysis"
    }

    {:ok, metadata}
  end

  defp extract_first_sentences(content, count) do
    content
    |> String.split(~r/[.!?]+/)
    |> Enum.take(count)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(". ")
    |> case do
      "" -> "Content summary not available"
      summary -> summary <> "."
    end
  end

  defp extract_bullet_points(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&(String.match?(&1, ~r/^\s*[-*•]\s+/) || String.match?(&1, ~r/^\s*\d+\.\s+/)))
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.replace(&1, ~r/^\s*[-*•]\s*/, ""))
    |> Enum.map(&String.replace(&1, ~r/^\s*\d+\.\s*/, ""))
    |> Enum.take(5)
    |> case do
      [] -> ["No bullet points found"]
      points -> points
    end
  end

  defp extract_common_topics(content) do
    # Simple topic extraction based on common technical terms
    topic_keywords = %{
      "elixir" => ~r/\belixir\b/i,
      "phoenix" => ~r/\bphoenix\b/i,
      "liveview" => ~r/\blive.?view\b/i,
      "genserver" => ~r/\bgenserver\b/i,
      "otp" => ~r/\botp\b/i,
      "programming" => ~r/\b(programming|coding|development)\b/i,
      "web" => ~r/\b(web|http|html|css|javascript)\b/i,
      "database" => ~r/\b(database|sql|postgres|mysql)\b/i,
      "api" => ~r/\b(api|rest|graphql)\b/i,
      "testing" => ~r/\b(test|testing|spec|tdd|bdd)\b/i
    }

    found_topics =
      topic_keywords
      |> Enum.filter(fn {_topic, regex} -> String.match?(content, regex) end)
      |> Enum.map(fn {topic, _regex} -> topic end)

    case found_topics do
      [] -> ["general"]
      topics -> topics
    end
  end

  defp determine_difficulty(content) do
    # Simple heuristics for difficulty assessment
    advanced_terms =
      ~r/\b(metaprogramming|macros|protocols|behaviours|supervision|distribution|clustering)\b/i

    intermediate_terms = ~r/\b(genserver|supervisor|process|concurrency|pattern.matching)\b/i

    cond do
      String.match?(content, advanced_terms) -> "advanced"
      String.match?(content, intermediate_terms) -> "intermediate"
      true -> "beginner"
    end
  end

  defp determine_file_type(filename) do
    extension =
      filename
      |> Path.extname()
      |> String.downcase()

    case extension do
      ".txt" -> {:ok, :text}
      ".md" -> {:ok, :markdown}
      ".markdown" -> {:ok, :markdown}
      ".pdf" -> {:ok, :pdf} # Now explicitly handled by AI
      ext -> {:error, {:unsupported_file_type, ext}}
    end
  end
end
```

### Step 3: Adjust `test/live_ai_chat/knowledge/extractor_test.exs`

I will update the PDF test case to mock the Gemini client and assert the expected successful extraction.

```elixir
# File: test/live_ai_chat/knowledge/extractor_test.exs
defmodule LiveAiChat.Knowledge.ExtractorTest do
  use ExUnit.Case, async: false

  import Mox # Import Mox for mocking

  alias LiveAiChat.Knowledge.Extractor
  alias LiveAiChat.TagStorage
  alias LiveAiChat.AIClientMock # Alias the mock

  @test_data_dir "priv/test_extractor_data"
  @test_upload_dir "priv/test_extractor_uploads"

  setup do
    # Create test directories
    File.mkdir_p!(@test_data_dir)
    File.mkdir_p!(@test_upload_dir)

    # Configure test directories
    Application.put_env(:live_ai_chat, :data_dir, @test_data_dir)
    Application.put_env(:live_ai_chat, :upload_dir, @test_upload_dir)

    # Start the TagStorage GenServer and TaskSupervisor for testing extraction save functionality
    # (Handle case where they might already be started by application)
    case TagStorage.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case Task.Supervisor.start_link(name: LiveAiChat.TaskSupervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Mock the AIClient behaviour for tests
    Mox.stub_with(AIClientMock, LiveAiChat.AIClient.Dummy)

    on_exit(fn ->
      # Clean up test directories
      File.rm_rf!(@test_data_dir)
      File.rm_rf!(@test_upload_dir)
      Application.delete_env(:live_ai_chat, :data_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "extract_content/2" do
    test "extracts content from text file" do
      content = """
      This is a comprehensive guide to Elixir programming.

      Key concepts include:
      - Pattern matching
      - GenServers for state management
      - Supervisor trees for fault tolerance

      Elixir is a functional programming language that runs on the BEAM virtual machine.
      Phoenix is the web framework built on top of Elixir.
      """

      {:ok, metadata} = Extractor.extract_content("guide.txt", content)

      assert is_map(metadata)
      assert is_binary(metadata["summary"])
      assert is_list(metadata["keyPoints"])
      assert is_list(metadata["topics"])
      assert metadata["filename"] == "guide.txt"
      assert metadata["contentType"] == "text file"
      assert metadata["extractionMethod"] == "simple_analysis"

      # Should detect Elixir-related topics
      assert "elixir" in metadata["topics"]
      assert "phoenix" in metadata["topics"]
    end

    test "extracts content from markdown file" do
      content = """
      # Phoenix LiveView Tutorial

      This tutorial covers the basics of Phoenix LiveView development.

      ## Key Topics
      - Real-time web applications
      - Server-side rendering
      - WebSocket connections

      LiveView enables interactive web applications without writing JavaScript.
      """

      {:ok, metadata} = Extractor.extract_content("tutorial.md", content)

      assert metadata["contentType"] == "markdown document"
      assert metadata["filename"] == "tutorial.md"
      assert "liveview" in metadata["topics"]
      assert "phoenix" in metadata["topics"]
    end

    test "determines difficulty level based on content" do
      beginner_content = "This is a simple introduction to programming concepts."

      intermediate_content =
        "GenServer processes handle state in Elixir applications using pattern matching."

      advanced_content =
        "Metaprogramming with macros allows compile-time code generation and protocol implementations."

      {:ok, beginner_meta} = Extractor.extract_content("beginner.txt", beginner_content)

      {:ok, intermediate_meta} =
        Extractor.extract_content("intermediate.txt", intermediate_content)

      {:ok, advanced_meta} = Extractor.extract_content("advanced.txt", advanced_content)

      assert beginner_meta["difficulty"] == "beginner"
      assert intermediate_meta["difficulty"] == "intermediate"
      assert advanced_meta["difficulty"] == "advanced"
    end

    test "calculates estimated read time" do
      short_content = "Short text."
      long_content = String.duplicate("word ", 1000)

      {:ok, short_meta} = Extractor.extract_content("short.txt", short_content)
      {:ok, long_meta} = Extractor.extract_content("long.txt", long_content)

      assert short_meta["estimatedReadTime"] == "1 minutes"
      assert String.contains?(long_meta["estimatedReadTime"], "5 minutes")
    end

    test "extracts bullet points from content" do
      content = """
      Here are the main points:
      - First important point
      - Second key concept
      * Third bullet point
      • Fourth point with different bullet
      1. Numbered first point
      2. Numbered second point

      Some regular text here.
      """

      {:ok, metadata} = Extractor.extract_content("bullets.txt", content)

      key_points = metadata["keyPoints"]
      # Should limit to 5 points
      assert length(key_points) <= 5
      assert "First important point" in key_points
      assert "Second key concept" in key_points
    end

    test "handles content without bullet points" do
      content = "This is just regular text without any bullet points or lists."

      {:ok, metadata} = Extractor.extract_content("plain.txt", content)

      assert metadata["keyPoints"] == ["No bullet points found"]
    end

    test "returns error for unsupported file types" do
      content = "Some content"

      assert {:error, {:unsupported_file_type, _}} =
               Extractor.extract_content("file.xyz", content)
    end

    test "extracts content from PDF files using AIClient.Gemini", %{mox: mox} do
      # Expect a call to the AIClientMock's extract_document_content
      expect(mox, AIClientMock, :extract_document_content, fn _binary, _prompt ->
        {:ok, """
          {
            "summary": "This is a mocked summary of a PDF document about AI.",
            "keyPoints": ["Mocked point 1", "Mocked point 2"],
            "categories": ["AI Knowledge Management", "Research"],
            "concepts": ["mocking", "testing"],
            "difficulty": "advanced",
            "estimatedReadTime": "10 minutes"
          }
        """}
      end)

      content = <<"%PDF-1.4", "some pdf content">>

      {:ok, metadata} = Extractor.extract_content("document.pdf", content)

      assert metadata["filename"] == "document.pdf"
      assert metadata["contentType"] == "pdf"
      assert metadata["summary"] == "This is a mocked summary of a PDF document about AI."
      assert metadata["keyPoints"] == ["Mocked point 1", "Mocked point 2"]
      assert metadata["topics"] == ["AI Knowledge Management", "Research"] # 'categories' from AI response maps to 'topics'
      assert metadata["difficulty"] == "advanced"
      assert metadata["estimatedReadTime"] == "10 minutes"
      assert metadata["extractionMethod"] == "gemini_ai"
    end
  end

  describe "enqueue/2" do
    test "successfully enqueues extraction task" do
      content = "Test content for background extraction with Elixir programming concepts."

      {:ok, pid} = Extractor.enqueue("test.txt", content)

      assert is_pid(pid)

      # Wait for the task to complete by monitoring the process
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      # Check that metadata was saved to TagStorage
      # Give the cast operation time to complete
      Process.sleep(100)
      saved_metadata = TagStorage.get_extraction("test.txt")
      assert saved_metadata["filename"] == "test.txt"
      assert "elixir" in saved_metadata["topics"]
    end

    test "handles extraction errors gracefully" do
      # This should trigger an unsupported file type error
      {:ok, pid} = Extractor.enqueue("unsupported.xyz", "content")

      # Wait for the task to complete by monitoring the process
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      # The task should have completed but with an error
      # We can't directly get the result, but we can verify no metadata was saved
      Process.sleep(100)
      metadata = TagStorage.get_extraction("unsupported.xyz")
      assert metadata == %{}
    end
  end

  describe "file type detection" do
    test "correctly identifies text files" do
      assert {:ok, metadata} = Extractor.extract_content("document.txt", "content")
      assert metadata["contentType"] == "text file"
    end

    test "correctly identifies markdown files" do
      assert {:ok, metadata} = Extractor.extract_content("document.md", "content")
      assert metadata["contentType"] == "markdown document"

      assert {:ok, metadata} = Extractor.extract_content("document.markdown", "content")
      assert metadata["contentType"] == "markdown document"
    end
  end

  describe "topic extraction" do
    test "identifies technical topics correctly" do
      content = """
      This document covers web development with Phoenix framework.
      We'll discuss API design, database integration with PostgreSQL,
      and testing strategies including TDD approaches.
      """

      {:ok, metadata} = Extractor.extract_content("tech.txt", content)

      topics = metadata["topics"]
      assert "phoenix" in topics
      assert "web" in topics
      assert "api" in topics
      assert "database" in topics
      assert "testing" in topics
    end

    test "returns general topic when no specific topics found" do
      content = "This is some general content without specific technical terms."

      {:ok, metadata} = Extractor.extract_content("general.txt", content)

      assert metadata["topics"] == ["general"]
    end
  end

  describe "metadata structure" do
    test "includes all required metadata fields" do
      content = "Test content for metadata validation."

      {:ok, metadata} = Extractor.extract_content("test.txt", content)

      # Check that all expected fields are present
      required_fields = [
        "filename",
        "contentType",
        "extractedAt",
        "extractorVersion",
        "summary",
        "keyPoints",
        "topics",
        "wordCount",
        "estimatedReadTime",
        "difficulty",
        "extractionMethod"
      ]

      for field <- required_fields do
        assert Map.has_key?(metadata, field), "Missing field: #{field}"
      end

      # Check that extractedAt is a valid ISO8601 timestamp
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(metadata["extractedAt"])
    end
  end
end
```

### Step 4: Clean up `test_pdf_extraction.exs`

This file is a manual test script and is no longer needed as PDF extraction is now integrated into the main application logic and tested via `extractor_test.exs`.

```elixir
# File: test_pdf_extraction.exs
# This file is no longer needed as PDF extraction is now handled by the main application logic
# and tested via `test/live_ai_chat/knowledge/extractor_test.exs`.
# Deleting this file.
```

## Token Usage

🔢 **Model**: gemini-2.5-flash

📊 Token Usage
  ├─ Prompt:    899353
  ├─ Response:  9303
  ├─ Thoughts:  1185
  └─ Total:     909841

## Generated Files

* Context: .codegiant/20250811_210426_codegiant_context.md
* Raw Output: .codegiant/20250811_210426_codegiant_llm_raw_output.json
* Response: .codegiant/20250811_210426_codegiant_llm_response.md

