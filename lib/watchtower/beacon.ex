defmodule Watchtower.Beacon do
  @moduledoc """
  A beacon to be watched by the watchman
  """

  require Logger

  defmodule Config do
    @moduledoc ~S"""
    Defines how a beacon should behave.
    """

    defstruct interval: {1, :second},
              log_level: :none,
              severity: :none,
              meta: nil

    @typedoc "Configures behavior of the beacon"
    @type t() :: %__MODULE__{
            interval: Watchtower.Beacon.interval(),
            log_level: :none | Logger.level(),
            severity: :none | atom,
            meta: any
          }
  end

  defmodule Condition do
    @moduledoc ~S"""
    When a beacon is asked to signal, this struct carries information
    regarding the current state of the beacon such as the last time
    it was called, the previous return state, and number of consecutive
    returns with that state.
    """
    @derive Jason.Encoder
    defstruct module: nil,
              status: :init,
              severity: :none,
              sequence: 0,
              count: 0,
              curr_signal: nil,
              prev_signal: nil,
              meta: nil

    @typedoc "Tracks condition of the beacon"
    @type t() :: %__MODULE__{
            module: atom(),
            status: Watchtower.Beacon.status(),
            severity: Watchtower.Beacon.severity(),
            sequence: non_neg_integer,
            count: non_neg_integer,
            curr_signal: DateTime.t(),
            prev_signal: DateTime.t(),
            meta: any
          }
  end

  @type status :: :init | atom
  @type severity :: :none | atom
  @type config :: Watchtower.Beacon.Config.t()
  @type condition :: Watchtower.Beacon.Condition.t()
  @type interval ::
          :never
          | {pos_integer, :millisecond}
          | {pos_integer, :milliseconds}
          | {pos_integer, :second}
          | {pos_integer, :seconds}
          | {pos_integer, :minute}
          | {pos_integer, :minutes}
          | {pos_integer, :hour}
          | {pos_integer, :hours}
          | {pos_integer, :day}
          | {pos_integer, :days}
          | {pos_integer, :week}
          | {pos_integer, :weeks}

  @callback beacon_config() :: config
  @callback beacon_signal(condition) :: status | {status, config}
  @optional_callbacks beacon_config: 0

  use GenServer

  alias Watchtower.Beacon.{Config, Condition}

  def child_spec(module) do
    %{
      id: beacon_name(module),
      start: {Watchtower.Beacon, :start_link, [[name: beacon_name(module), module: module]]}
    }
  end

  def beacon_name(module),
    do: Module.concat([Watchtower, module, Beacon])

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def init(opts) do
    module = Keyword.fetch!(opts, :module)

    config =
      if function_exported?(module, :beacon_config, 0),
        do: merge_config(module.beacon_config(), %Config{}),
        else: %Config{}

    :ets.insert(:watchman, {module, %Condition{module: module}})
    {:ok, %{module: module, config: config, timer: nil}, {:continue, :monitor}}
  end

  defp merge_config(%Config{} = new_config, _), do: new_config

  defp merge_config(new_config, old_config) when is_map(new_config),
    do: Map.merge(old_config, new_config)

  defp merge_config(new_config, old_config) when is_list(new_config) do
    [_ | fields] = Map.keys(%Watchtower.Beacon.Config{})

    new_config
    |> Keyword.take(fields)
    |> Enum.into(%{})
    |> merge_config(old_config)
  end

  def set_config(module, config) do
    case Process.whereis(beacon_name(module)) do
      nil -> {:error, :no_beacon}
      pid -> GenServer.cast(pid, {:set_config, config})
    end
  end

  def get_config(module) do
    case Process.whereis(beacon_name(module)) do
      nil -> {:error, :no_beacon}
      pid -> GenServer.call(pid, :get_config)
    end
  end

  def handle_cast({:set_config, new_config}, %{config: old_config} = state),
    do: {:noreply, %{state | config: merge_config(new_config, old_config)}, {:continue, :monitor}}

  def handle_call(:get_config, _from, state),
    do: {:reply, state.config, state}

  def handle_call(:signal, _from, %{module: module, config: old_config} = state) do
    {new_condition, new_config} = do_signal(module, old_config)
    {:reply, {:ok, new_condition}, %{state | config: new_config}}
  end

  # Skip monitoring
  def handle_continue(:monitor, %{config: %{interval: :never}} = state),
    do: {:noreply, state}

  def handle_continue(:monitor, state) do
    {_new_condition, new_config} = do_signal(state.module, state.config)
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)

    timer =
      case new_config.interval do
        :never ->
          nil

        interval when is_tuple(interval) ->
          Process.send_after(self(), :monitor, interval_to_ms(interval))
      end

    {:noreply, %{state | config: new_config, timer: timer}}
  end

  def handle_info(:monitor, state),
    do: {:noreply, state, {:continue, :monitor}}

  defp do_signal(module, %Config{} = old_config) do
    [{^module, old_condition}] = :ets.lookup(:watchman, module)

    {new_condition, new_config} =
      old_condition
      |> module.beacon_signal()
      |> update_condition(old_condition, old_config)

    :ets.insert(:watchman, {module, new_condition})
    log(new_condition, old_config, new_config)

    {new_condition, new_config}
  end

  # If the beacon passed back a new config, replace the existing config with that.
  defp update_condition({status, new_config}, condition, old_config),
    do: update_condition(status, condition, merge_config(new_config, old_config))

  # Status will always be an atom here
  defp update_condition(status, condition, config) do
    sequence = if condition.status == status, do: condition.sequence + 1, else: 1

    {%{
       condition
       | status: status,
         sequence: sequence,
         count: condition.count + 1,
         severity: config.severity,
         prev_signal: condition.curr_signal,
         curr_signal: DateTime.utc_now(),
         meta: config.meta
     }, config}
  end

  defp log(_, _, %{log_level: :none}), do: :ok

  defp log(condition, old_config, %{log_level: level} = new_config) do
    if new_config != old_config do
      Logger.log(level, "#{__MODULE__}: Changing config to #{inspect(new_config)}")
    end

    Logger.log(level, "#{__MODULE__}: #{inspect(condition)}")
  end

  @doc false
  def interval_to_ms({milliseconds, unit}) when unit in [:millisecond, :milliseconds],
    do: milliseconds

  def interval_to_ms({seconds, unit}) when unit in [:second, :seconds],
    do: seconds * 1000

  def interval_to_ms({minutes, unit}) when unit in [:minute, :minutes],
    do: minutes * 60 * 1000

  def interval_to_ms({hours, unit}) when unit in [:hour, :hours],
    do: hours * 60 * 60 * 1000

  def interval_to_ms({days, unit}) when unit in [:day, :days],
    do: days * 24 * 60 * 60 * 1000

  def interval_to_ms({weeks, unit}) when unit in [:week, :weeks],
    do: weeks * 7 * 24 * 60 * 60 * 1000

  def interval_to_ms({_, units}),
    do: raise("Unknown Units: #{units}")
end
