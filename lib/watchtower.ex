defmodule Watchtower do
  @moduledoc """
  Documentation for `Watchtower`.
  """
  @desc_behaviour Watchtower.Beacon

  def register_all(opts \\ []) do
    opts
    |> get_base_paths()
    |> Enum.flat_map(fn path ->
      path
      |> Path.join("*.beam")
      |> Path.wildcard()
    end)
    # Find all modules which implement the @desc_behaviour
    |> Enum.flat_map(fn path ->
      case :beam_lib.chunks(to_charlist(path), [:attributes]) do
        {:ok, {mod, chunks}} ->
          is_beacon? =
            chunks
            |> get_in([:attributes, :behaviour])
            |> List.wrap()
            |> Enum.member?(@desc_behaviour)

          if is_beacon?, do: [mod], else: []

        _ ->
          []
      end
    end)
    |> register_beacons()
  end

  defp get_base_paths(opts) do
    case opts[:ebin_root] do
      nil -> :code.get_path()
      paths -> List.wrap(paths)
    end
  end

  defp register_beacons(beacons) do
    beacon_registry = Watchtower.BeaconRegistry

    contents =
      quote do
        def beacons, do: unquote(beacons)
      end

    {:module, beam_name, beam_data, _exports} =
      Module.create(beacon_registry, contents, Macro.Env.location(__ENV__))

    Code.compiler_options(ignore_module_conflict: true)
    beam_filename = "#{beam_name}.beam"
    base_path = apply(Mix.Project, :build_path, [])
    path = Path.join([base_path, beam_filename])
    File.write!(path, beam_data)
    Code.compiler_options(ignore_module_conflict: false)
  end
end
