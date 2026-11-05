defmodule T3.HTTP.Response do
  @moduledoc """
  An HTTP success, including raw headers and a JSON-decoded or binary body.

  Bodies/headers can contain credentials from authentication routes; Inspect
  intentionally shows only status. A redirect is returned as an HTTP error,
  never followed automatically. No cookie jar is maintained.
  """
  @derive {Inspect, only: [:status]}
  defstruct [:status, :headers, :body]
  @type t :: %__MODULE__{status: integer(), headers: [{binary(), binary()}], body: term()}
end
