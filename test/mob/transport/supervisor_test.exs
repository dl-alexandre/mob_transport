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
end
