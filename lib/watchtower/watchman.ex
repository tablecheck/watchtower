defmodule Watchtower.Watchman do
  @moduledoc """
  Watches the beacons.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    :ets.new(:watchman, [:set, :public, :named_table])
    {:ok, %{}, {:continue, :monitor}}
  end

  def report,
    do: Enum.into(:ets.tab2list(:watchman), %{})

  def report(status) when is_atom(status) do
    :ets.match(:watchman, {'_', status: status})
  end

  def handle_continue(:monitor, state) do
    Process.send_after(self(), :monitor, 1000)
    {:noreply, state}
  end

  def handle_info(:monitor, state),
    do: {:noreply, state, {:continue, :monitor}}
end
