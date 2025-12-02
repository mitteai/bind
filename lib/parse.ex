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
  Supports:
  - Regular fields: "name[eq]" -> [:name, "eq"]
  - JSONB dot notation: "options.prompt[contains]" -> [:options, "prompt", "contains"]
  - Join colon notation: "current_version:content_title[contains]" -> [:current_version, :content_title, "contains", :join]
  - Join with JSONB: "current_version:flow_input.prompt[contains]" -> [:current_version, :flow_input, "prompt", "contains", :join_jsonb]

  ## Parameters
    - `param`: The where parameter as a string.

  """
  def where_field(param) do
    # Join with JSONB: assoc:field.jsonkey[constraint]
    case Regex.match?(~r/^\w+:\w+\.\w+\[\w+\]$/, param) do
      true ->
        [assoc_field_part, constraint] = String.split(param, "[")
        constraint = String.trim(constraint, "]")
        [assoc, field_jsonkey] = String.split(assoc_field_part, ":")
        [field, json_key] = String.split(field_jsonkey, ".")
        [String.to_atom(assoc), String.to_atom(field), json_key, constraint, :join_jsonb]

      false ->
        # Regular join: assoc:field[constraint]
        case Regex.match?(~r/^\w+:\w+\[\w+\]$/, param) do
          true ->
            [assoc_field_part, constraint] = String.split(param, "[")
            constraint = String.trim(constraint, "]")
            [assoc, field] = String.split(assoc_field_part, ":")
            [String.to_atom(assoc), String.to_atom(field), constraint, :join]

          false ->
            # Regular field or JSONB
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
  end
end
