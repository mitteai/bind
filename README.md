# Bind

Define an API controller like this:

```ex
def index(conn, _params) do
  users = conn.query_string
    |> Bind.query(User)
    |> Repo.all()

  render(conn, :index, result: users)
end
```

Now your endpoint supports all these queries out of the box:

```
GET /users?name[contains]=john&sort=-id&limit=25
GET /users?salary[gte]=50000&location[eq]=berlin
GET /users?joined_at[lt]=2024-01-01&status[neq]=disabled
GET /users?options.prompt[contains]=motorbike
```

Bind is a flexible and dynamic Ecto query builder, for retrieving data flexibly without writing custom queries for each use case.

## Installation

Add `bind` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bind, "~> 0.6.0"}
  ]
end
```

## API

```ex
Bind.query(schema, params)
```

Parameters:

-   `schema`: The Ecto schema module (e.g., `MyApp.User`).
-   `params`: Either a map of query parameters or a query string.

Returns: An Ecto query.

## Usage Example

Create Ecto query:

```ex
query = Bind.query(%{ "name[eq]" => "Alice", "age[gte]" => 30 }, MyApp.User)
```

Alternatively, with a query string:

```ex
query = Bind.query("?name[eq]=Alice&age[gte]=30", MyApp.User)
```

And finally run the query to get results from the database:

```ex
results = Repo.all(query)
```

Here's how it looks in a controller:

```ex
def index(conn, params) do
  images = conn.query_string
    |> Bind.query(MyApp.Media.Image)
    |> MyApp.Repo.all()

  render(conn, :index, result: images)
end
```

Error handling

```ex
case Bind.query(%{ "name[eq]" => "Alice", "age[gte]" => 30 }, MyApp.User) do
  {:error, reason} ->
    IO.puts("Error building query: #{reason}")

  query ->
    results = Repo.all(query)
end
```

### Filtering

Examples:

```ex
%{"name[eq]" => "Alice", "age[gte]" => 30}
```

```ex
%{
  "name[starts_with]" => "A",
  "age[gte]" => 18,
  "role[in]" => "superuser,admin,mod",
  "is_active[true]" => "",
  "last_login[nil]" => false
}
```

List of comparison operators supported:

-   `eq`: Equal to
-   `neq`: Not equal to
-   `gt`: Greater than
-   `gte`: Greater than or equal to
-   `lt`: Less than
-   `lte`: Less than or equal to
-   `true`: Boolean true
-   `false`: Boolean false
-   `starts_with`: String starts with
-   `ends_with`: String ends with
-   `in`: In a list of values
-   `contains`: String contains
-   `nil`: Is nil (or is not nil)

### JSONB Search

For PostgreSQL JSONB columns, use dot notation to search within JSON fields:

```ex
%{"options.prompt[contains]" => "motorbike"}
%{"metadata.duration[eq]" => "5"}
%{"config.settings[starts_with]" => "prod"}
```

Examples in URLs:
```
GET /videos?options.prompt[contains]=motorbike
GET /users?preferences.theme[eq]=dark
GET /posts?metadata.tags[contains]=elixir
```

Supported JSONB operators:
- `eq`: Exact match
- `contains`: Case-insensitive substring search
- `starts_with`: Case-insensitive prefix search
- `ends_with`: Case-insensitive suffix search

### Sorting

Use the `sort` parameter to specify sorting order:

-   Prefix with `-` for descending order
-   No prefix for ascending order

```ex
%{"sort" => "-age"}  # Sort by age descending
%{"sort" => "age"}  # Sort by age ascending
```

If nothing specified, sorts by ID field ascending.

### Pagination

-   `limit`: Specify the maximum number of results (default: 10)
-   `start`: Specify the starting ID for pagination

Example:

```ex
%{"limit" => 20, "start" => 100}
```

- For ascending order (default): `start=100`
- For descending order, use leading dash: `-start=100`

Example for descending pagination:
```
GET /users?sort=-created_at&-start=-100
```

### Query String Support

In a typical Phoenix controller, you can simply pass `conn.query_string` and get Ecto query back:

```ex
query_string = conn.query_string
    |> Bind.query(query_string, MyApp.User)
    |> MyApp.Repo.all()
```

### Transforming Query Parameters

You can transform filter values before query is built:

```ex
"user_id[eq]=123&team_id[eq]=456"
  |> Bind.map(%{
    user_id: fn id -> HashIds.decode(id) end,
    team_id: fn id -> HashIds.decode(id) end
  })
  |> Bind.query(MyApp.User)
  |> Repo.all()
```


Transform specific fields

```ex
Bind.map(params, %{
  user_id: fn id -> HashIds.decode(id) end,
  name: &String.upcase/1
})
```

Transform multiple fields with regex pattern:

```ex
Bind.map(params, %{
  ~r/_id$/i => fn id -> HashIds.decode(id) end
})
```

Note: Value transformation only applies to filter fields (e.g. [eq], [gte]), not to sort/limit/pagination params.

### Safe Parameter Transformation

Use `Bind.map_safe/2` when transformations might fail. It returns `{:ok, mapped_params}` on success or `{:error, reason}` on failure:
```ex
params
|> Bind.map_safe(%{
  asset_id: fn hash -> HashIds.decode!(hash) end
})
```

`map_safe/2` automatically handles Result tuples (`{:ok, value}` / `{:error, reason}`) returned by mapper functions:
```ex
# Mapper returns {:ok, value} - automatically unwrapped
params
|> Bind.map_safe(%{
  asset_id: fn hash -> decode_id(hash) end  # returns {:ok, id}
})
# => {:ok, %{"asset_id[eq]" => id}}

# Mapper returns {:error, reason} - propagated as error
params
|> Bind.map_safe(%{
  asset_id: fn hash -> decode_id(hash) end  # returns {:error, "invalid"}
})
# => {:error, {:transformation_failed, "invalid"}}

# Mix of return types works seamlessly
Bind.map_safe(params, %{
  user_id: fn id -> decode(id) end,      # {:ok, val} or {:error, reason}
  team_id: fn id -> decode!(id) end,     # val or raises
  name: &String.upcase/1                 # val directly
})
```

**Empty value handling:**

Empty values (`nil` or `""`) are automatically removed from the result if a mapper is defined for that field. Fields without mappers preserve empty values:

```ex
params = %{"user_id[eq]" => "", "name[eq]" => ""}

Bind.map_safe(params, %{
  user_id: fn id -> decode!(id) end
})

# => {:ok, %{"name[eq]" => ""}}
# user_id[eq] is removed (has mapper + empty value)
# name[eq] is kept (no mapper)
```

**Difference between `map/2` and `map_safe/2`:**

- `Bind.map/2`: Raises exceptions if transformation fails (use when you're confident inputs are valid)
- `Bind.map_safe/2`: Returns error tuples if transformation fails (use when inputs might be invalid)

```ex
# map/2 - raises on error
Bind.map(params, %{id: &decode!/1})
# => raises if decode! fails

# map_safe/2 - returns error tuple
Bind.map_safe(params, %{id: &decode!/1})
# => {:ok, mapped} or {:error, {:transformation_failed, reason}}
```

### Access Control with Filters

You can use filters to enforce access control and limit what users can query. Filters compose nicely with the query builder:

```ex
def index(conn, _params) do
  my_posts = conn.query_string
    # User can only see their own posts
    |> Bind.filter(%{"user_id[eq]" => conn.assigns.current_user.id})
    # That are active
    |> Bind.filter(%{"active[true]" => true})
    |> Bind.query(Post)
    |> Repo.all()

  render(conn, :index, posts: my_posts)
end
```
