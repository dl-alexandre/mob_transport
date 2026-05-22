defmodule Mob.Transport.Supervisor do
  @moduledoc """
  Dynamic supervisor for `Mob.Transport.Adapter` processes.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec start_adapter(DynamicSupervisor.supervisor(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_adapter(supervisor \\ __MODULE__, opts) do
    DynamicSupervisor.start_child(supervisor, {Mob.Transport.Adapter, opts})
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
