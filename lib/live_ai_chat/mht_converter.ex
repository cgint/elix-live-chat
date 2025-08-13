defmodule LiveAiChat.MhtConverter do
  @moduledoc """
  Interface for converting MHT/MHTML files to PDF via a pluggable adapter.

  By default uses `LiveAiChat.MhtConverter.Remote`, which calls an external
  HTTP service configured via the environment variable `MHT_CONVERTER_URL`.
  """

  @type filename :: String.t()
  @type bytes :: binary()

  @callback convert(filename, bytes) ::
              {:ok, %{pdf_filename: filename, pdf_binary: bytes}} | {:error, term()}

  @doc """
  Convert the given MHT/MHTML bytes to a PDF, returning the PDF filename and bytes.
  """
  @spec convert(filename, bytes) ::
          {:ok, %{pdf_filename: filename, pdf_binary: bytes}} | {:error, term()}
  def convert(mht_filename, mht_binary) do
    adapter = Application.get_env(:live_ai_chat, :mht_converter, LiveAiChat.MhtConverter.Remote)
    adapter.convert(mht_filename, mht_binary)
  end
end
