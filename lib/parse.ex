defmodule Bind.Parse do
  import Ecto.Query

  @doc """
  Parses the sort parameter to determine the sort direction and field.

  ## Parameters
    - `param`: The sort parameter as a string.

  ## Examples

      > Bind.Parse.sort_field("-age")
      [desc: :age]

      > Bind.Parse.sort_field("name")
      [asc: :name]

  """
  def sort_field(param) do
    case String.starts_with?(param, "-") do
      true ->
        [desc: String.to_atom(String.trim(param, "-"))]

      false ->
        [asc: String.to_atom(param)]
    end
  end

  @doc """
  Parses a where parameter to extract the field name and constraint.
  Now supports JSONB dot notation like "options.prompt[contains]".

  ## Parameters
    - `param`: The where parameter as a string.

  ## Examples

      > Bind.Parse.where_field("name[eq]")
      [:name, "eq"]

      > Bind.Parse.where_field("options.prompt[contains]")
      [:options, "prompt", "contains"]

  """
  def where_field(param) do
    case Regex.match?(~r/^\w+(\.\w+)?\[\w+\]$/, param) do
      true ->
        [field_part, constraint] = String.split(param, "[")
        constraint = String.trim(constraint, "]")

        case String.contains?(field_part, ".") do
          true ->
            [json_field, json_key] = String.split(field_part, ".")
            [String.to_atom(json_field), json_key, constraint]

          false ->
            [String.to_atom(field_part), constraint]
        end

      false ->
        nil
    end
  end
end
