defmodule Bind.JoinTest do
  use ExUnit.Case

  defmodule AssetVersion do
    use Ecto.Schema

    schema "asset_versions" do
      field(:content_title, :string)
      field(:content_type, :string)
      field(:status, :string)

      # JSONB field (map in Ecto)
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

    # Should only have one join
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

    # Should join on current_version
    assert query_string =~ "join:"
    assert query_string =~ "current_version"

    # Should build a JSONB fragment on flow_input->>'prompt'
    assert query_string =~ "fragment"
    assert query_string =~ "flow_input"
    assert query_string =~ "prompt"
    assert query_string =~ "fofofo"
  end
end
