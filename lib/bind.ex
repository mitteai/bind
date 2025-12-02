## File: bind/lib/bind.ex

defmodule Bind do
  import Ecto.Query

  @doc """
  Merges additional filters with existing query params.
  """
  def filter(query_string, filters) when is_binary(query_string) do
    query_string
    |> Bind.QueryString.to_map()
    |> filter(filters)
  end

  def filter(params, filters) when is_map(params) do
    Map.merge(params, filters)
  end

  @doc """
  Builds an Ecto query for the given schema based on the provided parameters.
  """
  def query(params, schema, opts \\ [])

  def query(params, schema, opts) when is_map(params) do
    allowed_joins = Keyword.get(opts, :joins, [])

    case Bind.QueryBuilder.build_where_query(params, allowed_joins) do
      {:error, reason} ->
        {:error, reason}

      where_query ->
        sort_query = Bind.QueryBuilder.build_sort_query(params)

        schema
        |> where(^where_query)
        |> Bind.QueryBuilder.apply_joins(params, allowed_joins)
        |> order_by(^Enum.into(sort_query, []))
        |> Bind.QueryBuilder.add_limit_query(params)
        |> Bind.QueryBuilder.add_offset_query(params)
    end
  end

  def query(query_string, schema, opts) when is_binary(query_string) do
    query_string
    |> Bind.QueryString.to_map()
    |> query(schema, opts)
  end

  @doc """
  Maps over query parameters, letting you transform values by pattern matching field names.
  """
  def map(query_string, field_mappers) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
    |> map(field_mappers)
  end

  def map(params, field_mappers) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case Bind.Parse.where_field(key) do
        # Handle regular fields [field_name, constraint]
        [field_name, _] ->
          field = to_string(field_name)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle JSONB fields [json_field, json_key, constraint]
        [json_field, json_key, _constraint] when is_binary(json_key) ->
          field = to_string(json_field)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle join fields [assoc, field, constraint, :join]
        [_assoc, field_name, _constraint, :join] ->
          field = to_string(field_name)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle join JSONB fields [assoc, field, json_key, constraint, :join_jsonb]
        [_assoc, field_name, _json_key, _constraint, :join_jsonb] ->
          field = to_string(field_name)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle non-where fields (like start, limit)
        nil ->
          {field, is_negated} =
            case String.starts_with?(key, "-") do
              true -> {String.trim_leading(key, "-"), true}
              false -> {key, false}
            end

          new_value = find_mapper(field_mappers, field).(value)
          final_key = if is_negated, do: "-#{field}", else: field
          Map.put(acc, final_key, new_value)
      end
    end)
  end

  defp find_mapper(mappers, field) do
    case Map.get(mappers, String.to_atom(field)) do
      nil ->
        case Enum.find(mappers, fn
               {%Regex{} = re, _} -> Regex.match?(re, field)
               _ -> false
             end) do
          {_, mapper} -> mapper
          nil -> & &1
        end

      mapper ->
        mapper
    end
  end

  @doc """
  Maps over query parameters with error handling.
  Returns {:ok, mapped_params} on success or {:error, reason} on failure.
  """
  def map_safe(query_string, field_mappers) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
    |> map_safe(field_mappers)
  end

  def map_safe(params, field_mappers) when is_map(params) do
    try do
      result =
        Enum.reduce_while(params, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
          case Bind.Parse.where_field(key) do
            [field_name, _] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, field_mappers, acc)

            [json_field, json_key, _constraint] when is_binary(json_key) ->
              field = to_string(json_field)
              handle_map_safe_field(key, value, field, field_mappers, acc)

            [_assoc, field_name, _constraint, :join] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, field_mappers, acc)

            [_assoc, field_name, _json_key, _constraint, :join_jsonb] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, field_mappers, acc)

            nil ->
              {field, is_negated} =
                case String.starts_with?(key, "-") do
                  true -> {String.trim_leading(key, "-"), true}
                  false -> {key, false}
                end

              mapper = find_mapper(field_mappers, field)

              if should_skip_transformation?(value) && has_custom_mapper?(field_mappers, field) do
                {:cont, {:ok, acc}}
              else
                case apply_mapper_safe(mapper, value) do
                  {:ok, new_value} ->
                    final_key = if is_negated, do: "-#{field}", else: field
                    {:cont, {:ok, Map.put(acc, final_key, new_value)}}

                  {:error, reason} ->
                    {:halt, {:error, reason}}
                end
              end
          end
        end)

      case result do
        {:ok, mapped} -> {:ok, mapped}
        {:error, reason} -> {:error, {:transformation_failed, reason}}
      end
    rescue
      e -> {:error, {:transformation_failed, Exception.message(e)}}
    end
  end

  # Helper for map_safe field handling
  defp handle_map_safe_field(key, value, field, field_mappers, acc) do
    mapper = find_mapper(field_mappers, field)

    if should_skip_transformation?(value) && has_custom_mapper?(field_mappers, field) do
      {:cont, {:ok, acc}}
    else
      case apply_mapper_safe(mapper, value) do
        {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end
  end

  defp apply_mapper_safe(mapper, value) do
    case mapper.(value) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result -> {:ok, result}
    end
  end

  defp should_skip_transformation?(value) do
    value in [nil, ""]
  end

  defp has_custom_mapper?(mappers, field) do
    case Map.get(mappers, String.to_atom(field)) do
      nil ->
        Enum.any?(mappers, fn
          {%Regex{} = re, _} -> Regex.match?(re, field)
          _ -> false
        end)

      _ ->
        true
    end
  end
end
