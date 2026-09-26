defmodule AshPlanningCenter.EventSnapshot do
  @moduledoc """
  Authority-free event-operations observation contract.

  Planning Center remains the remote system of record. This module only
  normalizes already-observed provider data into the cross-repository
  `zoe-event-ops/v1` contract consumed by XaaS simulation and ZOELA
  projections.

  It deliberately does not call Planning Center, infer staffing policy,
  route an incident, or acquire DO authority. Participant records are
  constrained to opaque references and operational state so youth PII
  cannot leak through this seam.
  """

  @contract_version "zoe-event-ops/v1"

  @record_fields %{
    roster: %{
      allowed: ~w(slot_ref person_ref role status),
      required: ~w(person_ref role)
    },
    registrations: %{
      allowed: ~w(registration_ref person_ref status),
      required: ~w(registration_ref person_ref)
    },
    check_ins: %{
      allowed: ~w(check_in_ref person_ref occurred_at status),
      required: ~w(check_in_ref person_ref)
    }
  }

  @enforce_keys [
    :event_ref,
    :event_name,
    :starts_at,
    :roster,
    :registrations,
    :check_ins,
    :source_refs
  ]
  defstruct @enforce_keys

  @type participant_record :: %{optional(String.t()) => term()}

  @type t :: %__MODULE__{
          event_ref: String.t(),
          event_name: String.t(),
          starts_at: String.t(),
          roster: [participant_record()],
          registrations: [participant_record()],
          check_ins: [participant_record()],
          source_refs: [String.t()]
        }

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    with {:ok, event_ref} <- required_string(attrs, :event_ref),
         {:ok, event_name} <- required_string(attrs, :event_name),
         {:ok, starts_at} <- required_string(attrs, :starts_at),
         {:ok, roster} <- normalize_records(value(attrs, :roster, []), :roster),
         {:ok, registrations} <-
           normalize_records(value(attrs, :registrations, []), :registrations),
         {:ok, check_ins} <- normalize_records(value(attrs, :check_ins, []), :check_ins),
         {:ok, source_refs} <-
           normalize_string_list(value(attrs, :source_refs, []), :source_refs) do
      {:ok,
       %__MODULE__{
         event_ref: event_ref,
         event_name: event_name,
         starts_at: starts_at,
         roster: roster,
         registrations: registrations,
         check_ins: check_ins,
         source_refs: source_refs
       }}
    end
  end

  def new(_attrs), do: {:error, {:invalid_event_snapshot, :expected_map}}

  @spec to_contract(t()) :: map()
  def to_contract(%__MODULE__{} = snapshot) do
    %{
      contract_version: @contract_version,
      provider: "planning_center",
      authority_boundary: "OBSERVE",
      do_authority: false,
      standing: "UNKNOWN",
      evidence_ceiling: "CONTRACT_ONLY",
      event: %{
        ref: snapshot.event_ref,
        name: snapshot.event_name,
        starts_at: snapshot.starts_at
      },
      observations: %{
        roster: snapshot.roster,
        registrations: snapshot.registrations,
        check_ins: snapshot.check_ins
      },
      counts: %{
        roster: length(snapshot.roster),
        registrations: unique_count(snapshot.registrations, "registration_ref"),
        check_ins: unique_count(snapshot.check_ins, "person_ref")
      },
      source_refs: snapshot.source_refs
    }
  end

  defp normalize_records(records, kind) when is_list(records) do
    records
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {record, index}, {:ok, acc} ->
      case normalize_record(record, kind, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  defp normalize_records(_records, kind), do: {:error, {:invalid_collection, kind}}

  defp normalize_record(record, kind, index) when is_map(record) do
    %{allowed: allowed, required: required} = Map.fetch!(@record_fields, kind)

    normalized =
      Map.new(record, fn {key, val} ->
        {normalize_key(key), val}
      end)

    unknown = Map.keys(normalized) -- allowed
    missing = Enum.reject(required, &non_blank?(Map.get(normalized, &1)))

    cond do
      unknown != [] ->
        {:error, {:unsupported_participant_fields, kind, index, Enum.sort(unknown)}}

      missing != [] ->
        {:error, {:missing_participant_fields, kind, index, missing}}

      true ->
        {:ok, normalized}
    end
  end

  defp normalize_record(_record, kind, index),
    do: {:error, {:invalid_participant_record, kind, index}}

  defp normalize_string_list(values, field) when is_list(values) do
    if Enum.all?(values, &non_blank?/1) do
      {:ok, Enum.map(values, &String.trim/1)}
    else
      {:error, {:invalid_string_list, field}}
    end
  end

  defp normalize_string_list(_values, field), do: {:error, {:invalid_string_list, field}}

  defp required_string(attrs, key) do
    case value(attrs, key, nil) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, {:missing_required_field, key}}
        else
          {:ok, value}
        end

      _ ->
        {:error, {:missing_required_field, key}}
    end
  end

  defp value(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp non_blank?(value) when is_binary(value), do: String.trim(value) != ""
  defp non_blank?(_value), do: false

  defp unique_count(records, key) do
    records
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end
end
