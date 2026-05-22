defmodule MobTransportTest do
  use ExUnit.Case, async: true

  test "exposes the transport behaviour module" do
    assert Mob.Transport.behaviour() == Mob.Transport
  end
end
