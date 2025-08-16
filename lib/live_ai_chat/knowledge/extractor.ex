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
        # Update metadata to include extraction results and mark as ready
        extraction_metadata = Map.merge(metadata, %{"status" => "ready"})
        LiveAiChat.TagStorage.save_extraction(filename, extraction_metadata)

        # Assign extracted topics as initial tags for the file
        case assign_topics_as_tags(filename, metadata) do
          :ok ->
            Logger.info(
              "Successfully extracted, saved metadata, and assigned tags for #{filename}"
            )

            # Notify the LiveView that extraction is complete
            Phoenix.PubSub.broadcast(LiveAiChat.PubSub, "knowledge", {:extraction_done, filename})

          {:error, tag_reason} ->
            Logger.warning(
              "Failed to assign extracted topics as tags for #{filename}: #{inspect(tag_reason)}"
            )

            # Don't fail the extraction if tagging fails - this is not critical
            # But still notify that extraction is complete
            Phoenix.PubSub.broadcast(LiveAiChat.PubSub, "knowledge", {:extraction_done, filename})
        end

        {:ok, metadata}

      {:error, reason} ->
        Logger.error("Content extraction failed for #{filename}: #{inspect(reason)}")
        # Update metadata to show extraction failed
        LiveAiChat.TagStorage.update_metadata(filename, %{
          "status" => "extraction_failed",
          "error" => inspect(reason)
        })
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
    prompt = build_extraction_prompt(content, content_type)
    gemini_client = Application.get_env(:live_ai_chat, :gemini_client, LiveAiChat.AIClient.Gemini)

    # For non-PDF content, use Gemini text completion for extraction
    case gemini_client.get_completion(prompt) do
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
            Logger.warning(
              "Failed to parse AI extraction response for #{filename}: #{inspect(reason)}"
            )

            # Do not fall back to simple analysis - fail the extraction
            {:error, :ai_extraction_failed}
        end

      {:error, reason} ->
        Logger.error("Gemini text extraction failed for #{filename}: #{inspect(reason)}")
        # Do not fall back to simple analysis - fail the extraction
        {:error, :gemini_extraction_failed}
    end
  end

  defp extract_with_ai_pdf(filename, binary_content, content_type) do
    prompt = build_pdf_extraction_prompt()
    gemini_client = Application.get_env(:live_ai_chat, :gemini_client, LiveAiChat.AIClient.Gemini)

    case gemini_client.extract_document_content(binary_content, prompt) do
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
            Logger.warning(
              "Failed to parse AI extraction response for #{filename}: #{inspect(reason)}"
            )

            # Do not fall back to simple analysis - fail the extraction
            {:error, :ai_extraction_failed}
        end

      {:error, reason} ->
        Logger.error("Gemini PDF extraction failed for #{filename}: #{inspect(reason)}")
        # Do not fall back to simple analysis - fail the extraction
        {:error, :gemini_extraction_failed}
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
      # Extract JSON from the response with multiple extraction strategies
      json_string = extract_json_from_response(response_text)

      case json_string do
        {:ok, extracted_json} ->
          case Jason.decode(extracted_json) do
            {:ok, parsed_json} ->
              # Validate that we have meaningful content before proceeding
              case validate_extracted_content(parsed_json) do
                {:ok, validated_metadata} ->
                  enhanced_metadata = Map.put(validated_metadata, "extractionMethod", "gemini_ai")
                  {:ok, enhanced_metadata}

                {:error, reason} ->
                  Logger.warning("AI extraction validation failed: #{reason}")
                  {:error, :invalid_extraction_content}
              end

            {:error, decode_error} ->
              Logger.warning("Failed to decode JSON from AI response: #{inspect(decode_error)}")
              Logger.debug("Extracted JSON string: #{extracted_json}")
              {:error, :json_decode_error}
          end

        {:error, reason} ->
          Logger.warning("Failed to extract JSON from AI response: #{reason}")
          Logger.debug("AI response text: #{String.slice(response_text, 0, 500)}...")
          {:error, :no_json_found}
      end
    rescue
      error ->
        Logger.error("Error parsing AI extraction response: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  defp extract_json_from_response(response_text) do
    # Strategy 1: Extract from complete markdown code blocks (```json ... ```)
    case Regex.run(~r/```(?:json)?\s*(\{[\s\S]*?\})\s*```/i, response_text) do
      [_, json_content] ->
        {:ok, String.trim(json_content)}

      nil ->
        # Strategy 2: Extract from incomplete markdown blocks (```json ... without closing)
        case Regex.run(~r/```(?:json)?\s*(\{[\s\S]*)/i, response_text) do
          [_, potential_json] ->
            # Try to extract a complete JSON object from this
            case Regex.run(~r/(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})/s, potential_json) do
              [_, json_content] ->
                {:ok, String.trim(json_content)}

              nil ->
                # Continue to strategy 3
                extract_json_fallback(response_text)
            end

          nil ->
            # Strategy 3: Extract JSON object between curly braces anywhere in text
            extract_json_fallback(response_text)
        end
    end
  end

  defp validate_extracted_content(parsed_json) do
    # Check that we have meaningful content, not just empty defaults
    summary = Map.get(parsed_json, "summary")
    topics = Map.get(parsed_json, "topics", [])
    key_points = Map.get(parsed_json, "keyPoints", [])

    cond do
      # Summary is missing or looks like a default/placeholder
      is_nil(summary) or summary == "" or
          String.contains?(String.downcase(summary), ["not available", "summary not available"]) ->
        {:error, "Missing or placeholder summary"}

      # Topics are missing or just defaults
      is_nil(topics) or topics == [] or topics == ["general"] ->
        {:error, "Missing or default topics"}

      # No key points provided
      is_nil(key_points) or key_points == [] ->
        {:error, "Missing key points"}

      true ->
        # Content looks valid, return validated metadata
        metadata = %{
          "summary" => summary,
          "keyPoints" => key_points,
          "topics" => topics,
          "concepts" => Map.get(parsed_json, "concepts", []),
          "difficulty" => Map.get(parsed_json, "difficulty", "intermediate"),
          "estimatedReadTime" => Map.get(parsed_json, "estimatedReadTime", "5 minutes")
        }

        {:ok, metadata}
    end
  end

  defp extract_json_fallback(response_text) do
    case Regex.run(~r/(\{[\s\S]*\})/m, response_text) do
      [_, json_content] ->
        # Clean up potential markdown artifacts
        cleaned_json =
          json_content
          |> String.replace(~r/^```(?:json)?\s*/i, "")
          |> String.replace(~r/\s*```$/, "")
          |> String.trim()

        {:ok, cleaned_json}

      nil ->
        {:error, "No JSON structure found in response"}
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
