defmodule T3.HTTP do
  @moduledoc """
  Explicit HTTP access to T3's environment API, independent of the MCP session.

      http = T3.HTTP.new(base_url: "http://127.0.0.1:3773", token: access_token)
      T3.HTTP.Orchestration.thread_transcript(http, thread_id)
      T3.HTTP.call(http, :orchestration_thread_history_page,
        params: %{"threadId" => thread_id}, query: %{"cursor" => cursor})

  Successes return `{:ok, %T3.HTTP.Response{}}`; failures return `{:error,
  %T3.Error{}}`. Configure `:finch` for a custom supervised Finch pool; the SDK
  application starts `T3.HTTP.Finch` by default. Credentials need the endpoint's
  own scopes: the presence of an MCP token does not imply HTTP authorization.

  JSON routes accept `json: wire_map`, token exchanges accept `form: wire_map`,
  and uploads/webhooks accept `body: exact_bytes`. Payload schemas remain T3's
  responsibility. There are no automatic retries, redirects or cookie storage.
  """
  alias T3.{Error, HTTP.Catalog, HTTP.Response}
  @derive {Inspect, only: [:base_url, :timeout, :max_body_bytes]}
  defstruct [
    :base_url,
    :token,
    finch: T3.HTTP.Finch,
    timeout: 30_000,
    pool_timeout: 5_000,
    auth_scheme: "Bearer",
    max_body_bytes: 16_777_216,
    headers: []
  ]

  @type t :: %__MODULE__{}
  @methods [:get, :post, :put, :patch, :delete, :head, :options]

  @doc "Create an HTTP configuration. Requires an origin URL, HTTPS or loopback HTTP."
  def new(opts) do
    origin = Keyword.fetch!(opts, :base_url)
    uri = URI.parse(origin)

    safe_scheme =
      uri.scheme == "https" or
        (uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1", "::1"])

    unless safe_scheme and is_binary(uri.host) and uri.host != "" and
             uri.userinfo == nil and uri.query == nil and uri.fragment == nil and
             uri.path in [nil, "", "/"] do
      raise ArgumentError,
            "base_url must be an HTTPS or loopback HTTP origin without credentials, path, query or fragment"
    end

    client = struct!(__MODULE__, Keyword.put(opts, :base_url, String.trim_trailing(origin, "/")))

    for field <- [:timeout, :pool_timeout, :max_body_bytes] do
      unless is_integer(Map.fetch!(client, field)) and Map.fetch!(client, field) > 0,
        do: raise(ArgumentError, "#{field} must be a positive integer")
    end

    unless client.auth_scheme in ["Bearer", "DPoP"],
      do: raise(ArgumentError, "auth_scheme must be Bearer or DPoP")

    normalize_headers(client.headers)
    client
  end

  @doc "Return every declared HTTP endpoint."
  defdelegate endpoints(), to: Catalog, as: :all

  @doc "Call a declared endpoint using :params, :query, :json, :form, :body and :headers options."
  def call(client, endpoint, opts \\ []) do
    case Catalog.fetch(endpoint) do
      nil ->
        invalid("unknown HTTP endpoint")

      spec ->
        with {:ok, path} <- expand_path(spec.path, Keyword.get(opts, :params, %{})) do
          opts = prepare_encoding(spec, opts)
          request(client, spec.method, path, opts)
        end
    end
  end

  @doc """
  Send one same-origin HTTP request. Relative root paths only; absolute URLs and
  network-path references are rejected so bearer credentials cannot cross origins.
  `:decode` may be `:auto` (default), `:json`, or `:binary`. Response bodies are
  bounded by `max_body_bytes`; receive and pool timeouts are bounded too.
  """
  def request(%__MODULE__{} = client, method, path, opts \\ [])
      when method in @methods and is_binary(path) do
    with :ok <- safe_path(path),
         {:ok, body, content_type} <- encode_body(opts),
         {:ok, headers} <- request_headers(client, opts, content_type) do
      query = Keyword.get(opts, :query, %{})
      url = client.base_url <> path <> query_suffix(query, path)
      req = Finch.build(method, url, headers, body)
      timeout = Keyword.get(opts, :timeout, client.timeout)
      limit = Keyword.get(opts, :max_body_bytes, client.max_body_bytes)

      unless is_integer(timeout) and timeout > 0 and is_integer(limit) and limit > 0,
        do: raise(ArgumentError, "timeout and max_body_bytes must be positive integers")

      result =
        Finch.stream_while(
          req,
          client.finch,
          %{status: nil, headers: [], body: [], bytes: 0},
          fn
            {:status, status}, acc ->
              {:cont, %{acc | status: status}}

            {:headers, values}, acc ->
              {:cont, %{acc | headers: acc.headers ++ values}}

            {:data, data}, acc ->
              bytes = acc.bytes + byte_size(data)

              if bytes > limit,
                do: {:halt, Map.put(acc, :too_large, true)},
                else: {:cont, %{acc | bytes: bytes, body: [data | acc.body]}}

            _, acc ->
              {:cont, acc}
          end,
          receive_timeout: timeout,
          pool_timeout: client.pool_timeout,
          request_timeout: timeout
        )

      finish(result, Keyword.get(opts, :decode, :auto))
    end
  rescue
    error in [ArgumentError, RuntimeError] ->
      {:error,
       %Error{kind: :configuration, message: "invalid HTTP configuration", details: error}}
  catch
    :exit, reason ->
      {:error, %Error{kind: :transport, message: "HTTP connection unavailable", details: reason}}
  end

  @doc false
  def prepare_request(%__MODULE__{} = client, method, path, opts)
      when method in @methods and is_binary(path) do
    with :ok <- safe_path(path),
         {:ok, body, content_type} <- encode_body(opts),
         {:ok, headers} <- request_headers(client, opts, content_type) do
      {:ok,
       Finch.build(
         method,
         client.base_url <> path <> query_suffix(Keyword.get(opts, :query, %{}), path),
         headers,
         body
       )}
    end
  end

  @doc "Stream a response with synchronous callback backpressure; see T3.HTTP.Stream."
  defdelegate stream(client, method, path, callback, opts \\ []), to: T3.HTTP.Stream, as: :run

  @doc "Start a cancellable streaming Task owned by the calling process."
  defdelegate start_stream(client, method, path, callback, opts \\ []),
    to: T3.HTTP.Stream,
    as: :start

  @doc "Cancel a streaming Task owned by this process and close its network worker."
  defdelegate cancel_stream(task), to: T3.HTTP.Stream, as: :cancel

  @doc "Routes implemented outside EnvironmentHttpApi, including guest/device/media APIs."
  defdelegate raw_endpoints(), to: T3.HTTP.Raw, as: :endpoints

  @doc "Build a multipart body from string fields and local-file or in-memory file tuples."
  defdelegate multipart(fields, files \\ []), to: T3.HTTP.Multipart, as: :build

  @doc "POST exact attachment bytes to the relative URL returned by t3_attachment_prepare_upload."
  def upload(client, relative_url, bytes, opts \\ []) when is_binary(bytes),
    do:
      request(
        client,
        :post,
        relative_url,
        Keyword.merge([body: bytes, content_type: "application/octet-stream"], opts)
      )

  defp safe_path(path) do
    uri = URI.parse(path)

    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") and
         uri.scheme == nil and uri.host == nil and uri.fragment == nil and
         not String.contains?(path, ["\r", "\n", "\\"]) do
      :ok
    else
      invalid("HTTP paths must be same-origin root paths without fragments")
    end
  end

  defp expand_path(template, params) when is_map(params) do
    Enum.reduce_while(
      Regex.scan(~r/:([A-Za-z][A-Za-z0-9]*)/, template, capture: :all_but_first),
      {:ok, template},
      fn [key], {:ok, path} ->
        case Map.fetch(params, key) do
          {:ok, value} when is_binary(value) and value != "" ->
            encoded = URI.encode(value, &URI.char_unreserved?/1)
            {:cont, {:ok, String.replace(path, ":" <> key, encoded)}}

          _ ->
            {:halt, invalid("missing path parameter #{key}")}
        end
      end
    )
  end

  defp expand_path(_, _), do: invalid("path params must be a string-keyed map")

  defp prepare_encoding(spec, opts) do
    opts = Keyword.delete(opts, :params)

    opts =
      if spec.orchestration_protocol do
        headers = [{"x-t3-orchestration-protocol", "2"} | Keyword.get(opts, :headers, [])]
        Keyword.put(opts, :headers, headers)
      else
        opts
      end

    case spec.encoding do
      :json -> Keyword.put_new(opts, :json, %{})
      :form -> Keyword.put_new(opts, :form, %{})
      _ -> opts
    end
  end

  defp encode_body(opts) do
    encodings = Enum.filter([:json, :form, :body, :multipart], &Keyword.has_key?(opts, &1))

    case encodings do
      [] ->
        {:ok, nil, nil}

      [:json] ->
        {:ok, JSON.encode!(Keyword.fetch!(opts, :json)), "application/json"}

      [:form] ->
        {:ok, URI.encode_query(Keyword.fetch!(opts, :form)), "application/x-www-form-urlencoded"}

      [:multipart] ->
        case Keyword.fetch!(opts, :multipart) do
          %Multipart{} = multipart ->
            {:ok, {:stream, Multipart.body_stream(multipart)},
             Multipart.content_type(multipart, "multipart/form-data")}

          _ ->
            invalid(":multipart must be a Multipart value")
        end

      [:body] ->
        body = Keyword.fetch!(opts, :body)

        if is_binary(body),
          do: {:ok, body, Keyword.get(opts, :content_type, "application/octet-stream")},
          else: invalid("raw body must be binary")

      _ ->
        invalid("choose only one of :json, :form, :body or :multipart")
    end
  end

  defp request_headers(client, opts, content_type) do
    headers = normalize_headers(client.headers ++ Keyword.get(opts, :headers, []))

    if Enum.any?(headers, fn {key, _} ->
         key in ["authorization", "host", "content-length", "transfer-encoding"]
       end) do
      invalid(
        "use :token for Authorization; routing and framing headers are managed by the client"
      )
    else
      headers =
        if content_type,
          do: [
            {"content-type", content_type}
            | Enum.reject(headers, &(elem(&1, 0) == "content-type"))
          ],
          else: headers

      headers =
        if client.token,
          do: [{"authorization", client.auth_scheme <> " " <> expose(client.token)} | headers],
          else: headers

      {:ok, headers}
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {name, value} ->
      name = String.downcase(to_string(name))
      value = to_string(value)

      if String.contains?(name <> value, ["\r", "\n"]),
        do: raise(ArgumentError, "invalid HTTP header")

      {name, value}
    end)
  end

  defp normalize_headers(_), do: raise(ArgumentError, "headers must be a list of pairs")
  defp expose(%ConduitMcp.Client.Secret{} = value), do: ConduitMcp.Client.Secret.expose(value)
  defp expose(value) when is_binary(value), do: value
  defp query_suffix(query, _) when query in [%{}, []], do: ""

  defp query_suffix(query, path),
    do: if(String.contains?(path, "?"), do: "&", else: "?") <> URI.encode_query(query)

  defp finish({:ok, %{too_large: true}}, _),
    do: {:error, %Error{kind: :protocol, message: "HTTP response exceeded max_body_bytes"}}

  defp finish({:ok, acc}, decode) do
    body = acc.body |> Enum.reverse() |> IO.iodata_to_binary()

    with {:ok, body} <- decode_body(body, acc.headers, decode) do
      response = %Response{status: acc.status, headers: acc.headers, body: body}

      if acc.status in 200..299,
        do: {:ok, response},
        else:
          {:error,
           %Error{
             kind: :http,
             code: acc.status,
             message: "T3 HTTP #{acc.status}",
             details: response
           }}
    end
  end

  defp finish({:error, reason, _acc}, decode), do: finish({:error, reason}, decode)

  defp finish({:error, reason}, _),
    do: {:error, %Error{kind: :transport, message: "T3 HTTP request failed", details: reason}}

  defp decode_body("", _, _), do: {:ok, nil}

  defp decode_body(body, headers, mode) do
    json? =
      mode == :json or
        (mode == :auto and
           Enum.any?(headers, fn {k, v} ->
             String.downcase(k) == "content-type" and
               (String.contains?(v, "application/json") or String.contains?(v, "+json"))
           end))

    if json? do
      case JSON.decode(body) do
        {:ok, decoded} ->
          {:ok, decoded}

        {:error, reason} ->
          {:error,
           %Error{kind: :protocol, message: "invalid HTTP JSON response", details: reason}}
      end
    else
      {:ok, body}
    end
  end

  defp invalid(message), do: {:error, %Error{kind: :configuration, message: message}}
end
