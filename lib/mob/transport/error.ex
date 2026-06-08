defmodule Mob.Transport.Error do
  @moduledoc """
  Structured error value for adapter and normalization failures.

  Public APIs still return plain `{:error, reason}` tuples for idiomatic Elixir
  interop. This struct is available when callers want a stable shape in logs,
  telemetry metadata, or future richer error handling.
  """

  @type t :: %__MODULE__{
          reason: term(),
          context: map()
        }

  defexception [:reason, context: %{}]

  @impl true
  def message(%__MODULE__{reason: reason, context: context}) do
    "mob transport error: #{inspect(reason)} context=#{inspect(context)}"
  end

  @doc """
  Builds a transport error struct.
  """
  @spec new(term(), map()) :: t()
  def new(reason, context \\ %{}) when is_map(context) do
    %__MODULE__{reason: reason, context: context}
  end
end
