defmodule Bind.MapSafeTest do
  use ExUnit.Case

  defmodule HashIds do
    def decode!(id) do
      case id do
        "valid_123" -> 123
        "valid_456" -> 456
        _ -> raise "Invalid hash"
      end
    end

    def decode(id) do
      case id do
        "valid_123" -> {:ok, 123}
        "valid_456" -> {:ok, 456}
        _ -> {:error, "invalid hash"}
      end
    end
  end

  describe "map_safe/2 with successful transformations" do
    test "transforms field values successfully" do
      params = %{"user_id[eq]" => "valid_123", "name[eq]" => "alice"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode!(id) end,
          name: &String.upcase/1
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "name[eq]" => "ALICE"
             }
    end

    test "transforms multiple ID fields with regex pattern" do
      params = %{
        "user_id[eq]" => "valid_123",
        "team_id[eq]" => "valid_456",
        "name[eq]" => "test"
      }

      result =
        Bind.map_safe(params, %{
          ~r/_id$/i => fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "team_id[eq]" => 456,
               "name[eq]" => "test"
             }
    end

    test "transforms query string successfully" do
      query_string = "user_id[eq]=valid_123&team_id[eq]=valid_456"

      result =
        Bind.map_safe(query_string, %{
          user_id: fn id -> HashIds.decode!(id) end,
          team_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "team_id[eq]" => 456
             }
    end

    test "keeps unmapped fields unchanged" do
      params = %{"user_id[eq]" => "valid_123", "name[eq]" => "alice"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "name[eq]" => "alice"
             }
    end

    test "transforms pagination parameters" do
      params = %{"start" => "valid_123", "user_id[eq]" => "valid_456"}

      result =
        Bind.map_safe(params, %{
          start: fn id -> HashIds.decode!(id) end,
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "start" => 123,
               "user_id[eq]" => 456
             }
    end

    test "preserves negative start parameter" do
      params = %{"-start" => "valid_123"}

      result =
        Bind.map_safe(params, %{
          start: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result
      assert mapped == %{"-start" => 123}
    end

    test "transforms JSONB field parameters" do
      params = %{"options.prompt[contains]" => "UPPERCASE"}

      result =
        Bind.map_safe(params, %{
          options: &String.downcase/1
        })

      assert {:ok, mapped} = result
      assert mapped == %{"options.prompt[contains]" => "uppercase"}
    end
  end

  describe "map_safe/2 with transformation errors" do
    test "returns error when transformation raises exception" do
      params = %{"user_id[eq]" => "invalid_hash"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:error, {:transformation_failed, message}} = result
      assert message =~ "Invalid hash"
    end

    test "returns error on first failing transformation" do
      params = %{
        "user_id[eq]" => "valid_123",
        "team_id[eq]" => "invalid_hash",
        "org_id[eq]" => "valid_456"
      }

      result =
        Bind.map_safe(params, %{
          ~r/_id$/i => fn id -> HashIds.decode!(id) end
        })

      assert {:error, {:transformation_failed, _}} = result
    end

    test "handles nil value transformation errors" do
      params = %{"user_id[eq]" => "bad_value"}

      result =
        Bind.map_safe(params, %{
          user_id: fn _id -> raise ArgumentError, "cannot transform" end
        })

      assert {:error, {:transformation_failed, message}} = result
      assert message =~ "cannot transform"
    end

    test "handles divide by zero and other runtime errors" do
      params = %{"count[eq]" => "0"}

      result =
        Bind.map_safe(params, %{
          count: fn val ->
            num = String.to_integer(val)
            # This will raise ArithmeticError
            div(100, num)
          end
        })

      assert {:error, {:transformation_failed, message}} = result
      assert message =~ "bad argument in arithmetic expression"
    end
  end

  describe "map_safe/2 with query string" do
    test "handles URL encoded query string with successful transformation" do
      query_string = "user_id[eq]=valid_123&name[eq]=John%20Doe"

      result =
        Bind.map_safe(query_string, %{
          user_id: fn id -> HashIds.decode!(id) end,
          name: &String.upcase/1
        })

      assert {:ok, mapped} = result
      assert mapped["user_id[eq]"] == 123
      assert mapped["name[eq]"] == "JOHN DOE"
    end

    test "returns error for invalid transformation in query string" do
      query_string = "user_id[eq]=invalid_hash&name[eq]=test"

      result =
        Bind.map_safe(query_string, %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:error, {:transformation_failed, _}} = result
    end
  end

  describe "map_safe/2 integration with Bind.query" do
    defmodule User do
      use Ecto.Schema

      schema "users" do
        field(:name, :string)
        field(:external_id, :integer)
      end
    end

    test "successful transformation pipes into Bind.query" do
      params = %{"external_id[eq]" => "valid_123", "name[eq]" => "alice"}

      result =
        params
        |> Bind.map_safe(%{
          external_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result

      query = Bind.query(mapped, User)
      query_string = inspect(query)

      assert query_string =~ "external_id == ^123"
      assert query_string =~ "name == ^\"alice\""
    end

    test "error stops pipeline before query building" do
      params = %{"external_id[eq]" => "invalid_hash"}

      result =
        params
        |> Bind.map_safe(%{
          external_id: fn id -> HashIds.decode!(id) end
        })

      assert {:error, {:transformation_failed, _}} = result
    end
  end

  describe "map_safe/2 empty and edge cases" do
    test "handles empty params map" do
      result =
        Bind.map_safe(%{}, %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, %{}} = result
    end

    test "handles empty query string" do
      result =
        Bind.map_safe("", %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, %{}} = result
    end

    test "handles params with no matching mappers" do
      params = %{"name[eq]" => "alice", "age[gte]" => "30"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode!(id) end
        })

      assert {:ok, mapped} = result
      assert mapped == params
    end
  end

  describe "map_safe/2 with Result tuples" do
    test "unwraps {:ok, value} tuples from transformations" do
      params = %{"user_id[eq]" => "valid_123", "name[eq]" => "alice"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode(id) end,
          name: &String.upcase/1
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "name[eq]" => "ALICE"
             }
    end

    test "returns error from {:error, reason} tuples" do
      params = %{"user_id[eq]" => "invalid_hash"}

      result =
        Bind.map_safe(params, %{
          user_id: fn id -> HashIds.decode(id) end
        })

      assert {:error, {:transformation_failed, "invalid hash"}} = result
    end

    test "handles mixed return types from mappers" do
      params = %{
        "user_id[eq]" => "valid_123",
        "team_id[eq]" => "valid_456",
        "name[eq]" => "alice"
      }

      result =
        Bind.map_safe(params, %{
          # returns {:ok, val}
          user_id: fn id -> HashIds.decode(id) end,
          # returns val directly
          team_id: fn id -> HashIds.decode!(id) end,
          # returns val directly
          name: &String.upcase/1
        })

      assert {:ok, mapped} = result

      assert mapped == %{
               "user_id[eq]" => 123,
               "team_id[eq]" => 456,
               "name[eq]" => "ALICE"
             }
    end

    test "stops on first error in Result tuple" do
      params = %{
        "user_id[eq]" => "valid_123",
        "team_id[eq]" => "invalid_hash",
        "org_id[eq]" => "valid_456"
      }

      result =
        Bind.map_safe(params, %{
          ~r/_id$/i => fn id -> HashIds.decode(id) end
        })

      assert {:error, {:transformation_failed, "invalid hash"}} = result
    end
  end
end
