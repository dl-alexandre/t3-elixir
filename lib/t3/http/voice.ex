defmodule T3.HTTP.Voice do
  @moduledoc "Named access to T3 HTTP voice routes. Options accept wire-map JSON, raw bodies, query and headers."

  @doc "GET `/api/voice/cloud/keys`. Body encoding: none."
  def cloud_keys(client, opts \\ []), do: T3.HTTP.call(client, :voice_cloud_keys, opts)

  @doc "POST `/api/voice/cloud/:provider/key`. Body encoding: json."
  def set_cloud_key(client, provider, opts \\ []),
    do: call_with_provider(client, :voice_set_cloud_key, provider, opts)

  @doc "GET `/api/voice/cloud/openrouter/models`. Body encoding: none."
  def cloud_models(client, opts \\ []), do: T3.HTTP.call(client, :voice_cloud_models, opts)

  @doc "POST `/api/voice/cloud/:provider/transcribe`. Body encoding: raw."
  def transcribe_cloud(client, provider, opts \\ []),
    do: call_with_provider(client, :voice_transcribe_cloud, provider, opts)

  @doc "GET `/api/voice/status`. Body encoding: none."
  def status(client, opts \\ []), do: T3.HTTP.call(client, :voice_status, opts)

  @doc "POST `/api/voice/models/prepare`. Body encoding: none."
  def prepare_model(client, opts \\ []), do: T3.HTTP.call(client, :voice_prepare_model, opts)

  @doc "GET `/api/voice/models`. Body encoding: none."
  def models(client, opts \\ []), do: T3.HTTP.call(client, :voice_models, opts)

  @doc "POST `/api/voice/models/download`. Body encoding: json."
  def download_model(client, opts \\ []), do: T3.HTTP.call(client, :voice_download_model, opts)

  @doc "POST `/api/voice/models/select`. Body encoding: json."
  def select_model(client, opts \\ []), do: T3.HTTP.call(client, :voice_select_model, opts)

  @doc "POST `/api/voice/models/cancel`. Body encoding: json."
  def cancel_model_download(client, opts \\ []),
    do: T3.HTTP.call(client, :voice_cancel_model_download, opts)

  @doc "POST `/api/voice/models/remove`. Body encoding: json."
  def remove_model(client, opts \\ []), do: T3.HTTP.call(client, :voice_remove_model, opts)

  @doc "POST `/api/voice/models/link`. Body encoding: json."
  def link_models(client, opts \\ []), do: T3.HTTP.call(client, :voice_link_models, opts)

  @doc "POST `/api/voice/acceleration`. Body encoding: json."
  def update_acceleration(client, opts \\ []),
    do: T3.HTTP.call(client, :voice_update_acceleration, opts)

  @doc "POST `/api/voice/model-unload-timeout`. Body encoding: json."
  def update_model_unload_timeout(client, opts \\ []),
    do: T3.HTTP.call(client, :voice_update_model_unload_timeout, opts)

  @doc "POST `/api/voice/transcribe`. Body encoding: raw."
  def transcribe(client, opts \\ []), do: T3.HTTP.call(client, :voice_transcribe, opts)

  @doc "POST `/api/voice/post-process`. Body encoding: json."
  def post_process(client, opts \\ []), do: T3.HTTP.call(client, :voice_post_process, opts)

  defp call_with_provider(client, endpoint, provider, opts) do
    params = Map.put(Keyword.get(opts, :params, %{}), "provider", provider)
    T3.HTTP.call(client, endpoint, Keyword.put(opts, :params, params))
  end
end
