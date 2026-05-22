defmodule Mob.Transport.EventTest do
  use ExUnit.Case, async: true

  describe "normalize/1" do
    test "passes canonical events through" do
      assert Mob.Transport.normalize_event({:transport_up, "peer", %{rssi: -40}}) ==
               {:ok, {:transport_up, "peer", %{rssi: -40}}}

      assert Mob.Transport.normalize_event({:transport_down, "peer"}) ==
               {:ok, {:transport_down, "peer"}}

      assert Mob.Transport.normalize_event({:frame, "peer", "payload"}) ==
               {:ok, {:frame, "peer", "payload"}}
    end

    test "normalizes current mob_ble bridge events" do
      assert Mob.Transport.normalize_event({:ble_peer_up, "peer", %{name: "device"}}) ==
               {:ok, {:transport_up, "peer", %{name: "device"}}}

      assert Mob.Transport.normalize_event({:ble_peer_down, "peer"}) ==
               {:ok, {:transport_down, "peer"}}

      assert Mob.Transport.normalize_event({:ble_frame, "peer", <<1, 2, 3>>}) ==
               {:ok, {:frame, "peer", <<1, 2, 3>>}}
    end

    test "rejects unknown events" do
      assert Mob.Transport.normalize_event({:unknown, :event}) ==
               {:error, {:unknown_event, {:unknown, :event}}}
    end
  end
end
