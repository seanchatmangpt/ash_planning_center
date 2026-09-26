defmodule AshPlanningCenter.EventReaderAdversarialTest do
  @moduledoc """
  Adversarial falsifiers for the bounded ZOE live observation reader.

  Every provider below is a real, hand-written implementation of the
  `AshPlanningCenter.Client` behaviour (a deterministic in-process provider),
  not an interaction-verifying mock: the reader is exercised end to end and the
  assertions are on the returned contract/receipt state. A live Planning Center
  tenant is not used because it is a paid external system holding youth PII.
  """
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Client.Response
  alias AshPlanningCenter.EventReader

  @attendees_path "/registrations/v2/signups/signup-1/attendees"

  def ok_page(data, total) do
    {:ok,
     %Response{
       status: 200,
       body: %{"data" => data, "meta" => %{"total_count" => total}},
       headers: %{}
     }}
  end

  def attendee(id, attributes \\ %{"active" => true}) do
    %{
      "id" => id,
      "attributes" => attributes,
      "relationships" => %{"person" => %{"data" => %{"id" => "p-" <> id}}}
    }
  end

  defmodule NonMapRecordClient do
    @behaviour AshPlanningCenter.Client
    @impl true
    def request(:get, _path, _opts) do
      {:ok, %Response{status: 200, body: %{"data" => ["not-a-resource"]}, headers: %{}}}
    end
  end

  defmodule MissingIdClient do
    @behaviour AshPlanningCenter.Client
    @impl true
    def request(:get, _path, _opts) do
      {:ok,
       %Response{
         status: 200,
         body: %{"data" => [%{"attributes" => %{"active" => true}}]},
         headers: %{}
       }}
    end
  end

  defmodule UnsafeIdClient do
    @behaviour AshPlanningCenter.Client
    @impl true
    def request(:get, _path, _opts) do
      {:ok,
       %Response{
         status: 200,
         body: %{"data" => [%{"id" => "a b\n<script>", "attributes" => %{}}]},
         headers: %{}
       }}
    end
  end

  defmodule UnsafePersonRefClient do
    @behaviour AshPlanningCenter.Client
    @impl true
    def request(:get, _path, _opts) do
      resource = %{
        "id" => "att-1",
        "attributes" => %{"active" => true},
        "relationships" => %{"person" => %{"data" => %{"id" => "Jane Doe"}}}
      }

      AshPlanningCenter.EventReaderAdversarialTest.ok_page([resource], 1)
    end
  end

  defmodule DuplicateDeliveryClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    # Offset pagination under a concurrent insert: the last record of page 0 is
    # delivered again as the first record of page 1 (identical content).
    def request(:get, _path, opts) do
      offset = opts |> Keyword.fetch!(:params) |> Map.fetch!("offset")

      ids =
        case offset do
          0 -> Enum.map(1..100, &"att-#{&1}")
          100 -> ["att-100", "att-101", "att-102"]
        end

      T.ok_page(Enum.map(ids, &T.attendee/1), 102)
    end
  end

  defmodule ConflictingDuplicateClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts) do
      T.ok_page([T.attendee("att-1"), T.attendee("att-1", %{"canceled" => true})], 2)
    end
  end

  defmodule NegativeTotalClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts) do
      T.ok_page(Enum.map(1..100, &T.attendee("att-#{&1}")), -1)
    end
  end

  defmodule UnderstatedTotalClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    # Provider claims 0 total while delivering a full page: stopping here would
    # silently truncate the observation.
    def request(:get, _path, _opts) do
      T.ok_page(Enum.map(1..100, &T.attendee("att-#{&1}")), 0)
    end
  end

  defmodule StringTotalClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts), do: T.ok_page([T.attendee("att-1")], "1")
  end

  defmodule OrderedClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts) do
      T.ok_page(Enum.map(["att-3", "att-1", "att-2"], &T.attendee/1), 3)
    end
  end

  defmodule ReorderedClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts) do
      T.ok_page(Enum.map(["att-2", "att-3", "att-1"], &T.attendee/1), 3)
    end
  end

  defmodule MutatedClient do
    @behaviour AshPlanningCenter.Client
    alias AshPlanningCenter.EventReaderAdversarialTest, as: T
    @impl true
    def request(:get, _path, _opts) do
      T.ok_page(
        [
          T.attendee("att-1"),
          T.attendee("att-2", %{"canceled" => true}),
          T.attendee("att-3")
        ],
        3
      )
    end
  end

  defmodule MethodLedgerClient do
    @behaviour AshPlanningCenter.Client
    @impl true
    def request(method, path, _opts) do
      send(self(), {:ledger, method, path})
      AshPlanningCenter.EventReaderAdversarialTest.ok_page([], 0)
    end
  end

  @attrs %{
    event_ref: "event:youth-001",
    event_name: "Youth Night",
    starts_at: "2026-09-23T19:00:00-07:00",
    sources: %{registrations: %{signup_id: "signup-1"}}
  }

  describe "malformed provider records are typed refusals, never crashes" do
    test "non-map resource" do
      assert {:error, {:malformed_provider_record, @attendees_path, 0, :expected_resource_map}} =
               EventReader.read(@attrs, client: NonMapRecordClient)
    end

    test "resource without an opaque id" do
      assert {:error, {:malformed_provider_record, @attendees_path, 0, :missing_opaque_id}} =
               EventReader.read(@attrs, client: MissingIdClient)
    end

    test "resource id outside the opaque-id alphabet cannot enter a projected ref" do
      assert {:error, {:malformed_provider_record, @attendees_path, 0, :unsafe_opaque_id}} =
               EventReader.read(@attrs, client: UnsafeIdClient)
    end

    test "person relationship id that is not opaque (e.g. a name) is refused, not projected" do
      assert {:error, {:malformed_provider_record, @attendees_path, 0, :unsafe_person_id}} =
               EventReader.read(@attrs, client: UnsafePersonRefClient)
    end

    test "read!/2 raises ArgumentError with the typed reason" do
      assert_raise ArgumentError, ~r/malformed_provider_record/, fn ->
        EventReader.read!(@attrs, client: MissingIdClient)
      end
    end
  end

  describe "malformed caller input is refused before transport" do
    test "a non-map source config is refused" do
      attrs = put_in(@attrs, [:sources, :services], "st-youth/plan-1")

      assert {:error, {:invalid_provider_source, :services}} =
               EventReader.read(attrs, client: MethodLedgerClient)

      refute_received {:ledger, _, _}
    end

    test "a non-module client is refused" do
      assert {:error, {:invalid_client, "Elixir.Nope"}} =
               EventReader.read(@attrs, client: "Elixir.Nope")

      assert {:error, {:invalid_client, NoSuchModule}} =
               EventReader.read(@attrs, client: NoSuchModule)
    end

    test "non-map attrs is refused" do
      assert {:error, {:invalid_event_reader, :expected_map}} = EventReader.read([], [])
    end
  end

  describe "duplicate delivery and count integrity" do
    test "identical records delivered twice across pages are observed once" do
      assert {:ok, result} = EventReader.read(@attrs, client: DuplicateDeliveryClient)

      refs = Enum.map(result.contract.observations.registrations, & &1["registration_ref"])
      assert length(refs) == 102
      assert refs == Enum.uniq(refs)
      assert result.receipt.records.registrations == 102
      assert result.contract.counts.registrations == 102
      assert result.receipt.duplicates_dropped == 1
      assert result.receipt.pages == 2
    end

    test "the same id delivered with conflicting content is refused" do
      assert {:error, {:conflicting_duplicate_record, @attendees_path, "att-1"}} =
               EventReader.read(@attrs, client: ConflictingDuplicateClient)
    end

    test "a negative total_count is refused" do
      assert {:error, {:invalid_provider_total, @attendees_path, -1}} =
               EventReader.read(@attrs, client: NegativeTotalClient)
    end

    test "a non-integer total_count is refused" do
      assert {:error, {:invalid_provider_total, @attendees_path, "1"}} =
               EventReader.read(@attrs, client: StringTotalClient)
    end

    test "a total_count below the records already delivered is refused, not truncated" do
      assert {:error, {:provider_count_inconsistent, @attendees_path, 0, 100}} =
               EventReader.read(@attrs, client: UnderstatedTotalClient)
    end
  end

  describe "replay identity" do
    test "provider reordering does not change the contract or the observation digest" do
      assert {:ok, a} = EventReader.read(@attrs, client: OrderedClient)
      assert {:ok, b} = EventReader.read(@attrs, client: ReorderedClient)

      assert a.contract.observations == b.contract.observations
      assert a.receipt.observation_digest == b.receipt.observation_digest
      assert "sha256:" <> hex = a.receipt.observation_digest
      assert byte_size(hex) == 64
    end

    test "repeated reads of an unchanged provider replay identically" do
      assert {:ok, a} = EventReader.read(@attrs, client: OrderedClient)
      assert {:ok, b} = EventReader.read(@attrs, client: OrderedClient)
      assert a == b
    end

    test "a changed provider observation changes the digest (replay mismatch is detectable)" do
      assert {:ok, a} = EventReader.read(@attrs, client: OrderedClient)
      assert {:ok, c} = EventReader.read(@attrs, client: MutatedClient)
      refute a.receipt.observation_digest == c.receipt.observation_digest
    end
  end

  describe "authority boundary" do
    test "every provider call is a GET under an admitted product prefix" do
      attrs =
        Map.put(@attrs, :sources, %{
          services: %{service_type_id: "st-1", plan_id: "plan-1"},
          registrations: %{signup_id: "signup-1"},
          check_ins: %{event_id: "ev-1"}
        })

      assert {:ok, result} = EventReader.read(attrs, client: MethodLedgerClient)
      assert result.receipt.do_authority == false

      calls = collect_ledger([])
      assert length(calls) == 3

      for {method, path} <- calls do
        assert method == :get

        assert String.starts_with?(path, "/services/v2/") or
                 String.starts_with?(path, "/registrations/v2/") or
                 String.starts_with?(path, "/check-ins/v2/")
      end
    end
  end

  defp collect_ledger(acc) do
    receive do
      {:ledger, method, path} -> collect_ledger([{method, path} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
