defmodule AshPlanningCenter.Equilibrium.Control do
  @moduledoc "Deterministic observation-only planner/provider control; never a DO boundary."
  @planners [:hddl, :fond, :powl]
  @max_steps 128
  def new(opts \\ []), do: %{epoch: Keyword.get(opts,:epoch,0), queue: :queue.new(), seen: MapSet.new(), leases: %{}, providers: %{}, max_queue: Keyword.get(opts,:max_queue,256)}
  def register_provider(s,id,caps,epoch \\ nil) when is_binary(id) and is_list(caps), do: put_in(s,[:providers,id],%{capabilities: MapSet.new(caps),epoch: epoch || s.epoch,alive: true})
  def extinguish_provider(s,id), do: update_in(s.providers[id], fn nil->nil; p->%{p|alive:false} end)
  def admit(o,s) when is_map(o) do
    with subject when is_binary(subject) and subject != "" <- Map.get(o,:subject),
         cap when is_atom(cap) and not is_nil(cap) <- Map.get(o,:capability),
         true <- Map.get(o,:epoch)==s.epoch,
         true <- MapSet.subset?(MapSet.new(Map.get(o,:authority,[])),MapSet.new([:observe,:select,:construct])),
         steps when is_integer(steps) and steps>0 and steps<=@max_steps <- Map.get(o,:max_steps,32),
         planner when not is_nil(planner) <- Enum.find(@planners,&(&1 in Map.get(o,:planners,@planners))),
         provider when not is_nil(provider) <- provider(s,cap) do
      r=receipt(:admitted,subject,%{planner:planner,provider:provider,steps:steps,epoch:s.epoch})
      {:ok,%{order:o,planner:planner,provider:provider,steps:steps,receipt:r}}
    else
      nil -> {:refused,:unavailable}
      false -> {:refused,:admission_boundary}
      _ -> {:refused,:invalid_order}
    end
  end
  def enqueue(s,a) do
    id=a.receipt.id
    cond do
      MapSet.member?(s.seen,id)->{:replay,s,a.receipt}
      :queue.len(s.queue)>=s.max_queue->{:refused,:backpressure,s}
      true->{:ok,%{s|queue: :queue.in(a,s.queue),seen: MapSet.put(s.seen,id)}}
    end
  end
  def lease(s,worker) when is_binary(worker) do
    case :queue.out(s.queue) do
      {:empty,_}->{:empty,s}
      {{:value,a},q}->
        token=digest({a.receipt.id,worker,s.epoch})
        l=%{token:token,worker:worker,epoch:s.epoch,admitted:a}
        {:ok,l,%{s|queue:q,leases:Map.put(s.leases,token,l)}}
    end
  end
  def complete(s,token,result) when is_map(result) do
    case Map.fetch(s.leases,token) do
      :error->{:refused,:unknown_lease,s}
      {:ok,%{epoch:e}} when e!=s.epoch->{:refused,:stale_epoch,s}
      {:ok,l}->
        if Map.get(result,:consequence,:none) in [:none,nil,false] do
          r=receipt(:constructed,l.admitted.order.subject,%{lease:token,result:result,authority: :observe})
          {:ok,r,%{s|leases:Map.delete(s.leases,token)}}
        else
          {:refused,:consequence_claim,s}
        end
    end
  end
  def reclaim(s) do
    q=s.leases |> Map.values() |> Enum.sort_by(& &1.token) |> Enum.reduce(s.queue,fn l,q->:queue.in_r(l.admitted,q) end)
    %{s|epoch:s.epoch+1,queue:q,leases:%{}}
  end
  def replay(rs), do: Enum.sort_by(rs,& &1.id)
  defp provider(s,cap), do: s.providers |> Enum.filter(fn {_id,p}->p.alive and p.epoch==s.epoch and MapSet.member?(p.capabilities,cap) end) |> Enum.map(&elem(&1,0)) |> Enum.sort() |> List.first()
  defp receipt(k,subject,payload) do
    body=%{kind:k,subject:subject,consequence: :none,payload:payload}
    Map.put(body,:id,digest(body))
  end
  defp digest(term), do: :crypto.hash(:sha256,:erlang.term_to_binary(term)) |> Base.encode16(case: :lower)
end
