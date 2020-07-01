defmodule Watchtower.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  require Logger

  use Application

  def start(_type, _args) do
    children =
      if Code.ensure_loaded?(Watchtower.BeaconRegistry) do
        # This will only be available after the library is compiled
        beacons = apply(Watchtower.BeaconRegistry, :beacons, [])
        # List all child processes to be supervised
        children = [Watchtower.Watchman] ++ Enum.map(beacons, &Watchtower.Beacon.child_spec/1)
      else
        Logger.warn("""
          Could not find Beacon Registry!
          Please run `mix compile.watchtower` or add :watchtower to the end of the list
          of compliers in mix.exs
        """)

        []
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Watchtower.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
