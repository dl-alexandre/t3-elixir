defmodule T3.Error do
  @moduledoc "A transport, HTTP, protocol, OAuth, or tool failure. Details may contain server data."
  defexception [:kind, :code, :details, message: "T3 request failed"]
  @type t :: %__MODULE__{kind: atom(), code: term(), details: term(), message: String.t()}
end
