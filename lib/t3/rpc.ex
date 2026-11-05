defmodule T3.RPC do
  @moduledoc """
  Supervised WebSocket client for T3's Effect RPC protocol (`/ws`).

  This is a separate authentication audience from MCP. Supply an environment
  access token (`:token`) or an RPC WebSocket ticket (`:ticket`), not an MCP OAuth
  token. T3 rejects MCP client credentials on this surface. `:dpop` accepts a
  caller-created proof for a proof-bound credential (token headers then use the
  `DPoP` authorization scheme; `:auth_scheme` can explicitly select it). Credentials
  never persist. `:max_pending` defaults to 128 and `:max_message_bytes` to 16 MiB.

  Obtain a route-bound ticket with an environment HTTP credential:

      http = T3.HTTP.new(base_url: "http://127.0.0.1:3773", token: environment_token)
      {:ok, response} = T3.HTTP.Auth.web_socket_ticket_for(http, "rpc")
      {:ok, rpc} = T3.RPC.start_link(
        url: "ws://127.0.0.1:3773/ws", ticket: response.body["ticket"]
      )

  For proof-bound tickets supply a new DPoP proof that hashes that ticket. The SDK
  transports caller-created proofs; it does not generate or manage signing keys.

      {:ok, rpc} = T3.RPC.start_link(url: "ws://127.0.0.1:3773/ws", token: token)
      {:ok, config} = T3.RPC.call(rpc, "server.getConfig", %{})
      {:ok, subscription} = T3.RPC.subscribe(rpc, "orchestration.subscribeShell", %{})
      # receive {:t3_rpc, subscription, {:chunk, values}}, process values, then:
      :ok = T3.RPC.ack(rpc, subscription)
      :ok = T3.RPC.unsubscribe(rpc, subscription)
      :ok = T3.RPC.close(rpc)

  Subscriptions use explicit acknowledgements: acknowledge each chunk after
  consuming it. This retains the server's back-pressure instead of buffering an
  unbounded event queue. Terminal messages are `{:t3_rpc, id, {:done, value}}` or
  `{:t3_rpc, id, {:error, error}}`. Subscriber death cancels its request.

  `call/4` defaults to a 30-second deadline. Subscription `:timeout` defaults to
  `:infinity`; pass milliseconds for a total deadline. No operation is replayed or
  retried after disconnect. Payloads and results retain the upstream string keys;
  `T3.RPC.Catalog` lists the pinned upstream methods and streaming flags.
  """
  use GenServer
  alias T3.Error

  @type subscription :: String.t()
  @type result :: {:ok, term()} | {:error, Error.t()}

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])

    with {:ok, _, _, _} <- connection_options(opts) do
      GenServer.start_link(__MODULE__, opts, gen_opts)
    end
  end

  @spec call(GenServer.server(), String.t(), term(), keyword()) :: result()
  def call(rpc, method, payload \\ %{}, opts \\ []),
    do: invoke(rpc, {:call, method, payload, opts})

  @spec subscribe(GenServer.server(), String.t(), term(), keyword()) ::
          {:ok, subscription()} | {:error, Error.t()}
  def subscribe(rpc, method, payload \\ %{}, opts \\ []),
    do: invoke(rpc, {:subscribe, method, payload, opts})

  @doc "Acknowledge the outstanding chunk of a subscription."
  def ack(rpc, id), do: invoke(rpc, {:ack, id})
  @doc "Interrupt a subscription and release its local state. Idempotent."
  def unsubscribe(rpc, id), do: invoke(rpc, {:unsubscribe, id})
  @doc "Reply to a server-originated request delivered to the configured :owner."
  def respond(rpc, id, {:ok, value}),
    do: invoke(rpc, {:respond, id, %{"_tag" => "Success", "value" => value}})

  def respond(rpc, id, {:error, error}),
    do:
      invoke(
        rpc,
        {:respond, id, %{"_tag" => "Failure", "cause" => [%{"_tag" => "Fail", "error" => error}]}}
      )

  def ping(rpc), do: invoke(rpc, :ping)
  def close(rpc), do: invoke(rpc, :close)

  defp invoke(rpc, message) do
    GenServer.call(rpc, message, :infinity)
  catch
    :exit, _ -> error(:closed, "RPC connection is closed")
  end

  @impl true
  def init(opts) do
    timeout = Keyword.get(opts, :connect_timeout, 10_000)

    with {:ok, uri, path, headers} <- connection_options(opts),
         {:ok, conn} <-
           Mint.HTTP.connect(if(uri.scheme == "wss", do: :https, else: :http), uri.host, uri.port,
             protocols: [:http1],
             transport_opts: [timeout: timeout]
           ),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(String.to_existing_atom(uri.scheme), conn, path, headers),
         {:ok, conn, ws, initial_data} <- handshake(conn, ref, timeout) do
      if initial_data != [], do: send(self(), {:rpc_initial_data, initial_data})

      {:ok,
       %{
         conn: conn,
         ws: ws,
         ref: ref,
         pending: %{},
         incoming: MapSet.new(),
         next_id: 1,
         owner: Keyword.get(opts, :owner),
         timeout: Keyword.get(opts, :timeout, 30_000),
         max_message_bytes: Keyword.get(opts, :max_message_bytes, 16 * 1024 * 1024),
         max_pending: Keyword.get(opts, :max_pending, 128)
       }}
    else
      {:error, %Error{} = error} ->
        {:stop, error}

      {:error, _reason} ->
        {:stop, %Error{kind: :transport, message: "RPC connection failed"}}

      {:error, conn, _reason} ->
        Mint.HTTP.close(conn)
        {:stop, %Error{kind: :transport, message: "RPC connection failed"}}
    end
  end

  defp connection_options(opts) do
    uri = URI.parse(Keyword.fetch!(opts, :url))

    cond do
      Enum.any?([:connect_timeout, :timeout, :max_message_bytes, :max_pending], fn key ->
        value = Keyword.get(opts, key, 1)
        not (is_integer(value) and value > 0)
      end) ->
        error(:configuration, "RPC connection limits must be positive integers")

      opts[:token] != nil and opts[:ticket] != nil ->
        error(:configuration, "choose one RPC token or ticket")

      Keyword.get(opts, :auth_scheme, :bearer) not in [:bearer, :dpop] ->
        error(:configuration, "RPC auth_scheme must be :bearer or :dpop")

      uri.scheme not in ["ws", "wss"] or is_nil(uri.host) or uri.userinfo != nil or
          uri.fragment != nil ->
        error(
          :configuration,
          "RPC URL must be an absolute ws/wss URL without credentials or fragment"
        )

      uri.scheme == "ws" and uri.host not in ["localhost", "127.0.0.1", "::1"] ->
        error(:configuration, "RPC credentials require WSS or loopback WS")

      not is_nil(uri.query) ->
        error(:configuration, "pass RPC ticket and protocol options separately from the URL")

      true ->
        query = %{"orchestrationProtocol" => to_string(Keyword.get(opts, :protocol_version, 2))}

        query =
          if opts[:ticket], do: Map.put(query, "wsTicket", expose(opts[:ticket])), else: query

        query = if opts[:dpop], do: Map.put(query, "dpop", expose(opts[:dpop])), else: query

        headers =
          if opts[:token],
            do: [
              {"authorization",
               if(
                 Keyword.get(opts, :auth_scheme, if(opts[:dpop], do: :dpop, else: :bearer)) ==
                   :dpop,
                 do: "DPoP ",
                 else: "Bearer "
               ) <> expose(opts[:token])}
            ],
            else: []

        headers = if opts[:dpop], do: [{"dpop", expose(opts[:dpop])} | headers], else: headers

        path =
          if(uri.path in [nil, ""], do: "/ws", else: uri.path) <> "?" <> URI.encode_query(query)

        {:ok, %{uri | port: uri.port || if(uri.scheme == "wss", do: 443, else: 80)}, path,
         headers}
    end
  end

  defp expose(%ConduitMcp.Client.Secret{} = value), do: ConduitMcp.Client.Secret.expose(value)
  defp expose(value) when is_binary(value), do: value

  defp handshake(conn, ref, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    handshake(conn, ref, deadline, nil, [])
  end

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
                  initial_data = for {:data, ^ref, data} <- responses, do: data
                  {:ok, conn, ws, initial_data}

                {:error, conn, _} ->
                  Mint.HTTP.close(conn)
                  error(:http, "RPC WebSocket upgrade rejected", status)
              end
            else
              handshake(conn, ref, deadline, status, headers)
            end

          {:error, conn, _, _} ->
            Mint.HTTP.close(conn)
            error(:transport, "RPC handshake failed")

          :unknown ->
            handshake(conn, ref, deadline, status, headers)
        end
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Mint.HTTP.close(conn)
        error(:timeout, "RPC handshake timed out")
    end
  end

  @impl true
  def handle_call({kind, method, payload, opts}, from, state) when kind in [:call, :subscribe] do
    timeout = Keyword.get(opts, :timeout, if(kind == :call, do: state.timeout, else: :infinity))
    owner = Keyword.get(opts, :owner, elem(from, 0))

    if map_size(state.pending) >= state.max_pending do
      {:reply, error(:overloaded, "RPC pending request limit reached"), state}
    else
      if ((is_integer(timeout) and timeout > 0) or timeout == :infinity) and is_pid(owner) and
           is_binary(method) do
        id = to_string(state.next_id)

        entry = %{
          kind: kind,
          from: from,
          owner: owner,
          monitor: Process.monitor(owner),
          timer:
            if(timeout == :infinity,
              do: nil,
              else: Process.send_after(self(), {:deadline, id}, timeout)
            ),
          outstanding: false
        }

        frame = %{
          "_tag" => "Request",
          "id" => id,
          "tag" => method,
          "payload" => payload,
          "headers" => Keyword.get(opts, :headers, [])
        }

        case send_frame(state, frame) do
          {:ok, state} ->
            state = %{
              state
              | pending: Map.put(state.pending, id, entry),
                next_id: state.next_id + 1
            }

            if kind == :subscribe, do: {:reply, {:ok, id}, state}, else: {:noreply, state}

          {:error, state} ->
            cleanup(entry)

            {:stop, :normal, error(:transport, "RPC send failed"),
             fail_all(state, :transport, "RPC send failed")}
        end
      else
        {:reply, error(:configuration, "invalid RPC request timeout, owner, or method"), state}
      end
    end
  end

  def handle_call({:ack, id}, _from, state) do
    case state.pending[id] do
      %{kind: :subscribe, outstanding: true} = entry ->
        case send_frame(state, %{"_tag" => "Ack", "requestId" => id}) do
          {:ok, state} ->
            {:reply, :ok, put_in(state.pending[id], %{entry | outstanding: false})}

          {:error, state} ->
            {:stop, :normal, error(:transport, "RPC acknowledgement failed"),
             fail_all(state, :transport, "RPC send failed")}
        end

      _ ->
        {:reply, error(:protocol, "no outstanding RPC chunk to acknowledge"), state}
    end
  end

  def handle_call({:unsubscribe, id}, _from, state) do
    {entry, pending} = Map.pop(state.pending, id)
    if entry, do: cleanup(entry)
    state = %{state | pending: pending}

    case send_frame(state, %{"_tag" => "Interrupt", "requestId" => id}) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, state} -> {:stop, :normal, :ok, fail_all(state, :transport, "RPC send failed")}
    end
  end

  def handle_call({:respond, id, exit}, _from, state) do
    if MapSet.member?(state.incoming, id) do
      case send_frame(state, %{"_tag" => "Exit", "requestId" => id, "exit" => exit}) do
        {:ok, state} ->
          {:reply, :ok, %{state | incoming: MapSet.delete(state.incoming, id)}}

        {:error, state} ->
          {:stop, :normal, error(:transport, "RPC reply failed"),
           fail_all(state, :transport, "RPC send failed")}
      end
    else
      {:reply, error(:protocol, "unknown server RPC request"), state}
    end
  end

  def handle_call(:ping, _from, state) do
    case send_frame(state, %{"_tag" => "Ping"}) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, state} ->
        {:stop, :normal, error(:transport, "RPC ping failed"),
         fail_all(state, :transport, "RPC send failed")}
    end
  end

  def handle_call(:close, _from, state) do
    state = fail_all(state, :closed, "RPC connection closed")

    case send_ws(state, :close) do
      {:ok, state} -> {:stop, :normal, :ok, state}
      {:error, state} -> {:stop, :normal, :ok, state}
    end
  end

  @impl true
  def handle_info({:deadline, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {entry, pending} ->
        deliver(entry, id, error(:timeout, "RPC request timed out"))
        cleanup(entry)
        state = %{state | pending: pending}

        case send_frame(state, %{"_tag" => "Interrupt", "requestId" => id}) do
          {:ok, state} -> {:noreply, state}
          {:error, state} -> {:stop, :normal, fail_all(state, :transport, "RPC send failed")}
        end
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state.pending
    |> Enum.filter(fn {_id, entry} -> entry.monitor == monitor end)
    |> Enum.reduce({:noreply, state}, fn {id, entry}, {:noreply, state} ->
      cleanup(entry)
      state = %{state | pending: Map.delete(state.pending, id)}

      case send_frame(state, %{"_tag" => "Interrupt", "requestId" => id}) do
        {:ok, state} -> {:noreply, state}
        {:error, state} -> {:noreply, fail_all(state, :transport, "RPC send failed")}
      end
    end)
  end

  def handle_info({:rpc_initial_data, data}, state) do
    process_responses(state, Enum.map(data, &{:data, state.ref, &1}))
  end

  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        process_responses(%{state | conn: conn}, responses)

      {:error, conn, _reason, _responses} ->
        {:stop, :normal, fail_all(%{state | conn: conn}, :transport, "RPC connection lost")}

      :unknown ->
        {:noreply, state}
    end
  end

  defp process_responses(state, responses) do
    Enum.reduce_while(responses, {:noreply, state}, fn
      {:data, _, data}, {:noreply, state} ->
        case Mint.WebSocket.decode(state.ws, data) do
          {:ok, ws, frames} ->
            if retained_bytes(ws) > state.max_message_bytes + 14 do
              {:halt,
               {:stop, :normal,
                fail_all(%{state | ws: ws}, :protocol, "RPC partial message exceeds byte limit")}}
            else
              case process_frames(%{state | ws: ws}, frames) do
                {:noreply, _} = result -> {:cont, result}
                result -> {:halt, result}
              end
            end

          {:error, ws, _reason} ->
            {:halt,
             {:stop, :normal, fail_all(%{state | ws: ws}, :protocol, "invalid WebSocket frame")}}
        end

      {:error, _, _}, {:noreply, state} ->
        {:halt, {:stop, :normal, fail_all(state, :transport, "RPC connection lost")}}

      _, result ->
        {:cont, result}
    end)
  end

  # Mint buffers unfinished frames/messages; bound those before a final fragment.
  defp retained_bytes(ws), do: byte_size(ws.buffer) + binary_bytes(ws.fragment)
  defp binary_bytes(value) when is_binary(value), do: byte_size(value)

  defp binary_bytes(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.reduce(0, &(binary_bytes(&1) + &2))

  defp binary_bytes(_), do: 0

  defp process_frames(state, frames) do
    Enum.reduce_while(frames, {:noreply, state}, fn frame, {:noreply, state} ->
      case frame do
        {kind, body}
        when kind in [:text, :binary] and byte_size(body) <= state.max_message_bytes ->
          case JSON.decode(body) do
            {:ok, messages} ->
              messages = if is_list(messages), do: messages, else: [messages]

              case process_messages(state, messages) do
                {:noreply, _} = result -> {:cont, result}
                result -> {:halt, result}
              end

            {:error, _} ->
              {:halt, {:stop, :normal, fail_all(state, :protocol, "invalid RPC JSON")}}
          end

        {:ping, body} ->
          case send_ws(state, {:pong, body}) do
            {:ok, state} ->
              {:cont, {:noreply, state}}

            {:error, state} ->
              {:halt, {:stop, :normal, fail_all(state, :transport, "RPC pong failed")}}
          end

        {:pong, _} ->
          {:cont, {:noreply, state}}

        {:close, _, _} ->
          {:halt, {:stop, :normal, fail_all(state, :closed, "RPC peer closed connection")}}

        :close ->
          {:halt, {:stop, :normal, fail_all(state, :closed, "RPC peer closed connection")}}

        _ ->
          {:halt,
           {:stop, :normal, fail_all(state, :protocol, "unsupported or oversized RPC frame")}}
      end
    end)
  end

  defp process_messages(state, messages) do
    Enum.reduce_while(messages, {:noreply, state}, fn message, {:noreply, state} ->
      case process_message(state, message) do
        {:ok, state} ->
          {:cont, {:noreply, state}}

        {:error, state} ->
          {:halt, {:stop, :normal, fail_all(state, :protocol, "invalid RPC message")}}
      end
    end)
  end

  defp process_message(state, %{"_tag" => "Chunk", "requestId" => id, "values" => values})
       when is_list(values) do
    case state.pending[id] do
      %{kind: :subscribe, outstanding: false} = entry ->
        send(entry.owner, {:t3_rpc, id, {:chunk, values}})
        {:ok, put_in(state.pending[id], %{entry | outstanding: true})}

      nil ->
        {:ok, state}

      _ ->
        {:error, state}
    end
  end

  defp process_message(state, %{"_tag" => "Exit", "requestId" => id, "exit" => exit}) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:ok, state}

      {entry, pending} ->
        result =
          case exit do
            %{"_tag" => "Success", "value" => value} ->
              {:ok, value}

            %{"_tag" => "Success"} ->
              {:ok, nil}

            %{"_tag" => "Failure", "cause" => cause} ->
              error(:rpc, "RPC request failed", nil, cause)

            _ ->
              error(:protocol, "invalid RPC exit")
          end

        cleanup(entry)
        deliver(entry, id, result)
        {:ok, %{state | pending: pending}}
    end
  end

  defp process_message(state, %{"_tag" => "Ping"}), do: send_frame(state, %{"_tag" => "Pong"})
  defp process_message(state, %{"_tag" => "Pong"}), do: {:ok, state}

  defp process_message(state, %{"_tag" => "Defect"} = message),
    do: {:ok, fail_all(state, :rpc, "RPC server defect", message)}

  defp process_message(state, %{"_tag" => "ClientProtocolError", "requestIds" => ids} = message)
       when is_list(ids) do
    state =
      Enum.reduce(ids, state, fn id, state ->
        case Map.pop(state.pending, id) do
          {nil, _} ->
            state

          {entry, pending} ->
            cleanup(entry)
            deliver(entry, id, error(:protocol, "RPC server rejected protocol", nil, message))
            %{state | pending: pending}
        end
      end)

    {:ok, state}
  end

  defp process_message(state, %{"_tag" => "ClientProtocolError"} = message),
    do: {:ok, fail_all(state, :protocol, "RPC server rejected protocol", message)}

  defp process_message(state, %{
         "_tag" => "Request",
         "id" => id,
         "tag" => method,
         "payload" => payload
       }) do
    if is_pid(state.owner) and MapSet.size(state.incoming) < state.max_pending do
      send(state.owner, {:t3_rpc_request, self(), id, method, payload})
      {:ok, %{state | incoming: MapSet.put(state.incoming, id)}}
    else
      send_frame(state, %{
        "_tag" => "Exit",
        "requestId" => id,
        "exit" => %{
          "_tag" => "Failure",
          "cause" => [
            %{"_tag" => "Fail", "error" => %{"message" => "no server request handler configured"}}
          ]
        }
      })
    end
  end

  defp process_message(state, _), do: {:error, state}

  defp deliver(%{kind: :call, from: from}, _id, result), do: GenServer.reply(from, result)
  defp deliver(%{owner: owner}, id, {:ok, value}), do: send(owner, {:t3_rpc, id, {:done, value}})

  defp deliver(%{owner: owner}, id, {:error, error}),
    do: send(owner, {:t3_rpc, id, {:error, error}})

  defp cleanup(entry) do
    if entry.timer, do: Process.cancel_timer(entry.timer)
    Process.demonitor(entry.monitor, [:flush])
  end

  defp fail_all(state, kind, message, details \\ nil) do
    Enum.each(state.pending, fn {id, entry} ->
      cleanup(entry)
      deliver(entry, id, error(kind, message, nil, details))
    end)

    %{state | pending: %{}}
  end

  defp send_frame(state, frame) do
    send_ws(state, {:text, JSON.encode!(frame)})
  rescue
    _ in [Protocol.UndefinedError, ArgumentError] -> {:error, state}
  end

  defp send_ws(state, frame) do
    with {:ok, ws, data} <- Mint.WebSocket.encode(state.ws, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
      {:ok, %{state | conn: conn, ws: ws}}
    else
      _ -> {:error, state}
    end
  end

  defp error(kind, message, code \\ nil, details \\ nil),
    do: {:error, %Error{kind: kind, message: message, code: code, details: details}}

  @impl true
  def terminate(_reason, state), do: Mint.HTTP.close(state.conn)
  @impl true
  def format_status(status),
    do: %{status | state: %{connection: :redacted}, message: :redacted, reason: :redacted}
end
