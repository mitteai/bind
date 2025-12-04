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

  def build_where_query(params, allowed_joins \\ []) do
    case validate_where_query(params, allowed_joins) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        Enum.reduce(params, Ecto.Query.dynamic(true), fn {param, param_value}, dynamic ->
          case Bind.Parse.where_field(param) do
            nil ->
              dynamic

            # Join fields - skip in where, handled separately
            [_assoc, _field, _constraint, :join] ->
              dynamic

            [_assoc, _field, _json_key, _constraint, :join_jsonb] ->
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

  def validate_where_query(params, allowed_joins \\ []) do
    Enum.find_value(params, fn {param, param_value} ->
      case Bind.Parse.where_field(param) do
        nil ->
          nil

        # Validate join is allowed
        [assoc, _field, _constraint, :join] ->
          if assoc in allowed_joins do
            nil
          else
            {:error, "Join not allowed: #{assoc}"}
          end

        # Validate join_jsonb is allowed
        [assoc, _field, _json_key, _constraint, :join_jsonb] ->
          if assoc in allowed_joins do
            nil
          else
            {:error, "Join not allowed: #{assoc}"}
          end

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

  @doc """
  Extracts join fields from params and groups by association.
  Returns map of %{assoc_name => [{:field, field, constraint, value} | {:jsonb, field, json_key, constraint, value}, ...]}
  """
  def extract_joins(params) do
    Enum.reduce(params, %{}, fn {param, value}, acc ->
      case Bind.Parse.where_field(param) do
        [assoc, field, constraint, :join] ->
          joins = Map.get(acc, assoc, [])
          Map.put(acc, assoc, [{:field, field, constraint, value} | joins])

        [assoc, field, json_key, constraint, :join_jsonb] ->
          joins = Map.get(acc, assoc, [])
          Map.put(acc, assoc, [{:jsonb, field, json_key, constraint, value} | joins])

        _ ->
          acc
      end
    end)
  end

  @doc """
  Builds join clauses and where conditions for joined associations.
  """
  def apply_joins(query, params, allowed_joins) do
    joins = extract_joins(params)

    Enum.reduce(joins, query, fn {assoc, constraints}, q ->
      if assoc in allowed_joins do
        # Add join
        q = join(q, :inner, [r], j in assoc(r, ^assoc), as: ^assoc)

        # Add where conditions for this join
        Enum.reduce(constraints, q, fn
          {:field, field, constraint, value}, q2 ->
            dynamic = join_constraint(assoc, field, constraint, value)
            where(q2, ^dynamic)

          {:jsonb, field, json_key, constraint, value}, q2 ->
            dynamic = join_jsonb_constraint(assoc, field, json_key, constraint, value)
            where(q2, ^dynamic)
        end)
      else
        q
      end
    end)
  end

  def constraint(field, "search", value) do
    tsquery =
      value
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"#{&1}:*")
      |> Enum.join(" & ")

    dynamic([r], fragment("? @@ to_tsquery('simple', ?)", field(r, ^field), ^tsquery))
  end

  defp join_constraint(assoc, field, "search", value) do
    tsquery =
      value
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&"#{&1}:*")
      |> Enum.join(" & ")

    dynamic([{^assoc, j}], fragment("? @@ to_tsquery('simple', ?)", field(j, ^field), ^tsquery))
  end

  # Build dynamic for join constraint
  defp join_constraint(assoc, field, "eq", value) do
    dynamic([{^assoc, j}], field(j, ^field) == ^value)
  end

  defp join_constraint(assoc, field, "neq", value) do
    dynamic([{^assoc, j}], field(j, ^field) != ^value)
  end

  defp join_constraint(assoc, field, "gt", value) do
    dynamic([{^assoc, j}], field(j, ^field) > ^value)
  end

  defp join_constraint(assoc, field, "gte", value) do
    dynamic([{^assoc, j}], field(j, ^field) >= ^value)
  end

  defp join_constraint(assoc, field, "lt", value) do
    dynamic([{^assoc, j}], field(j, ^field) < ^value)
  end

  defp join_constraint(assoc, field, "lte", value) do
    dynamic([{^assoc, j}], field(j, ^field) <= ^value)
  end

  defp join_constraint(assoc, field, "contains", value) do
    dynamic([{^assoc, j}], ilike(field(j, ^field), ^"%#{value}%"))
  end

  defp join_constraint(assoc, field, "starts_with", value) do
    dynamic([{^assoc, j}], ilike(field(j, ^field), ^"#{value}%"))
  end

  defp join_constraint(assoc, field, "ends_with", value) do
    dynamic([{^assoc, j}], ilike(field(j, ^field), ^"%#{value}"))
  end

  defp join_constraint(assoc, field, "true", _value) do
    dynamic([{^assoc, j}], field(j, ^field) == true)
  end

  defp join_constraint(assoc, field, "false", _value) do
    dynamic([{^assoc, j}], field(j, ^field) == false)
  end

  defp join_constraint(assoc, field, "nil", value) when value in ["true", true] do
    dynamic([{^assoc, j}], is_nil(field(j, ^field)))
  end

  defp join_constraint(assoc, field, "nil", value) when value in ["false", false] do
    dynamic([{^assoc, j}], not is_nil(field(j, ^field)))
  end

  defp join_constraint(assoc, field, "in", value) do
    values = String.split(value, ",")
    dynamic([{^assoc, j}], field(j, ^field) in ^values)
  end

  # Build dynamic for join JSONB constraint
  defp join_jsonb_constraint(assoc, field, json_key, "eq", value) do
    dynamic([{^assoc, j}], fragment("? ->> ? = ?", field(j, ^field), ^json_key, ^value))
  end

  defp join_jsonb_constraint(assoc, field, json_key, "contains", value) do
    dynamic(
      [{^assoc, j}],
      fragment("? ->> ? ILIKE ?", field(j, ^field), ^json_key, ^"%#{value}%")
    )
  end

  defp join_jsonb_constraint(assoc, field, json_key, "starts_with", value) do
    dynamic([{^assoc, j}], fragment("? ->> ? ILIKE ?", field(j, ^field), ^json_key, ^"#{value}%"))
  end

  defp join_jsonb_constraint(assoc, field, json_key, "ends_with", value) do
    dynamic([{^assoc, j}], fragment("? ->> ? ILIKE ?", field(j, ^field), ^json_key, ^"%#{value}"))
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
