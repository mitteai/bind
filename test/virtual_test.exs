defmodule Bind.VirtualTest do
  use ExUnit.Case
  import Ecto.Query

  defmodule ChatMessage do
    use Ecto.Schema

    schema "chat_messages" do
      field(:chat_id, :integer)
      field(:asset_id, :integer)
    end
  end

  defmodule Chat do
    use Ecto.Schema

    schema "chats" do
      field(:user_id, :integer)
      field(:subject, :string)
      field(:options, :map)
      field(:updated_at, :naive_datetime)
    end
  end

  # Has a real asset_id column, for shadowing tests.
  defmodule Message do
    use Ecto.Schema

    schema "messages" do
      field(:asset_id, :integer)
      field(:body, :string)
    end
  end

  defp scope_by_asset(query, asset_id) do
    chat_ids =
      from(m in ChatMessage, where: m.asset_id == ^asset_id, select: m.chat_id)

    from(c in query, where: c.id in subquery(chat_ids))
  end

  # Captures the value the scope was called with, applies nothing.
  defp capture_scope(tag) do
    test_pid = self()

    fn query, value ->
      send(test_pid, {tag, value})
      query
    end
  end

  test "virtual scope applies alongside regular column filters" do
    params = %{"user_id[eq]" => 7, "asset_id[eq]" => 123}

    query = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})
    query_string = inspect(query)

    assert query_string =~ "user_id == ^7"
    assert query_string =~ "subquery"
    assert query_string =~ "asset_id == ^123"
  end

  test "sort, limit and pagination are preserved around the scoped query" do
    params = %{
      "asset_id[eq]" => 123,
      "sort" => "-updated_at",
      "limit" => 5,
      "start" => 10
    }

    query = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})
    query_string = inspect(query)

    assert query_string =~ "desc"
    assert query_string =~ "updated_at"
    assert query_string =~ "limit: ^5"
    assert query_string =~ "id > ^10"
  end

  test "default sort and limit still apply to a virtual-scoped query" do
    params = %{"asset_id[eq]" => 123}

    query = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})
    query_string = inspect(query)

    assert query_string =~ "asc"
    assert query_string =~ "limit"
  end

  test "undeclared constraint on a virtual field is rejected with bind's error shape" do
    params = %{"asset_id[neq]" => 1}

    result = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})

    assert result == {:error, "Invalid constraint: asset_id[neq]"}
  end

  test "keyword form routes eq and in to their declared functions" do
    params = %{"asset_id[eq]" => "1"}

    Bind.query(params, Chat,
      virtual: %{asset_id: [eq: capture_scope(:eq), in: capture_scope(:in)]}
    )

    assert_received {:eq, "1"}
    refute_received {:in, _}

    params = %{"asset_id[in]" => "1,2,3"}

    Bind.query(params, Chat,
      virtual: %{asset_id: [eq: capture_scope(:eq), in: capture_scope(:in)]}
    )

    assert_received {:in, ["1", "2", "3"]}
    refute_received {:eq, _}
  end

  test "in value: binary is comma-split into a list" do
    params = %{"asset_id[in]" => "a,b"}

    Bind.query(params, Chat, virtual: %{asset_id: [in: capture_scope(:in)]})

    assert_received {:in, ["a", "b"]}
  end

  test "in value: a list passes through as-is" do
    params = %{"asset_id[in]" => [123, 456]}

    Bind.query(params, Chat, virtual: %{asset_id: [in: capture_scope(:in)]})

    assert_received {:in, [123, 456]}
  end

  test "in value: a non-binary scalar is wrapped in a list" do
    params = %{"asset_id[in]" => 5}

    Bind.query(params, Chat, virtual: %{asset_id: [in: capture_scope(:in)]})

    assert_received {:in, [5]}
  end

  test "two declared constraints in one request both apply" do
    params = %{"asset_id[eq]" => "1", "asset_id[in]" => "1,2"}

    Bind.query(params, Chat,
      virtual: %{asset_id: [eq: capture_scope(:eq), in: capture_scope(:in)]}
    )

    assert_received {:eq, "1"}
    assert_received {:in, ["1", "2"]}
  end

  test "scope returning {:error, reason} aborts the build" do
    params = %{"asset_id[eq]" => 123, "user_id[eq]" => 7}

    result =
      Bind.query(params, Chat,
        virtual: %{asset_id: fn _query, _value -> {:error, "no such asset"} end}
      )

    assert result == {:error, "no such asset"}
  end

  test "virtual shadows a real column" do
    test_pid = self()

    params = %{"asset_id[eq]" => 9}

    query =
      Bind.query(params, Message,
        virtual: %{
          asset_id: fn q, v ->
            send(test_pid, {:scoped, v})
            where(q, [m], m.body == ^"scoped:#{v}")
          end
        }
      )

    query_string = inspect(query)

    assert_received {:scoped, 9}
    assert query_string =~ "scoped:9"
    refute query_string =~ "asset_id == ^9"
  end

  test "undeclared constraint on a shadowed column is rejected, not passed through" do
    params = %{"asset_id[gte]" => 3}

    result = Bind.query(params, Message, virtual: %{asset_id: capture_scope(:eq)})

    assert result == {:error, "Invalid constraint: asset_id[gte]"}
    refute_received {:eq, _}
  end

  test "sorting by a virtual-only field is rejected" do
    params = %{"asset_id[eq]" => 1, "sort" => "-asset_id"}

    result = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})

    assert result == {:error, "Cannot sort by virtual field: asset_id"}
  end

  test "sorting by a shadowed column stays legal and sorts by the column" do
    params = %{"asset_id[eq]" => 1, "sort" => "-asset_id"}

    query = Bind.query(params, Message, virtual: %{asset_id: capture_scope(:eq)})
    query_string = inspect(query)

    assert_received {:eq, 1}
    assert query_string =~ "desc"
    assert query_string =~ "asset_id"
  end

  test "binary query-string path numeric-converts before the scope sees the value" do
    Bind.query("asset_id[eq]=123", Chat, virtual: %{asset_id: capture_scope(:eq)})

    assert_received {:eq, 123}
  end

  test "raw query-string form works end to end" do
    query =
      Bind.query("asset_id[eq]=abc&user_id[eq]=7", Chat,
        virtual: %{asset_id: &scope_by_asset/2}
      )

    query_string = inspect(query)

    assert query_string =~ "user_id == ^7"
    assert query_string =~ "subquery"
  end

  test "virtual option present with no matching param changes nothing" do
    params = %{"user_id[eq]" => 7}

    with_virtual = Bind.query(params, Chat, virtual: %{asset_id: &scope_by_asset/2})
    without = Bind.query(params, Chat)

    assert inspect(with_virtual) == inspect(without)
  end

  test "JSONB notation never matches a virtual field" do
    params = %{"options.foo[eq]" => "x"}

    query = Bind.query(params, Chat, virtual: %{options: capture_scope(:jsonb)})
    query_string = inspect(query)

    refute_received {:jsonb, _}
    assert query_string =~ "fragment"
  end

  test "join notation never matches a virtual field" do
    params = %{"chat:asset_id[eq]" => 1}

    result = Bind.query(params, Message, virtual: %{asset_id: capture_scope(:eq)})

    refute_received {:eq, _}
    assert result == {:error, "Join not allowed: chat"}
  end
end
