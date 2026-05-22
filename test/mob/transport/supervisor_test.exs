defmodule Mob.Transport.SupervisorTest do
  use ExUnit.Case, async: true

  alias Mob.Transport.FakeTransport
  alias Mob.Transport.Supervisor

  test "starts adapter children dynamically" do
    {:ok, supervisor} = Supervisor.start_link(name: nil)

    assert {:ok, adapter} =
             Supervisor.start_adapter(
               supervisor,
               transport: FakeTransport,
               event_target: self()
             )

    assert Process.alive?(adapter)
  end

  test "runs multiple adapter children concurrently" do
    {:ok, supervisor} = Supervisor.start_link(name: nil)

    assert {:ok, adapter_a} =
             Supervisor.start_adapter(
               supervisor,
               transport: FakeTransport,
               event_target: self()
             )

    assert {:ok, adapter_b} =
             Supervisor.start_adapter(
               supervisor,
               transport: FakeTransport,
               event_target: self()
             )

    assert adapter_a != adapter_b
    assert length(DynamicSupervisor.which_children(supervisor)) == 2
  end

  test "restarts an adapter after its owned transport crashes" do
    {:ok, supervisor} = Supervisor.start_link(name: nil)

    assert {:ok, adapter} =
             Supervisor.start_adapter(
               supervisor,
               transport: FakeTransport,
               event_target: self()
             )

    %{transport_pid: transport_pid} = :sys.get_state(adapter)
    Process.monitor(adapter)

    FakeTransport.crash(transport_pid, :boom)

    assert_receive {:DOWN, _ref, :process, ^adapter, {:transport_exit, :boom}}, 1_000

    assert [{_id, restarted_adapter, :worker, [Mob.Transport.Adapter]}] =
             DynamicSupervisor.which_children(supervisor)

    assert restarted_adapter != adapter
    assert Process.alive?(restarted_adapter)
  end
end
