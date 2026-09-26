defmodule AshPlanningCenter.Equilibrium.ControlTest do
  use ExUnit.Case, async: true
  alias AshPlanningCenter.Equilibrium.Control

  defp state do
    Control.new(epoch: 7, max_queue: 2)
    |> Control.register_provider("b", [:people_read])
    |> Control.register_provider("a", [:people_read])
  end

  defp order(extra \\ %{}) do
    Map.merge(%{subject: "pco:people", capability: :people_read, epoch: 7,
      authority: [:observe, :select, :construct], planners: [:fond, :powl], max_steps: 12}, extra)
  end

  test "selection is deterministic and consequence-free" do
    assert {:ok, a} = Control.admit(order(), state())
    assert a.planner == :fond
    assert a.provider == "a"
    assert a.receipt.consequence == :none
    assert {:ok, b} = Control.admit(order(), state())
    assert a.receipt == b.receipt
  end

  test "authority laundering refuses before queueing" do
    assert {:refused, %{code: :authority_laundering}} =
      Control.admit(order(%{authority: [:observe, :do]}), state())
  end

  test "epoch drift and unbounded planning are typed refusals" do
    assert {:refused, %{code: :epoch_drift}} = Control.admit(order(%{epoch: 6}), state())
    assert {:refused, %{code: :unbounded_plan}} = Control.admit(order(%{max_steps: 129}), state())
  end

  test "provider extinction refuses admission" do
    s = state() |> Control.extinguish_provider("a") |> Control.extinguish_provider("b")
    assert {:refused, %{code: :provider_extinction}} = Control.admit(order(), s)
  end

  test "duplicate delivery replays and queue is bounded" do
    {:ok, admitted} = Control.admit(order(), state())
    assert {:ok, s1} = Control.enqueue(state(), admitted)
    assert {:replay, ^s1, _} = Control.enqueue(s1, admitted)
    {:ok, second} = Control.admit(order(%{subject: "pco:people:2"}), s1)
    {:ok, s2} = Control.enqueue(s1, second)
    {:ok, third} = Control.admit(order(%{subject: "pco:people:3"}), s2)
    assert {:refused, :backpressure, ^s2} = Control.enqueue(s2, third)
  end

  test "crash reclaim rotates epoch and stale completion cannot acquire standing" do
    {:ok, admitted} = Control.admit(order(), state())
    {:ok, s1} = Control.enqueue(state(), admitted)
    {:ok, lease, s2} = Control.lease(s1, "worker-1")
    s3 = Control.reclaim(s2)
    assert s3.epoch == 8
    assert {:refused, :unknown_lease, ^s3} = Control.complete(s3, lease.token, %{consequence: :none})
  end

  test "completion rejects consequence claims" do
    {:ok, admitted} = Control.admit(order(), state())
    {:ok, s1} = Control.enqueue(state(), admitted)
    {:ok, lease, s2} = Control.lease(s1, "worker")
    assert {:refused, :consequence_claim, ^s2} =
      Control.complete(s2, lease.token, %{consequence: :planning_center_write})
  end

  test "replay order is deterministic" do
    {:ok, a} = Control.admit(order(%{subject: "b"}), state())
    {:ok, b} = Control.admit(order(%{subject: "a"}), state())
    assert Control.replay([a.receipt, b.receipt]) == Control.replay([b.receipt, a.receipt])
  end
end
