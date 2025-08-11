#!/usr/bin/env elixir

# Test script to manually trigger PDF extraction
Mix.install([])

defmodule PDFExtractionTest do
  def run do
    # Start the application components we need
    {:ok, _} = Application.ensure_all_started(:logger)

    # Add the project's lib directory to the code path
    Code.prepend_path("_build/dev/lib/live_ai_chat/ebin")

    # Read the PDF file
    pdf_file = "priv/uploads/2503.18238v1.pdf"

    case File.read(pdf_file) do
      {:ok, binary_content} ->
        IO.puts("Successfully read #{pdf_file}, size: #{byte_size(binary_content)} bytes")

        # Try to extract text using pdftotext directly
        temp_file = System.tmp_dir!() |> Path.join("test_pdf_extract.pdf")
        text_file = temp_file <> ".txt"

        try do
          File.write!(temp_file, binary_content)

          case System.cmd("pdftotext", [temp_file, text_file], stderr_to_stdout: true) do
            {output, 0} ->
              IO.puts("pdftotext extraction successful")

              case File.read(text_file) do
                {:ok, text_content} ->
                  cleaned_text = String.trim(text_content)
                  word_count = cleaned_text |> String.split(~r/\s+/, trim: true) |> Enum.count()

                  IO.puts("Extracted text length: #{String.length(cleaned_text)} characters")
                  IO.puts("Word count: #{word_count}")
                  IO.puts("First 500 characters:")
                  IO.puts(String.slice(cleaned_text, 0, 500) <> "...")

                {:error, reason} ->
                  IO.puts("Failed to read extracted text: #{inspect(reason)}")
              end

            {error_output, exit_code} ->
              IO.puts("pdftotext failed with exit code #{exit_code}")
              IO.puts("Error output: #{error_output}")
          end
        after
          File.rm(temp_file)
          File.rm(text_file)
        end

      {:error, reason} ->
        IO.puts("Failed to read PDF file: #{inspect(reason)}")
    end
  end
end

PDFExtractionTest.run()
