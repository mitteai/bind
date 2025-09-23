defmodule Bind.QueryBuilder do
  import Ecto.Query

  def add_limit_query(query, params) do
    case Map.get(params, "limit") do
      nil ->
        Ecto.Query.limit(query, [r], 10)

      limit_param when is_integer(limit_param) ->
        Ecto.Query.limit(query, [r], ^limit_param)

      limit_param when is_binary(limit_param) ->
        Ecto.Query.limit(query, [r], ^String.to_integer(limit_param))
    end
  end

  def add_offset_query(query, params) do
  cond do
    start_id = Map.get(params, "start") ->
      Ecto.Query.where(query, [r], field(r, :id) > ^start_id)

    start_id = Map.get(params, "-start") ->
      Ecto.Query.where(query, [r], field(r, :id) < ^start_id)

    true ->
      query
  end
end

  def build_where_query(params) do
    case validate_where_query(params) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        Enum.reduce(params, Ecto.Query.dynamic(true), fn {param, param_value}, dynamic ->
          case Bind.Parse.where_field(param) do
            nil ->
              dynamic

            parsed_field ->
              case build_constraint(parsed_field, param_value) do
                {:error, reason} ->
                  {:error, reason}

                constraint ->
                  dynamic([r], ^dynamic and ^constraint)
              end
          end
        end)
    end
  end

  def validate_where_query(params) do
    Enum.find_value(params, fn {param, param_value} ->
      case Bind.Parse.where_field(param) do
        nil ->
          nil

        parsed_field ->
          case build_constraint(parsed_field, param_value) do
            {:error, reason} -> {:error, reason}
            _ -> nil
          end
      end
    end)
  end

  def build_sort_query(params) do
    case params["sort"] do
      nil -> [asc: :id]
      "" -> [asc: :id]
      sort_param -> Bind.Parse.sort_field(sort_param)
    end
  end

  # Handle both regular fields and JSONB fields
  defp build_constraint([field, constraint], value) do
    constraint(field, constraint, value)
  end

  defp build_constraint([json_field, json_key, constraint], value) do
    jsonb_constraint(json_field, json_key, constraint, value)
  end

  @doc """
  Parses a constraint and returns a dynamic query fragment.

  ## Parameters
    - `field`: The field to apply the constraint to.
    - `constraint`: The type of constraint (e.g., "eq", "gte").
    - `value`: The value to compare the field against.

  ## Examples

      > Bind.Parse.constraint(:name, "eq", "Alice")
      dynamic([r], r.name == ^"Alice")

      > Bind.Parse.constraint(:age, "gte", 30)
      dynamic([r], r.age > ^30)

  """
  def constraint(field, "eq", value) do
    dynamic([r], field(r, ^field) == ^value)
  end

  def constraint(field, "neq", value) do
    dynamic([r], field(r, ^field) != ^value)
  end

  def constraint(field_name, "gt", value) do
    dynamic([r], field(r, ^field_name) > ^value)
  end

  def constraint(field_name, "gte", value) do
    dynamic([r], field(r, ^field_name) >= ^value)
  end

  def constraint(field, "lt", value) do
    dynamic([r], field(r, ^field) < ^value)
  end

  def constraint(field, "lte", value) do
    dynamic([r], field(r, ^field) <= ^value)
  end

  def constraint(field, "true", _value) do
    dynamic([r], field(r, ^field) == true)
  end

  def constraint(field, "false", _value) do
    dynamic([r], field(r, ^field) == false)
  end

  def constraint(field, "starts_with", value) do
    dynamic([r], ilike(field(r, ^field), ^"#{value}%"))
  end

  def constraint(field, "ends_with", value) do
    dynamic([r], ilike(field(r, ^field), ^"%#{value}"))
  end

  def constraint(field, "in", value) do
    values = String.split(value, ",")
    dynamic([r], field(r, ^field) in ^values)
  end

  def constraint(field, "contains", value) do
    dynamic([r], ilike(field(r, ^field), ^"%#{value}%"))
  end

  def constraint(field, "nil", value) when value in ["true", true] do
    dynamic([r], is_nil(field(r, ^field)))
  end

  def constraint(field, "nil", value) when value in ["false", false] do
    dynamic([r], not is_nil(field(r, ^field)))
  end

  def constraint(field, constraint, _value) do
    # Here we add an error clause that matches any unknown constraint.
    {:error, "Invalid constraint: #{field}[#{constraint}]"}
  end

  # JSONB constraint functions
  def jsonb_constraint(json_field, json_key, "eq", value) do
    dynamic([r], fragment("? ->> ? = ?", field(r, ^json_field), ^json_key, ^value))
  end

  def jsonb_constraint(json_field, json_key, "contains", value) do
    dynamic([r], fragment("? ->> ? ILIKE ?", field(r, ^json_field), ^json_key, ^"%#{value}%"))
  end

  def jsonb_constraint(json_field, json_key, "starts_with", value) do
    dynamic([r], fragment("? ->> ? ILIKE ?", field(r, ^json_field), ^json_key, ^"#{value}%"))
  end

  def jsonb_constraint(json_field, json_key, "ends_with", value) do
    dynamic([r], fragment("? ->> ? ILIKE ?", field(r, ^json_field), ^json_key, ^"%#{value}"))
  end

  def jsonb_constraint(json_field, json_key, constraint, _value) do
    {:error, "Invalid JSONB constraint: #{json_field}.#{json_key}[#{constraint}]"}
  end
end
