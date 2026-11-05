defmodule T3.HTTP.Media do
  @moduledoc "Binary assets, attachment capability uploads and browser upload/download."
  @doc "Fetch an asset capability. Range headers can request byte ranges."
  def asset(client, token, filename, opts \\ []),
    do:
      T3.HTTP.Raw.call(
        client,
        :asset,
        Keyword.put(opts, :params, %{"token" => token, "fileName" => filename})
      )

  @doc "Upload exact bytes using the relative capability URL from MCP prepare_upload."
  defdelegate upload(client, relative_url, bytes, opts \\ []), to: T3.HTTP
  @doc "Fetch browser download bytes; query includes threadId, tabId and id."
  def preview_download(client, opts \\ []), do: T3.HTTP.Raw.call(client, :preview_download, opts)

  @doc "Answer a browser file picker with multipart files; query includes threadId, tabId and chooser."
  def preview_upload(client, multipart, opts \\ []),
    do: T3.HTTP.Raw.call(client, :preview_upload, Keyword.put(opts, :multipart, multipart))

  @doc "Submit OTLP JSON trace data. Requires orchestration operate scope."
  def traces(client, trace_data, opts \\ []),
    do: T3.HTTP.Raw.call(client, :otlp_traces, Keyword.put(opts, :json, trace_data))
end
