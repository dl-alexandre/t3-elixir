defmodule T3.OAuthTest do
  use ExUnit.Case, async: true
  alias T3.{OAuth, Error}

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.TestFixture, owner: self()}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    {:ok,
     client: T3.new(url: "http://127.0.0.1:#{port}/json"), origin: "http://127.0.0.1:#{port}"}
  end

  test "discovers, registers, pins read-only scope and exchanges PKCE code", %{
    client: client,
    origin: origin
  } do
    assert {:ok, flow} = OAuth.begin(client, redirect_uri: "http://127.0.0.1:8080/callback")
    query = flow.authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["scope"] == "orchestration:read"
    assert query["code_challenge_method"] == "S256"

    callback =
      "http://127.0.0.1:8080/callback?" <>
        URI.encode_query(%{state: query["state"], code: "code", iss: origin})

    assert {:ok, token} = OAuth.complete(flow, callback)
    refute inspect(token) =~ "fixture-token"
    {:ok, connected} = T3.connect(%{client | token: token.access_token})

    try do
      assert {:ok, _} = T3.Threads.list(connected, %{"projectId" => "project-1"})
    after
      T3.Client.close(connected)
    end
  end

  test "rejects state, issuer and callback mismatches before exchange", %{client: client} do
    {:ok, flow} = OAuth.begin(client, redirect_uri: "http://127.0.0.1:8080/callback")

    assert {:error, %Error{kind: :oauth}} =
             OAuth.complete(flow, "http://127.0.0.1:8080/callback?state=wrong&code=code")

    assert {:error, %Error{kind: :oauth}} = OAuth.complete(flow, "http://localhost/elsewhere")
    query = flow.authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert {:error, %Error{kind: :oauth}} =
             OAuth.complete(
               flow,
               "http://127.0.0.1:8080/callback?" <>
                 URI.encode_query(%{
                   state: query["state"],
                   code: "code",
                   iss: "https://wrong.example"
                 })
             )

    refute_receive {:request, "POST", "/token", _, _}
  end

  test "loopback sign-in uses dependency listener and returns usable client", %{
    client: client,
    origin: origin
  } do
    finch = start_supervised!({Finch, name: __MODULE__})
    assert is_pid(finch)

    open = fn url ->
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      callback =
        query["redirect_uri"] <>
          "?" <> URI.encode_query(%{state: query["state"], code: "code", iss: origin})

      Task.start(fn -> Finch.build(:get, callback) |> Finch.request(__MODULE__) end)
    end

    {:ok, client} = T3.connect(%{client | token: "fixture-token"})
    assert {:ok, signed_in} = OAuth.login(client, open: open, timeout: 2000)
    refute Process.alive?(client.supervisor)
    refute signed_in.connected?
    refute is_nil(signed_in.token)
    refute inspect(signed_in) =~ "fixture-token"
  end
end
