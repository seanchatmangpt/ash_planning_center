defmodule AshPlanningCenter.Domain do
  @moduledoc "Primary Ash domain for Planning Center resources."

  use Ash.Domain,
    extensions: [AshA2A],
    validate_config_inclusion?: false

  resources do
    resource AshPlanningCenter.People.Person do
      define(:list_people, action: :read)
      define(:get_person, action: :get, args: [:id], not_found_error?: false)
    end
  end
end
