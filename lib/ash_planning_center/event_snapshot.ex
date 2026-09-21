defmodule AshPlanningCenter.EventSnapshot do
  @moduledoc """
  Read-only operational snapshot for one Planning Center-backed event.

  This module deliberately stops at OBSERVE. It does not mutate Planning
  Center, select an operator, dispatch SA2A work, or manufacture standing.
  Higher-order runtimes can compose this observation with other sensors.
  """

  @enforce_keys [
    :event_id,
    :starts_at,
    :registrations,
    :check_ins,
    :volunteers,
    :roster_complete?,
    :attendance_submitted?,
    :registration_exceptions,
    :teams
  ]

  defstruct [
    :event_id,
    :starts_at,
    :registrations,
    :check_ins,
    :volunteers,
    :roster_complete?,
    :attendance_submitted?,
    :registration_exceptions,
    :teams,
    source: :planning_center,
    authority_boundary: :observe,
    schema_version: 1
  ]

  @type team_count :: %{required("team") => String.t(), required("count") => non_neg_integer()}

  @type t :: %__MODULE__{
          event_id: String.t(),
          starts_at: String.t(),
          registrations: non_neg_integer(),
          check_ins: non_neg_integer(),
          volunteers: non_neg_integer(),
          roster_complete?: boolean(),
          attendance_submitted?: boolean(),
          registration_exceptions: non_neg_integer(),
          teams: [team_count()],
          source: :planning_center,
          authority_boundary: :observe,
          schema_version: 1
        }

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, event_id} <- required_binary(attrs, :event_id),
         {:ok, starts_at} <- required_binary(attrs, :starts_at),
         {:ok, registrations} <- non_negative(attrs, :registrations),
         {:ok, check_ins} <- non_negative(attrs, :check_ins),
         {:ok, volunteers} <- non_negative(attrs, :volunteers),
         {:ok, registration_exceptions} <- non_negative(attrs, :registration_exceptions),
         {:ok, roster_complete?} <- boolean(attrs, :roster_complete?),
         {:ok, attendance_submitted?} <- boolean(attrs, :attendance_submitted?),
         {:ok, teams} <- teams(attrs) do
      {:ok,
       %__MODULE__{
         event_id: event_id,
         starts_at: starts_at,
         registrations: registrations,
         check_ins: check_ins,
         volunteers: volunteers,
         roster_complete?: roster_complete?,
         attendance_submitted?: attendance_submitted?,
         registration_exceptions: registration_exceptions,
         teams: teams
       }}
    end
  end

  def new(_), do: {:error, :invalid_snapshot}

  @spec to_observation(t()) :: map()
  def to_observation(%__MODULE__{} = snapshot) do
    %{
      "schema" => "zoe.event.observation.v1",
      "schema_version" => snapshot.schema_version,
      "source" => "planning_center",
      "authority" => "OBSERVE",
      "event_id" => snapshot.event_id,
      "starts_at" => snapshot.starts_at,
      "registrations" => snapshot.registrations,
      "check_ins" => snapshot.check_ins,
      "volunteers" => snapshot.volunteers,
      "roster_complete" => snapshot.roster_complete?,
      "attendance_submitted" => snapshot.attendance_submitted?,
      "registration_exceptions" => snapshot.registration_exceptions,
      "teams" => snapshot.teams,
      "digest" => digest(snapshot)
    }
  end

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = snapshot) do
    teams =
      snapshot.teams
      |> Enum.map_join(",", fn %{"team" => team, "count" => count} -> "#{team}=#{count}" end)

    [
      snapshot.event_id,
      snapshot.starts_at,
      snapshot.registrations,
      snapshot.check_ins,
      snapshot.volunteers,
      snapshot.roster_complete?,
      snapshot.attendance_submitted?,
      snapshot.registration_exceptions,
      teams
    ]
    |> Enum.map_join("|", &to_string/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp required_binary(attrs, key) do
    case value(attrs, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:invalid, key}}
    end
  end

  defp non_negative(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _ -> {:error, {:invalid, key}}
    end
  end

  defp boolean(attrs, key) do
    case value(attrs, key) do
      value when is_boolean(value) -> {:ok, value}
      _ -> {:error, {:invalid, key}}
    end
  end

  defp teams(attrs) do
    case value(attrs, :teams, %{}) do
      teams when is_map(teams) ->
        teams
        |> Enum.reduce_while({:ok, []}, fn
          {name, count}, {:ok, acc}
          when (is_binary(name) or is_atom(name)) and is_integer(count) and count >= 0 ->
            {:cont, {:ok, [%{"team" => to_string(name), "count" => count} | acc]}}

          _, _ ->
            {:halt, {:error, {:invalid, :teams}}}
        end)
        |> case do
          {:ok, normalized} -> {:ok, Enum.sort_by(normalized, & &1["team"])}
          error -> error
        end

      _ ->
        {:error, {:invalid, :teams}}
    end
  end

  defp value(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
