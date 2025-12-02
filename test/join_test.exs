## File: bind/test/join_test.exs

defmodule Bind.JoinTest do
  use ExUnit.Case

  defmodule AssetVersion do
    use Ecto.Schema

    schema "asset_versions" do
      field(:content_title, :string)
      field(:content_type, :string)
      field(:status, :string)
      field(:flow_input, :map)
      belongs_to(:asset, Bind.JoinTest.Asset)
    end
  end

  defmodule Asset do
    use Ecto.Schema

    schema "assets" do
      field(:asset_type, :string)
      field(:user_id, :integer)
      belongs_to(:current_version, AssetVersion)
    end
  end

  test "joins on belongs_to association with contains constraint" do
    params = %{"current_version:content_title[contains]" => "cat"}

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "join:"
    assert query_string =~ "current_version"
    assert query_string =~ "ilike"
    assert query_string =~ "cat"
  end

  test "joins on belongs_to association with eq constraint" do
    params = %{"current_version:status[eq]" => "done"}

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "join:"
    assert query_string =~ "status"
    assert query_string =~ "done"
  end

  test "combines join constraint with regular constraint" do
    params = %{
      "asset_type[eq]" => "image",
      "current_version:content_title[contains]" => "cat"
    }

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "asset_type == ^\"image\""
    assert query_string =~ "join:"
    assert query_string =~ "cat"
  end

  test "rejects join field not in whitelist" do
    params = %{"current_version:content_title[contains]" => "cat"}

    result = Bind.query(params, Asset, joins: [])

    assert {:error, "Join not allowed: current_version"} = result
  end

  test "rejects join field when no joins specified" do
    params = %{"current_version:content_title[contains]" => "cat"}

    result = Bind.query(params, Asset)

    assert {:error, "Join not allowed: current_version"} = result
  end

  test "multiple constraints on same join use single join" do
    params = %{
      "current_version:content_title[contains]" => "cat",
      "current_version:status[eq]" => "done"
    }

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert length(Regex.scan(~r/join:/, query_string)) == 1
    assert query_string =~ "cat"
    assert query_string =~ "done"
  end

  test "works with query string" do
    query_string = "current_version:content_title[contains]=cat&asset_type[eq]=image"

    query = Bind.query(query_string, Asset, joins: [:current_version])
    result = inspect(query)

    assert result =~ "join:"
    assert result =~ "cat"
    assert result =~ "asset_type"
  end

  test "joins on belongs_to association with jsonb contains constraint" do
    params = %{"current_version:flow_input.prompt[contains]" => "fofofo"}

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "join:"
    assert query_string =~ "current_version"
    assert query_string =~ "fragment"
    assert query_string =~ "flow_input"
    assert query_string =~ "prompt"
    assert query_string =~ "fofofo"
  end

  test "map_safe handles join jsonb fields" do
    params = %{
      "current_version:flow_input.prompt[contains]" => "cat",
      "start" => "123"
    }

    result = Bind.map_safe(params, %{
      start: fn id -> String.to_integer(id) end
    })

    assert {:ok, mapped} = result
    assert mapped["current_version:flow_input.prompt[contains]"] == "cat"
    assert mapped["start"] == 123
  end

  test "map_safe transforms join jsonb field values" do
    params = %{
      "current_version:flow_input.prompt[contains]" => "CAT"
    }

    result = Bind.map_safe(params, %{
      flow_input: &String.downcase/1
    })

    assert {:ok, mapped} = result
    assert mapped["current_version:flow_input.prompt[contains]"] == "cat"
  end

  test "map handles join jsonb fields" do
    params = %{
      "current_version:flow_input.prompt[contains]" => "DOG"
    }

    mapped = Bind.map(params, %{
      flow_input: &String.downcase/1
    })

    assert mapped["current_version:flow_input.prompt[contains]"] == "dog"
  end

  test "map_safe skips empty join jsonb values with mapper" do
    params = %{
      "current_version:flow_input.prompt[contains]" => "",
      "asset_type[eq]" => "image"
    }

    result = Bind.map_safe(params, %{
      flow_input: fn _ -> raise "should not be called" end
    })

    assert {:ok, mapped} = result
    refute Map.has_key?(mapped, "current_version:flow_input.prompt[contains]")
    assert mapped["asset_type[eq]"] == "image"
  end
end
