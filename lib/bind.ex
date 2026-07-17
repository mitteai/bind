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
    virtual = normalize_virtual(Keyword.get(opts, :virtual, %{}))

    with {:ok, params, virtual_filters} <- extract_virtual(params, virtual),
         :ok <- validate_virtual_sort(params, virtual, schema) do
      case Bind.QueryBuilder.build_where_query(params, allowed_joins) do
        {:error, reason} ->
          {:error, reason}

        where_query ->
          sort_query = Bind.QueryBuilder.build_sort_query(params)

          base =
            schema
            |> where(^where_query)
            |> Bind.QueryBuilder.apply_joins(params, allowed_joins)

          case apply_virtual(base, virtual_filters) do
            {:error, reason} ->
              {:error, reason}

            scoped ->
              scoped
              |> order_by(^Enum.into(sort_query, []))
              |> Bind.QueryBuilder.add_limit_query(params)
              |> Bind.QueryBuilder.add_offset_query(params)
          end
      end
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
        [field_name, constraint] ->
          field = to_string(field_name)
          new_value = map_value(field_mappers, field, constraint, value)
          Map.put(acc, key, new_value)

        # Handle JSONB fields [json_field, json_key, constraint]
        [json_field, json_key, _constraint] when is_binary(json_key) ->
          field = to_string(json_field)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle join fields [assoc, field, constraint, :join]
        [_assoc, field_name, constraint, :join] ->
          field = to_string(field_name)
          new_value = map_value(field_mappers, field, constraint, value)
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

  # `in` values are comma-joined; a custom mapper (e.g. hashed-id decode)
  # must see each element, not the joined string. The mapped value stays a
  # list and flows through query's `in` handling as-is. Without a custom
  # mapper the value is left untouched.
  defp map_value(mappers, field, "in", value) do
    if has_custom_mapper?(mappers, field) do
      mapper = find_mapper(mappers, field)

      value
      |> Bind.QueryBuilder.in_values()
      |> Enum.map(mapper)
    else
      value
    end
  end

  defp map_value(mappers, field, _constraint, value) do
    find_mapper(mappers, field).(value)
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
            [field_name, constraint] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, constraint, field_mappers, acc)

            [json_field, json_key, _constraint] when is_binary(json_key) ->
              field = to_string(json_field)
              handle_map_safe_field(key, value, field, nil, field_mappers, acc)

            [_assoc, field_name, constraint, :join] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, constraint, field_mappers, acc)

            [_assoc, field_name, _json_key, _constraint, :join_jsonb] ->
              field = to_string(field_name)
              handle_map_safe_field(key, value, field, nil, field_mappers, acc)

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
  defp handle_map_safe_field(key, value, field, constraint, field_mappers, acc) do
    mapper = find_mapper(field_mappers, field)
    custom? = has_custom_mapper?(field_mappers, field)

    cond do
      should_skip_transformation?(value) && custom? ->
        {:cont, {:ok, acc}}

      constraint == "in" && custom? ->
        case map_in_safe(mapper, value) do
          {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      true ->
        case apply_mapper_safe(mapper, value) do
          {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end
  end

  # Applies the mapper to each element of an `in` value, halting on the
  # first error. The mapped value stays a list.
  defp map_in_safe(mapper, value) do
    value
    |> Bind.QueryBuilder.in_values()
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, mapped} ->
      case apply_mapper_safe(mapper, element) do
        {:ok, new_value} -> {:cont, {:ok, [new_value | mapped]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, mapped} -> {:ok, Enum.reverse(mapped)}
      {:error, reason} -> {:error, reason}
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

  # Virtual fields — semantics:
  #
  # - `virtual: %{field: fun}` is shorthand for `virtual: %{field: [eq: fun]}`.
  #   Each fun is `(query, value)` and returns the query with the filter
  #   applied, or `{:error, reason}` (a string, matching bind's own error
  #   shape) to reject the value and abort the build.
  # - Undeclared constraints are rejected, never collapsed: with only `eq`
  #   declared, `field[neq]=1` returns {:error, "Invalid constraint: ..."}.
  # - A virtual field shadows a real column of the same name and replaces its
  #   entire constraint surface — undeclared constraints on the column are
  #   rejected too. Multiple declared constraints in one request AND together.
  # - Values arrive as the params map holds them; bind does not normalize
  #   types (the binary query-string path numeric-converts, the map path
  #   doesn't). Exception: `in` is normalized to a list via in_values/1.
  # - Sorting by a virtual-only field is rejected up front; sorting by a
  #   shadowed real column stays legal.
  # - Scopes apply after `where` and `joins:`, before sort/limit/pagination,
  #   so those (including the implicit defaults) wrap the scoped query.
  # - Only the plain `field[op]` form participates; JSONB (`field.key[op]`)
  #   and join (`assoc:field[op]`) notations never match a virtual field.
  # - Composes with map/map_safe: for `in` constraints, mappers apply per
  #   element and the mapped list flows through (see map_value/4).

  # Normalizes both declaration forms to a string-keyed
  # %{"name" => %{"constraint" => fun}} map. Matching happens on strings so
  # user-controlled param names never create atoms here.
  defp normalize_virtual(virtual) do
    Map.new(virtual, fn
      {name, fun} when is_function(fun, 2) ->
        {to_string(name), %{"eq" => fun}}

      {name, constraints} when is_list(constraints) ->
        {to_string(name),
         Map.new(constraints, fn {constraint, fun} when is_function(fun, 2) ->
           {to_string(constraint), fun}
         end)}
    end)
  end

  # Splits params matching a declared virtual field out of the map, pairing
  # each with its scope function. A matching field with an undeclared
  # constraint is an error. Only the plain `field[op]` form participates:
  # the \w+ pattern excludes JSONB (dots) and join (colons) notation.
  defp extract_virtual(params, virtual) when map_size(virtual) == 0 do
    {:ok, params, []}
  end

  defp extract_virtual(params, virtual) do
    result =
      Enum.reduce_while(params, {:ok, params, []}, fn {key, value}, {:ok, remaining, filters} ->
        with true <- is_binary(key),
             [_, name, constraint] <- Regex.run(~r/^(\w+)\[(\w+)\]$/, key),
             %{} = constraints <- Map.get(virtual, name) do
          case Map.get(constraints, constraint) do
            nil ->
              {:halt, {:error, "Invalid constraint: #{name}[#{constraint}]"}}

            fun ->
              filter = {fun, virtual_value(constraint, value)}
              {:cont, {:ok, Map.delete(remaining, key), [filter | filters]}}
          end
        else
          _ -> {:cont, {:ok, remaining, filters}}
        end
      end)

    case result do
      {:ok, remaining, filters} -> {:ok, remaining, Enum.reverse(filters)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp virtual_value("in", value), do: Bind.QueryBuilder.in_values(value)
  defp virtual_value(_constraint, value), do: value

  # Sorting by a virtual-only name would order_by a nonexistent column and
  # raise at Repo.all; reject it up front. A virtual name shadowing a real
  # column stays sortable (the sort hits the column).
  defp validate_virtual_sort(_params, virtual, _schema) when map_size(virtual) == 0, do: :ok

  defp validate_virtual_sort(params, virtual, schema) do
    sort = Map.get(params, "sort")

    if is_binary(sort) and sort != "" do
      name = String.trim_leading(sort, "-")

      if Map.has_key?(virtual, name) and not schema_field?(schema, name) do
        {:error, "Cannot sort by virtual field: #{name}"}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp schema_field?(schema, name) when is_atom(schema) do
    function_exported?(schema, :__schema__, 1) and
      Enum.any?(schema.__schema__(:fields), &(to_string(&1) == name))
  end

  defp schema_field?(_schema, _name), do: false

  defp apply_virtual(query, filters) do
    Enum.reduce_while(filters, query, fn {fun, value}, q ->
      case fun.(q, value) do
        {:error, reason} -> {:halt, {:error, reason}}
        scoped -> {:cont, scoped}
      end
    end)
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
