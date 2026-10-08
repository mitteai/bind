defmodule Bind.CountTest do
  use ExUnit.Case
  import Ecto.Query

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
      field(:age, :integer)
      field(:team_id, :integer)
    end
  end

  describe "count?/1" do
    test "is true for count=true and count=1" do
      assert Bind.count?(%{"count" => "true"})
      assert Bind.count?(%{"count" => "1"})
      assert Bind.count?(%{"count" => true})
      assert Bind.count?("name[eq]=Alice&count=true")
      assert Bind.count?("count=1")
    end

    test "is false without the key or with any other value" do
      refute Bind.count?(%{})
      refute Bind.count?(%{"count" => "false"})
      refute Bind.count?(%{"count" => ""})
      refute Bind.count?("name[eq]=Alice")
    end
  end

  describe "count/1" do
    test "keeps the filters, drops sort and limit, selects the count" do
      query = Bind.query("name[eq]=Alice&age[gte]=30&sort=-age&limit=5", User)
      counted = inspect(Bind.count(query))

      assert counted =~ "select: count()"
      assert counted =~ "name == ^\"Alice\""
      assert counted =~ "age >= ^30"
      refute counted =~ "order_by"
      refute counted =~ "limit"
    end

    test "keeps the cursor: it counts what the request would page through" do
      query = Bind.query(%{"name[eq]" => "Alice", "-start" => 10}, User)
      counted = inspect(Bind.count(query))

      assert counted =~ "id < ^10"
    end

    test "keeps scopes piped after query/3 and drops their preloads" do
      query =
        "age[gte]=30"
        |> Bind.query(User)
        |> where([u], u.team_id == 7)
        |> preload(:team)

      counted = inspect(Bind.count(query))

      assert counted =~ "team_id == 7"
      assert counted =~ "select: count()"
      refute counted =~ "preload"
    end

    test "counts a scope's distinct rows, not the distinct of the count" do
      query = "age[gte]=30" |> Bind.query(User) |> distinct(true)
      counted = inspect(Bind.count(query))

      # the distinct lives in the subquery, the count wraps it
      assert counted =~ "from u0 in subquery("
      assert counted =~ "distinct: true"
      assert counted =~ "select: count()"
    end

    test "the count query is unlimited even without an explicit limit param" do
      # query/3 limits to 10 by default; the count must not inherit that
      query = Bind.query(%{}, User)
      assert inspect(query) =~ "limit: 10"
      refute inspect(Bind.count(query)) =~ "limit"
    end
  end
end
