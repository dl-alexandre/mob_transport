# Implementing a Transport

Carrier packages implement `Mob.Transport` and let `Mob.Transport.Adapter`
handle the common lifecycle, event normalization, and forwarding contract.

## Required callbacks

```elixir
@callback start_link(keyword()) :: GenServer.on_start()
@callback send_frame(pid(), peer_id, binary(), keyword()) :: :ok | {:error, term()}
```

`start_link/1` receives all carrier options plus `:event_target`. When started
through `Mob.Transport.Adapter`, `:event_target` is the adapter process.

`send_frame/4` sends one binary frame to one peer. The carrier decides how to
map `peer_id` to BLE peripherals, WiFi sockets, mesh neighbors, or another
medium.

## Optional callbacks

```elixir
@callback stop(pid()) :: :ok | {:error, term()}
@callback broadcast_frame(pid(), binary(), keyword()) :: :ok | {:error, term()}
```

Implement `stop/1` when the carrier needs explicit cleanup beyond process
shutdown. Implement `broadcast_frame/3` only when the carrier has a meaningful
broadcast operation.

## Event target

Every carrier must send inbound events to the configured `:event_target`.

Canonical events:

```elixir
send(event_target, {:transport_up, peer_id, metadata})
send(event_target, {:transport_down, peer_id})
send(event_target, {:frame, peer_id, frame})
send(event_target, {:transport_error, reason})
```

`frame` must be a binary. Non-binary frames are rejected by the normalizer with:

```elixir
{:error, {:invalid_frame, frame}}
```

## Minimal carrier

```elixir
defmodule MyCarrier.Transport do
  @behaviour Mob.Transport

  use GenServer

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def send_frame(pid, peer_id, frame, opts \\ []) do
    GenServer.call(pid, {:send_frame, peer_id, frame, opts})
  end

  @impl true
  def init(opts) do
    {:ok, %{event_target: Keyword.fetch!(opts, :event_target)}}
  end

  @impl true
  def handle_call({:send_frame, peer_id, frame, _opts}, _from, state) do
    # Replace this with the carrier-specific write operation.
    send(state.event_target, {:frame, peer_id, frame})
    {:reply, :ok, state}
  end
end
```

## Adapter usage

```elixir
{:ok, adapter} =
  Mob.Transport.Adapter.start_link(
    transport: MyCarrier.Transport,
    event_target: router_pid,
    carrier_option: "value"
  )
```

Adapter-specific options are removed before carrier startup. Remaining options
are passed through, and `:transport_opts` can be used when callers want a
separate namespace:

```elixir
Mob.Transport.Adapter.start_link(
  transport: MyCarrier.Transport,
  event_target: router_pid,
  transport_opts: [local_name: "phone"]
)
```

## Error and restart strategy

The adapter traps exits from its owned transport. If the transport exits, the
adapter stops with `{:transport_exit, reason}` so a supervisor can restart the
adapter and carrier together.

For OTP-owned adapters:

```elixir
children = [
  {Mob.Transport.Supervisor, name: MyApp.TransportSupervisor}
]

{:ok, adapter} =
  Mob.Transport.Supervisor.start_adapter(
    MyApp.TransportSupervisor,
    transport: MyCarrier.Transport,
    event_target: router_pid
  )
```

## Mobile carrier checklist

Keep mobile concerns in the carrier package, not in `mob_transport`:

* app backgrounding and foregrounding
* iOS and Android permission flows
* battery or radio constraints
* connection quality changes
* native bridge startup and teardown
