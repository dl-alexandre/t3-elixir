defmodule T3.HTTP.Webhooks do
  @moduledoc "Named access to T3 HTTP webhooks routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "POST `/api/hooks/:hookId/:token`. Body encoding: raw."
  def post(client, param_hookId, param_token, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :webhooks_post,
        Keyword.put(opts, :params, %{"hookId" => param_hookId, "token" => param_token})
      )

  @doc "PUT `/api/hooks/:hookId/:token`. Body encoding: raw."
  def put(client, param_hookId, param_token, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :webhooks_put,
        Keyword.put(opts, :params, %{"hookId" => param_hookId, "token" => param_token})
      )

  @doc "PATCH `/api/hooks/:hookId/:token`. Body encoding: raw."
  def patch(client, param_hookId, param_token, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :webhooks_patch,
        Keyword.put(opts, :params, %{"hookId" => param_hookId, "token" => param_token})
      )

  @doc "GET `/api/hooks/:hookId/:token`. Body encoding: raw."
  def get(client, param_hookId, param_token, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :webhooks_get,
        Keyword.put(opts, :params, %{"hookId" => param_hookId, "token" => param_token})
      )
end
