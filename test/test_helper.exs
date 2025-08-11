ExUnit.start()

Mox.defmock(LiveAiChat.AIClientMock, for: LiveAiChat.AIClient)

# Mock for Gemini AI client specifically used in extractor tests
defmodule LiveAiChat.AIClient.GeminiBehaviour do
  @callback get_completion(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback extract_document_content(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
end

Mox.defmock(LiveAiChat.AIClient.GeminiMock, for: LiveAiChat.AIClient.GeminiBehaviour)
