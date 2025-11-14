defmodule Bind.MapSafeEmptyValuesTest do
  use ExUnit.Case

  defmodule HashIds do
    # Simulates a decoder that fails on nil/empty
    def decode!(id) when id in [nil, ""], do: raise "Cannot decode empty value"
    def decode!(id), do: String.to_integer(id)

    def decode(id) when id in [nil, ""], do: {:error, "empty value"}
    def decode(id), do: {:ok, String.to_integer(id)}
  end

  test "removes key when value is nil" do
    params = %{"user_id[eq]" => nil, "name[eq]" => "alice"}

    result = Bind.map_safe(params, %{
      user_id: fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    assert mapped == %{"name[eq]" => "alice"}
    refute Map.has_key?(mapped, "user_id[eq]")
  end

  test "removes key when value is empty string" do
    params = %{"taskset_id[eq]" => "", "name[eq]" => "test"}

    result = Bind.map_safe(params, %{
      taskset_id: fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    assert mapped == %{"name[eq]" => "test"}
    refute Map.has_key?(mapped, "taskset_id[eq]")
  end

  test "transforms non-empty values normally" do
    params = %{"user_id[eq]" => "123", "taskset_id[eq]" => ""}

    result = Bind.map_safe(params, %{
      user_id: fn id -> HashIds.decode!(id) end,
      taskset_id: fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    assert mapped == %{"user_id[eq]" => 123}
    refute Map.has_key?(mapped, "taskset_id[eq]")
  end

  test "handles mix of nil, empty, and valid values" do
    params = %{
      "user_id[eq]" => "123",
      "team_id[eq]" => nil,
      "org_id[eq]" => "",
      "name[eq]" => "test"
    }

    result = Bind.map_safe(params, %{
      ~r/_id$/i => fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    assert mapped == %{
      "user_id[eq]" => 123,
      "name[eq]" => "test"
    }
    refute Map.has_key?(mapped, "team_id[eq]")
    refute Map.has_key?(mapped, "org_id[eq]")
  end

  test "removes pagination params with empty values" do
    params = %{"start" => "", "limit" => "10"}

    result = Bind.map_safe(params, %{
      start: fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    assert mapped == %{"limit" => "10"}
    refute Map.has_key?(mapped, "start")
  end

  test "keeps keys that don't have mappers even if empty" do
    params = %{"user_id[eq]" => "", "name[eq]" => ""}

    result = Bind.map_safe(params, %{
      user_id: fn id -> HashIds.decode!(id) end
    })

    assert {:ok, mapped} = result
    # user_id is removed (has mapper + empty)
    # name is kept (no mapper)
    assert mapped == %{"name[eq]" => ""}
    refute Map.has_key?(mapped, "user_id[eq]")
  end
end
