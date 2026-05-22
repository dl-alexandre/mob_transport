# mob_transport

`mob_transport` is a small reusable transport abstraction layer for `mob`
transport plugins.

It defines:

* a common `Mob.Transport` behaviour
* canonical transport events
* a lightweight `Mob.Transport.Adapter`
* an optional `Mob.Transport.Supervisor` for adapter processes

It does not include BLE, WiFi, mesh, native, routing, or messaging logic.
Carrier-specific packages such as `mob_ble` implement the behaviour and emit
carrier events to the adapter.

## Event Contract

Canonical events forwarded by the adapter:

```elixir
{:transport_up, peer_id, metadata}
{:transport_down, peer_id}
{:frame, peer_id, frame}
{:transport_error, reason}
```

The initial compatibility layer also normalizes current `mob_ble` bridge
events:

```elixir
{:ble_peer_up, peer_id, metadata}
{:ble_peer_down, peer_id}
{:ble_frame, peer_id, frame}
```

## Example

```elixir
{:ok, adapter} =
  Mob.Transport.Adapter.start_link(
    transport: Mob.Ble.MobileBridge,
    event_target: self(),
    local_name: "my-device",
    native?: false
  )

:ok = Mob.Transport.Adapter.send_frame(adapter, "peer-id", "payload")
```

See `docs/ARCHITECTURE.md` for the adapter pattern and package boundaries.
