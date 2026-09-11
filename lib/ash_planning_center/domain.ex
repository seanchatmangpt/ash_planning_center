defmodule AshPlanningCenter.Domain do
  @moduledoc "Primary Ash domain for Planning Center resources."

  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshPlanningCenter.People.Person do
      define :list_people, action: :read
      define :get_person, action: :get, args: [:id]
    end
  end
end
