defmodule LiveAiChat.Knowledge.Extractor do
  @moduledoc """
  Module for extracting content and metadata from uploaded files using AI.
  Runs extraction tasks in the background to avoid blocking the upload process.
  """

  require Logger

  @task_supervisor LiveAiChat.TaskSupervisor
  # @ai_client LiveAiChat.AIClient.Gemini  # Reserved for future AI integration

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

  Returns {:ok, metadata} on success or {:error, reason} on failure.
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

        # Assign extracted topics as initial tags for the file
        case assign_topics_as_tags(filename, metadata) do
          :ok ->
            Logger.info(
              "Successfully extracted, saved metadata, and assigned tags for #{filename}"
            )

          {:error, tag_reason} ->
            Logger.warning(
              "Failed to assign extracted topics as tags for #{filename}: #{inspect(tag_reason)}"
            )

            # Don't fail the extraction if tagging fails
        end

        {:ok, metadata}

      {:error, reason} ->
        Logger.error("Content extraction failed for #{filename}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_extraction(filename, binary_content, file_type) do
    case file_type do
      :text ->
        extract_from_text(filename, binary_content)

      :pdf ->
        extract_from_pdf(filename, binary_content)

      :markdown ->
        extract_from_markdown(filename, binary_content)

      unsupported ->
        {:error, {:unsupported_file_type, unsupported}}
    end
  end

  defp extract_from_text(filename, binary_content) do
    content = binary_content
    extract_with_ai(filename, content, "text file")
  end

  defp extract_from_markdown(filename, binary_content) do
    content = binary_content
    extract_with_ai(filename, content, "markdown document")
  end

  defp extract_from_pdf(filename, binary_content) do
    # Use Gemini directly for PDF analysis instead of pdftotext
    extract_with_ai_pdf(filename, binary_content, "pdf")
  end

  defp extract_with_ai(filename, content, content_type) do
    _prompt = build_extraction_prompt(content, content_type)

    # For now, we'll create a simple extraction since we need to adapt the AI client
    # to support extraction vs. chat completion
    # TODO: Integrate with actual AI client for enhanced extraction
    {:ok, metadata} = extract_using_simple_analysis(content)

    enhanced_metadata =
      Map.merge(metadata, %{
        "filename" => filename,
        "contentType" => content_type,
        "extractedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "extractorVersion" => "1.0.0"
      })

    {:ok, enhanced_metadata}
  end

  defp extract_with_ai_pdf(filename, binary_content, content_type) do
    prompt = build_pdf_extraction_prompt()

    case LiveAiChat.AIClient.Gemini.extract_document_content(binary_content, prompt) do
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

          {:error, _reason} ->
            Logger.warning(
              "Failed to parse AI extraction response for #{filename}, falling back to simple analysis"
            )

            # Fallback to simple analysis with placeholder content
            extract_with_ai(filename, "[PDF file analyzed by Gemini]", content_type)
        end

      {:error, reason} ->
        Logger.error("Gemini PDF extraction failed for #{filename}: #{inspect(reason)}")
        # Fallback to simple analysis
        extract_with_ai(filename, "[PDF file - Gemini extraction failed]", content_type)
    end
  end

  defp build_extraction_prompt(content, content_type) do
    """
    Please analyze the following #{content_type} and extract key information.

    Return a JSON object with the following structure:
    {
      "summary": "A brief summary of the content (2-3 sentences)",
      "keyPoints": ["list", "of", "main", "points"],
      "topics": ["list", "of", "main", "topics"],
      "concepts": ["key", "concepts", "mentioned"],
      "difficulty": "beginner|intermediate|advanced",
      "estimatedReadTime": "X minutes"
    }

    Content to analyze:
    #{String.slice(content, 0, 4000)}
    #{if String.length(content) > 4000, do: "\n... (content truncated)", else: ""}
    """
  end

  defp build_pdf_extraction_prompt do
    """
    Please analyze this PDF document and extract key information in JSON format.

    Return a JSON object with the following structure:
    {
      "summary": "A concise 2-3 sentence summary of the main content and purpose of this document",
      "keyPoints": ["List of 3-7 key points or main topics covered in the document"],
      "topics": ["List of 2-5 relevant categories or tags that describe the document type, subject area, or domain"],
      "concepts": ["Key concepts, terms, or technologies mentioned in the document"],
      "difficulty": "beginner|intermediate|advanced",
      "estimatedReadTime": "X minutes"
    }

    For PDFs and images: You can read text, analyze charts, tables, diagrams, and extract any relevant information.
    Focus on the main content, structure, and purpose of the document.
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
                "topics" => Map.get(parsed_json, "topics", ["general"]),
                "concepts" => Map.get(parsed_json, "concepts", []),
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

  defp assign_topics_as_tags(filename, metadata) do
    # Extract topics from metadata - handle both "topics" and "categories" keys
    # as the AI extraction might use "categories" while simple analysis uses "topics"
    topics = Map.get(metadata, "topics", []) ++ Map.get(metadata, "categories", [])

    case topics do
      [] ->
        Logger.debug("No topics found to assign as tags for #{filename}")
        :ok

      topic_list when is_list(topic_list) ->
        # Filter out empty or nil topics and ensure they are strings
        valid_topics =
          topic_list
          |> Enum.filter(&(&1 != nil and &1 != ""))
          |> Enum.map(&to_string/1)
          |> Enum.uniq()

        case valid_topics do
          [] ->
            Logger.debug("No valid topics found to assign as tags for #{filename}")
            :ok

          tags ->
            Logger.info(
              "Assigning #{length(tags)} extracted topics as tags for #{filename}: #{inspect(tags)}"
            )

            try do
              LiveAiChat.TagStorage.update_tags_for_file(filename, tags)
              :ok
            rescue
              error ->
                {:error, error}
            end
        end

      _ ->
        Logger.warning("Invalid topics format in metadata for #{filename}: #{inspect(topics)}")
        :ok
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
      ".pdf" -> {:ok, :pdf}
      ext -> {:error, {:unsupported_file_type, ext}}
    end
  end
end
