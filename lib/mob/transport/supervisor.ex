defmodule Mob.Transport.Supervisor do
  @moduledoc """
  Dynamic supervisor for `Mob.Transport.Adapter` processes.

  Use this when an application wants OTP-owned adapters:

      {:ok, sup} = Mob.Transport.Supervisor.start_link(name: MyApp.TransportSupervisor)

      {:ok, adapter} =
        Mob.Transport.Supervisor.start_adapter(
          MyApp.TransportSupervisor,
          transport: MyTransport,
          event_target: self()
        )
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @spec start_adapter(GenServer.server(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_adapter(supervisor \\ __MODULE__, opts) do
    DynamicSupervisor.start_child(supervisor, {Mob.Transport.Adapter, opts})
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
