defmodule LiveAiChat.MhtConverter.Remote do
  @moduledoc """
  Remote adapter that POSTs MHT/MHTML to a conversion service and returns PDF bytes.

  Configuration (runtime):
    - :mht_converter_url (env: MHT_CONVERTER_URL) - required
    - :mht_converter_headers (keyword map) - optional
    - :mht_converter_timeout_ms (integer) - optional, default 60_000
  """

  @behaviour LiveAiChat.MhtConverter

  require Logger

  alias LiveAiChat.FileStorage

  @impl true
  def convert(mht_filename, mht_binary) do
    url =
      Application.get_env(:live_ai_chat, :mht_converter_url) ||
        System.get_env("MHT_CONVERTER_URL")

    if is_nil(url) or url == "" do
      Logger.error(
        "MHT converter URL not configured. Set :mht_converter_url or MHT_CONVERTER_URL"
      )

      {:error, :converter_url_not_configured}
    else
      timeout = Application.get_env(:live_ai_chat, :mht_converter_timeout_ms, 60_000)
      headers = build_headers()

      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "mht2pdf_" <> Integer.to_string(System.unique_integer()) <> ".mht"
        )

      try do
        File.write!(tmp_path, mht_binary)

        # Use curl for robust multipart file upload compatible with your converter
        header_args = Enum.flat_map(headers, fn {k, v} -> ["-H", "#{k}: #{v}"] end)

        args =
          [
            "-sS",
            "--max-time",
            to_string(div(timeout, 1000)),
            "-f",
            "-X",
            "POST",
            "-F",
            "file=@#{tmp_path}"
          ] ++ header_args ++ [url, "-o", "-"]

        case System.cmd("curl", args, stderr_to_stdout: true) do
          {pdf_bytes, 0} ->
            case ensure_pdf_response(pdf_bytes, [{"content-type", "application/pdf"}]) do
              {:ok, bytes} ->
                pdf_filename = default_pdf_name(mht_filename)
                {:ok, %{pdf_filename: FileStorage.safe_filename(pdf_filename), pdf_binary: bytes}}

              {:error, reason} ->
                {:error, reason}
            end

          {error_output, exit_code} ->
            Logger.error(
              "MHT converter curl failed (exit #{exit_code}): #{truncate(error_output)}"
            )

            {:error, {:curl_error, exit_code}}
        end
      after
        # best-effort cleanup
        _ = File.rm(tmp_path)
      end
    end
  end

  defp default_pdf_name(mht_filename) do
    base = mht_filename |> Path.basename() |> Path.rootname()
    base <> ".pdf"
  end

  defp ensure_pdf_response(body, headers) when is_binary(body) do
    content_type = get_header(headers, "content-type")

    cond do
      byte_size(body) == 0 ->
        {:error, :empty_pdf}

      content_type && String.contains?(String.downcase(content_type), "application/pdf") ->
        {:ok, body}

      # some services may omit content-type; accept non-empty
      true ->
        {:ok, body}
    end
  end

  defp get_header(headers, key) do
    headers
    |> Enum.find_value(fn {k, v} ->
      if String.downcase(k) == String.downcase(key), do: v, else: nil
    end)
  end

  defp build_headers do
    # Do not set Content-Type here; Req sets multipart boundary for form uploads.
    Application.get_env(:live_ai_chat, :mht_converter_headers, [])
  end

  defp truncate(body, max \\ 200) do
    case body do
      binary when is_binary(binary) and byte_size(binary) > max ->
        binary_part(binary, 0, max) <> "..."

      other ->
        other
    end
  end
end
