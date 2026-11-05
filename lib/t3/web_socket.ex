defmodule T3.WebSocket do
  @moduledoc """
  Raw WebSocket transport for T3's non-Effect media/device routes.

  Text and binary frames are delivered unchanged as
  `{:t3_web_socket, socket, delivery_ref, {:text | :binary, bytes}}`. Call
  `ack/2` after consuming each delivery. This acknowledgement only releases the
  local backlog; route-specific acknowledgements (for example preview's JSON
  `{"type":"ack"}`) must also be sent to the server. See `T3.WebSocket.Routes`.

  Credentials are explicit: `:token` adds Authorization, `:ticket` adds wsTicket,
  and `:headers`/`:query` admit other route-specific inputs. No authentication is
  inferred from an MCP client. WSS is required except on loopback. A credential
  is sent only to the configured URL; redirects are never followed.

  Options: `:owner` (defaults to starter), `:connect_timeout` (10 seconds),
  `:idle_timeout` (60 seconds; `:infinity` allowed), `:lifetime` (`:infinity`),
  `:max_message_bytes` (16 MiB), `:max_pending_frames` (16), and
  `:max_pending_bytes` (32 MiB). Exceeding an input/backlog bound closes the
  connection and reports an error rather than accumulating unbounded mail.
  Ping frames receive automatic pongs. Owner death closes the connection.
  Server-close messages are `{:t3_web_socket, socket, {:closed, reason}}`;
  failures additionally send `{:t3_web_socket, socket, {:error, %T3.Error{}}}`.
  """
  use GenServer
  alias T3.Error

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    opts = Keyword.put_new(opts, :owner, self())
    with {:ok, _, _, _} <- options(opts), do: GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Send a literal text frame. No JSON encoding or protocol envelope is added."
  def send_text(socket, data) when is_binary(data), do: invoke(socket, {:send, {:text, data}})
  @doc "Send literal binary bytes, such as a route-specific control/video payload."
  def send_binary(socket, data) when is_binary(data), do: invoke(socket, {:send, {:binary, data}})
  @doc "Encode a value as JSON and send it in a text frame."
  def send_json(socket, value) do
    send_text(socket, JSON.encode!(value))
  rescue
    _ in [Protocol.UndefinedError, ArgumentError] ->
      error(:configuration, "value cannot be encoded as JSON")
  end

  def ping(socket, data \\ "") when is_binary(data), do: invoke(socket, {:send, {:ping, data}})
  def pong(socket, data \\ "") when is_binary(data), do: invoke(socket, {:send, {:pong, data}})
  @doc "Release a consumed delivery from the local backlog; sends nothing to the server."
  def ack(socket, delivery_ref), do: invoke(socket, {:ack, delivery_ref})
  @doc "Close the socket and release resources. Safe to call repeatedly."
  def close(socket) do
    case invoke(socket, :close) do
      {:error, %Error{kind: :closed}} -> :ok
      result -> result
    end
  end

  defp invoke(socket, message) do
    GenServer.call(socket, message, :infinity)
  catch
    :exit, _ -> error(:closed, "WebSocket is closed")
  end

  @impl true
  def init(opts) do
    timeout = Keyword.get(opts, :connect_timeout, 10_000)

    with {:ok, uri, path, headers} <- options(opts),
         {:ok, conn} <-
           Mint.HTTP.connect(if(uri.scheme == "wss", do: :https, else: :http), uri.host, uri.port,
             protocols: [:http1],
             transport_opts: [timeout: timeout]
           ),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(
             if(uri.scheme == "wss", do: :wss, else: :ws),
             conn,
             path,
             headers
           ),
         {:ok, conn, ws, data} <-
           handshake(conn, ref, System.monotonic_time(:millisecond) + timeout, nil, []) do
      state = %{
        conn: conn,
        ws: ws,
        ref: ref,
        owner: opts[:owner],
        owner_monitor: Process.monitor(opts[:owner]),
        pending: %{},
        pending_bytes: 0,
        notified?: false,
        max_message_bytes: Keyword.get(opts, :max_message_bytes, 16 * 1024 * 1024),
        max_pending_frames: Keyword.get(opts, :max_pending_frames, 16),
        max_pending_bytes: Keyword.get(opts, :max_pending_bytes, 32 * 1024 * 1024),
        idle_timeout: Keyword.get(opts, :idle_timeout, 60_000),
        idle_timer: nil,
        lifetime_timer: timer(Keyword.get(opts, :lifetime, :infinity), :lifetime)
      }

      if data != [], do: send(self(), {:initial_data, data})
      {:ok, reset_idle(state)}
    else
      {:error, %Error{} = error} ->
        {:stop, error}

      {:error, conn, _} ->
        Mint.HTTP.close(conn)
        {:stop, %Error{kind: :transport, message: "WebSocket connection failed"}}

      {:error, _} ->
        {:stop, %Error{kind: :transport, message: "WebSocket connection failed"}}
    end
  end

  defp options(opts) do
    uri = URI.parse(Keyword.fetch!(opts, :url))
    headers = Keyword.get(opts, :headers, [])
    query = Keyword.get(opts, :query, %{})

    cond do
      Enum.any?(
        [:connect_timeout, :max_message_bytes, :max_pending_frames, :max_pending_bytes],
        fn key -> not positive?(Keyword.get(opts, key, 1)) end
      ) ->
        error(:configuration, "WebSocket limits must be positive integers")

      Enum.any?([:idle_timeout, :lifetime], fn key ->
        value = Keyword.get(opts, key, :infinity)
        value != :infinity and not positive?(value)
      end) ->
        error(:configuration, "WebSocket deadlines must be positive integers or :infinity")

      not is_pid(opts[:owner]) ->
        error(:configuration, "WebSocket owner must be a PID")

      uri.scheme not in ["ws", "wss"] or is_nil(uri.host) or uri.userinfo != nil or
        uri.fragment != nil or uri.query != nil ->
        error(
          :configuration,
          "WebSocket URL must be absolute ws/wss; pass query and credentials separately"
        )

      uri.scheme == "ws" and uri.host not in ["localhost", "127.0.0.1", "::1"] ->
        error(:configuration, "use WSS or loopback WS")

      not valid_headers?(headers) ->
        error(:configuration, "invalid or reserved WebSocket headers")

      not is_map(query) ->
        error(:configuration, "WebSocket :query must be a map")

      opts[:token] != nil and opts[:ticket] != nil ->
        error(:configuration, "choose a WebSocket token or ticket")

      opts[:token] != nil and
          Enum.any?(headers, fn {key, _} -> String.downcase(key) == "authorization" end) ->
        error(:configuration, "conflicting WebSocket authorization")

      Keyword.get(opts, :auth_scheme, :bearer) not in [:bearer, :dpop] ->
        error(:configuration, "auth_scheme must be :bearer or :dpop")

      true ->
        query = Map.new(query, fn {key, value} -> {to_string(key), expose(value)} end)

        query =
          if opts[:ticket], do: Map.put(query, "wsTicket", expose(opts[:ticket])), else: query

        headers =
          if opts[:token],
            do: [
              {"authorization",
               if(Keyword.get(opts, :auth_scheme, :bearer) == :dpop, do: "DPoP ", else: "Bearer ") <>
                 expose(opts[:token])}
              | headers
            ],
            else: headers

        headers = if opts[:dpop], do: [{"dpop", expose(opts[:dpop])} | headers], else: headers
        path = if(uri.path in [nil, ""], do: "/", else: uri.path)
        path = if map_size(query) == 0, do: path, else: path <> "?" <> URI.encode_query(query)

        {:ok, %{uri | port: uri.port || if(uri.scheme == "wss", do: 443, else: 80)}, path,
         headers}
    end
  end

  defp positive?(value), do: is_integer(value) and value > 0

  defp valid_headers?(headers) when is_list(headers) do
    Enum.all?(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        not (String.downcase(key) in ["host", "connection", "upgrade", "proxy-authorization"] or
               String.starts_with?(String.downcase(key), "sec-websocket-")) and
          not String.contains?(key <> value, ["\r", "\n"])

      _ ->
        false
    end)
  end

  defp valid_headers?(_), do: false
  defp expose(%ConduitMcp.Client.Secret{} = secret), do: ConduitMcp.Client.Secret.expose(secret)
  defp expose(value), do: to_string(value)

  defp handshake(conn, ref, deadline, status, headers) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            status =
              Enum.find_value(responses, status, fn
                {:status, ^ref, value} -> value
                _ -> nil
              end)

            headers =
              Enum.find_value(responses, headers, fn
                {:headers, ^ref, value} -> value
                _ -> nil
              end)

            if Enum.member?(responses, {:done, ref}) do
              case Mint.WebSocket.new(conn, ref, status, headers) do
                {:ok, conn, ws} ->
                  {:ok, conn, ws, for({:data, ^ref, bytes} <- responses, do: bytes)}

                {:error, conn, _} ->
                  Mint.HTTP.close(conn)
                  error(:http, "WebSocket upgrade rejected", status)
              end
            else
              handshake(conn, ref, deadline, status, headers)
            end

          {:error, conn, _, _} ->
            Mint.HTTP.close(conn)
            error(:transport, "WebSocket handshake failed")

          :unknown ->
            handshake(conn, ref, deadline, status, headers)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Mint.HTTP.close(conn)
        error(:timeout, "WebSocket handshake timed out")
    end
  end

  @impl true
  def handle_call({:send, {_type, data} = frame}, _from, state) do
    if byte_size(data) > state.max_message_bytes do
      {:reply, error(:configuration, "outgoing WebSocket frame exceeds byte limit"), state}
    else
      case write(state, frame) do
        {:ok, state} ->
          {:reply, :ok, state}

        {:error, state} ->
          {:stop, :normal, error(:transport, "WebSocket send failed"),
           shutdown(state, :transport, "WebSocket send failed")}
      end
    end
  end

  def handle_call({:ack, ref}, _from, state) do
    case Map.pop(state.pending, ref) do
      {nil, _} ->
        {:reply, error(:protocol, "unknown WebSocket delivery"), state}

      {size, pending} ->
        {:reply, :ok, %{state | pending: pending, pending_bytes: state.pending_bytes - size}}
    end
  end

  def handle_call(:close, _from, state) do
    state = notify_closed(state, :normal)

    case write(state, :close) do
      {:ok, state} -> {:stop, :normal, :ok, state}
      {:error, state} -> {:stop, :normal, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:timer, kind, ref}, state) when kind in [:idle, :lifetime] do
    current = if kind == :idle, do: state.idle_timer, else: state.lifetime_timer

    if current && elem(current, 0) == ref do
      {:stop, :normal, shutdown(state, :timeout, "WebSocket #{kind} deadline exceeded")}
    else
      {:noreply, state}
    end
  end

  def handle_info({:initial_data, data}, state), do: process_data(state, data)

  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        data = for {:data, _, bytes} <- responses, do: bytes

        if Enum.any?(responses, &match?({:error, _, _}, &1)) do
          {:stop, :normal,
           shutdown(%{state | conn: conn}, :transport, "WebSocket connection lost")}
        else
          process_data(%{state | conn: conn}, data)
        end

      {:error, conn, _, _} ->
        {:stop, :normal, shutdown(%{state | conn: conn}, :transport, "WebSocket connection lost")}

      :unknown ->
        {:noreply, state}
    end
  end

  defp process_data(state, data) do
    Enum.reduce_while(data, {:noreply, state}, fn bytes, {:noreply, state} ->
      if byte_size(bytes) > state.max_message_bytes + 4096 do
        {:halt,
         {:stop, :normal,
          shutdown(state, :protocol, "WebSocket receive buffer exceeds byte limit")}}
      else
        case Mint.WebSocket.decode(state.ws, bytes) do
          {:ok, ws, frames} ->
            # Mint retains partial frames/fragments; cap that retained structure too.
            if retained_bytes(ws) > state.max_message_bytes + 14 do
              {:halt,
               {:stop, :normal,
                shutdown(
                  %{state | ws: ws},
                  :protocol,
                  "WebSocket partial message exceeds byte limit"
                )}}
            else
              case process_frames(reset_idle(%{state | ws: ws}), frames) do
                {:noreply, _} = result -> {:cont, result}
                result -> {:halt, result}
              end
            end

          {:error, ws, _} ->
            {:halt,
             {:stop, :normal, shutdown(%{state | ws: ws}, :protocol, "invalid WebSocket frame")}}
        end
      end
    end)
  end

  # Count retained payload bytes, allowing only a maximum WebSocket header (14
  # bytes) above the configured payload limit. A fragmented message is checked
  # before a final fragment arrives, not merely after Mint emits the message.
  defp retained_bytes(ws), do: byte_size(ws.buffer) + binary_bytes(ws.fragment)
  defp binary_bytes(value) when is_binary(value), do: byte_size(value)

  defp binary_bytes(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.reduce(0, &(binary_bytes(&1) + &2))

  defp binary_bytes(_), do: 0

  defp process_frames(state, frames) do
    Enum.reduce_while(frames, {:noreply, state}, fn
      {type, bytes}, {:noreply, state} when type in [:text, :binary] ->
        size = byte_size(bytes)

        cond do
          size > state.max_message_bytes ->
            {:halt,
             {:stop, :normal, shutdown(state, :protocol, "WebSocket message exceeds byte limit")}}

          map_size(state.pending) >= state.max_pending_frames or
              state.pending_bytes + size > state.max_pending_bytes ->
            {:halt,
             {:stop, :normal,
              shutdown(state, :overloaded, "WebSocket owner backlog exceeds limit")}}

          true ->
            ref = make_ref()
            send(state.owner, {:t3_web_socket, self(), ref, {type, bytes}})

            {:cont,
             {:noreply,
              %{
                state
                | pending: Map.put(state.pending, ref, size),
                  pending_bytes: state.pending_bytes + size
              }}}
        end

      {:ping, bytes}, {:noreply, state} ->
        case write(state, {:pong, bytes}) do
          {:ok, state} ->
            {:cont, {:noreply, state}}

          {:error, state} ->
            {:halt, {:stop, :normal, shutdown(state, :transport, "WebSocket pong failed")}}
        end

      {:pong, _}, {:noreply, state} ->
        {:cont, {:noreply, state}}

      {:close, code, reason}, {:noreply, state} ->
        {:halt, {:stop, :normal, notify_closed(state, {code, reason})}}

      _, {:noreply, state} ->
        {:halt, {:stop, :normal, shutdown(state, :protocol, "invalid WebSocket message")}}
    end)
  end

  defp write(state, frame) do
    with {:ok, ws, bytes} <- Mint.WebSocket.encode(state.ws, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, bytes) do
      {:ok, %{state | conn: conn, ws: ws}}
    else
      _ -> {:error, state}
    end
  end

  defp timer(:infinity, _), do: nil

  defp timer(timeout, kind) do
    ref = make_ref()
    {ref, Process.send_after(self(), {:timer, kind, ref}, timeout)}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer({_ref, timer}), do: Process.cancel_timer(timer)

  defp reset_idle(state) do
    cancel_timer(state.idle_timer)
    %{state | idle_timer: timer(state.idle_timeout, :idle)}
  end

  defp shutdown(state, kind, message) do
    send(state.owner, {:t3_web_socket, self(), {:error, %Error{kind: kind, message: message}}})
    notify_closed(state, :error)
  end

  defp notify_closed(%{notified?: true} = state, _), do: state

  defp notify_closed(state, reason) do
    send(state.owner, {:t3_web_socket, self(), {:closed, reason}})
    %{state | notified?: true}
  end

  defp error(kind, message, code \\ nil),
    do: {:error, %Error{kind: kind, message: message, code: code}}

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.idle_timer)
    cancel_timer(state.lifetime_timer)
    Mint.HTTP.close(state.conn)
  end

  @impl true
  def format_status(status),
    do: %{status | state: %{connection: :redacted}, message: :redacted, reason: :redacted}
end
