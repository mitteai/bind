defmodule Bind do
  import Ecto.Query

  @doc """
  Merges additional filters with existing query params.

  ## Examples
      # Only allow users to see their own posts
      conn.query_string
        |> Bind.filter(%{"user_id[eq]" => current_user.id})
        |> Bind.query(Post)

      # Scope to team and active status
      params
        |> Bind.filter(%{"team_id[eq]" => team_id})
        |> Bind.filter(%{"active[true]" => true})
        |> Bind.query(Post)
  """
  def filter(query_string, filters) when is_binary(query_string) do
    query_string
    |> Bind.QueryString.to_map()
    |> filter(filters)
  end

  def filter(params, filters) when is_map(params) do
    Map.merge(params, filters)
  end

  @moduledoc """
  `Bind` provides functionality to build dynamic Ecto queries based on given parameters.
  It allows developers to retrieve data flexibly without writing custom queries for each use case.

  ## Examples

  Given an Ecto schema module `MyApp.User` and a map of query parameters, you can build and run a query like this:

      > params = %{ "name[eq]" => "Alice", "age[gte]" => 30, "sort" => "-age", "limit" => "10" }
      > query = Bind.query(params, MyApp.User)
      > results = Repo.all(query)
      > IO.inspect(results)

  Or, you can pipe:

      > %{ "name[eq]" => "Alice", "age[gte]" => 30, "sort" => "-age", "limit" => "10" }
      |> Bind.query(MyApp.User)
      |> Repo.all()
      |> IO.inspect()

  If you're in a Phoenix controller:

      def index(conn, params) do
        users = conn.query_string
          |> Bind.decode_query()
          |> Bind.query(MyApp.User)
          |> Repo.all()

  render(conn, "index.json", users: users)
      end
  """

  @doc """
  Builds an Ecto query for the given schema based on the provided parameters.

  ## Parameters
      - `params`: A map of query parameters.
      - `schema`: The Ecto schema module (e.g., `MyApp.User`).
      - `opts`: Optional keyword list with:
        - `:joins` - List of allowed association names for join queries

  ## Examples

      > params = %{"name[eq]" => "Alice", "age[gte]" => "30", "sort" => "-age"}
      > Bind.query(MyApp.User, params)
      #Ecto.Query<from u0 in MyApp.User, where: u0.name == ^"Alice", where: u0.age >= ^30, order_by: [desc: u0.age]>

      # With joins
      > params = %{"current_version:content_title[contains]" => "cat"}
      > Bind.query(params, MyApp.Asset, joins: [:current_version])

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

  @doc """
  Builds an Ecto query for the given schema based on the provided query string.

  ## Parameters
    - `query_string`: The query string from a URL.
    - `schema`: The Ecto schema module (e.g., `MyApp.User`).
    - `opts`: Optional keyword list with:
      - `:joins` - List of allowed association names for join queries

  ## Examples
      > query_string = "?name[eq]=Alice&age[gte]=30&sort=-age&limit=10"
      > Bind.query(query_string, MyApp.User)
      #Ecto.Query<from u0 in MyApp.User, where: u0.name == ^"Alice", where: u0.age >= ^30, order_by: [desc: u0.age]>

      # With joins
      > Bind.query("current_version:content_title[contains]=cat", MyApp.Asset, joins: [:current_version])
  """
  def query(query_string, schema, opts) when is_binary(query_string) do
    query_string
    |> Bind.QueryString.to_map()
    |> query(schema, opts)
  end

  @doc """
  Maps over query parameters, letting you transform values by pattern matching field names.

  ## Example

      # Simple value transformation
      qs = "user_id[eq]=123&team_id[in]=456,789"

      Bind.map(qs, %{
        user_id: fn id -> HashIds.decode(id) end,
        team_id: fn ids ->
          ids
          |> String.split(",")
          |> Enum.map(&HashIds.decode/1)
          |> Enum.join(",")
        end
      })

      # Pattern matching fields
      qs = "org_id[eq]=123&user_id[eq]=456"
      Bind.map(qs, %{
        ~r/^.*_id$/i => fn id -> HashIds.decode(id) end
      })
  """
  def map(query_string, field_mappers) when is_binary(query_string) do
    query_string
    |> URI.decode_query()
    |> map(field_mappers)
  end

  @doc """
  Maps over query parameters using field transformer functions.

  ## Parameters
   - `params`: Map of query parameters (e.g. %{"user_id[eq]" => "123"})
   - `field_mappers`: Map of field names to transformer functions.
      Can contain atom keys for exact matches or regex patterns for flexible matching.

  ## Examples

     # Transform specific fields
     params = %{"user_id[eq]" => "123", "name[eq]" => "alice"}
     Bind.map(params, %{
       user_id: fn id -> HashIds.decode(id) end,
       name: &String.upcase/1
     })
     # => %{"user_id[eq]" => "u_123", "name[eq]" => "ALICE"}

     # Transform multiple fields with regex pattern
     params = %{"user_id[eq]" => "123", "team_id[eq]" => "456"}
     Bind.map(params, %{
       ~r/_id$/i => fn id -> HashIds.decode(id) end
     })
     # => %{"user_id[eq]" => "u_123", "team_id[eq]" => "t_456"}

  Note: Only transforms values for where conditions (e.g. [eq], [gte]).
  Other parameters like sort, limit etc. are preserved unchanged.
  """
  def map(params, field_mappers) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case Bind.Parse.where_field(key) do
        # Handle regular fields [field_name, constraint]
        [field_name, _] ->
          field = to_string(field_name)
          # Try exact match first, then regex patterns for where fields
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle JSONB fields [json_field, json_key, constraint]
        [json_field, _json_key, _constraint] when is_binary(_json_key) ->
          field = to_string(json_field)
          # Apply mapper to the main JSON field (e.g., "options")
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle join fields [assoc, field, constraint, :join]
        [_assoc, field_name, _constraint, :join] ->
          field = to_string(field_name)
          new_value = find_mapper(field_mappers, field).(value)
          Map.put(acc, key, new_value)

        # Handle non-where fields (like start, limit)
        nil ->
          # For non-where fields (like start, limit), check if it's negated
          {field, is_negated} =
            case String.starts_with?(key, "-") do
              true -> {String.trim_leading(key, "-"), true}
              false -> {key, false}
            end

          # Find mapper using non-negated field name
          new_value = find_mapper(field_mappers, field).(value)

          # Restore the negative prefix if it was present
          final_key = if is_negated, do: "-#{field}", else: field
          Map.put(acc, final_key, new_value)
      end
    end)
  end

  defp find_mapper(mappers, field) do
    # Try exact match
    case Map.get(mappers, String.to_atom(field)) do
      nil ->
        # Try regex patterns
        case Enum.find(mappers, fn
               {%Regex{} = re, _} -> Regex.match?(re, field)
               _ -> false
             end) do
          {_, mapper} -> mapper
          # identity function if no match
          nil -> & &1
        end

      mapper ->
        mapper
    end
  end

  # Add this to lib/bind.ex after the existing map/2 function

  @doc """
  Maps over query parameters with error handling.
  Returns {:ok, mapped_params} on success or {:error, reason} on failure.

  ## Examples

      # Success case
      params = %{"user_id[eq]" => "valid_hash"}
      {:ok, mapped} = Bind.map_safe(params, %{
        user_id: fn id -> HashIds.decode!(id) end
      })

      # Error case
      params = %{"user_id[eq]" => "bad_hash"}
      {:error, {:transformation_failed, reason}} = Bind.map_safe(params, %{
        user_id: fn id -> HashIds.decode!(id) end
      })

      # Use in controller with pattern matching
      case Bind.map_safe(params, %{asset_id: &decode_id!/1}) do
        {:ok, attrs} -> create_resource(attrs)
        {:error, _} -> send_error_response()
      end
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
              mapper = find_mapper(field_mappers, field)

              # Only skip if value is empty AND there's an actual mapper (not identity)
              if should_skip_transformation?(value) && has_custom_mapper?(field_mappers, field) do
                {:cont, {:ok, acc}}
              else
                case apply_mapper_safe(mapper, value) do
                  {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end
              end

            [json_field, _json_key, _constraint] when is_binary(_json_key) ->
              field = to_string(json_field)
              mapper = find_mapper(field_mappers, field)

              # Only skip if value is empty AND there's an actual mapper (not identity)
              if should_skip_transformation?(value) && has_custom_mapper?(field_mappers, field) do
                {:cont, {:ok, acc}}
              else
                case apply_mapper_safe(mapper, value) do
                  {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end
              end

            # Handle join fields [assoc, field, constraint, :join]
            [_assoc, field_name, _constraint, :join] ->
              field = to_string(field_name)
              mapper = find_mapper(field_mappers, field)

              if should_skip_transformation?(value) && has_custom_mapper?(field_mappers, field) do
                {:cont, {:ok, acc}}
              else
                case apply_mapper_safe(mapper, value) do
                  {:ok, new_value} -> {:cont, {:ok, Map.put(acc, key, new_value)}}
                  {:error, reason} -> {:halt, {:error, reason}}
                end
              end

            nil ->
              {field, is_negated} =
                case String.starts_with?(key, "-") do
                  true -> {String.trim_leading(key, "-"), true}
                  false -> {key, false}
                end

              mapper = find_mapper(field_mappers, field)

              # Only skip if value is empty AND there's an actual mapper (not identity)
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

  # Apply mapper and handle result tuples
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
    # Check if there's an actual mapper (not identity function)
    case Map.get(mappers, String.to_atom(field)) do
      nil ->
        # Check regex patterns
        Enum.any?(mappers, fn
          {%Regex{} = re, _} -> Regex.match?(re, field)
          _ -> false
        end)

      _ ->
        true
    end
  end
end
