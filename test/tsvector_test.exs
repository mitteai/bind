defmodule Bind.TsvectorTest do
  use ExUnit.Case

  defmodule AssetVersion do
    use Ecto.Schema

    schema "asset_versions" do
      field(:search_content, :string)
      field(:title, :string)
    end
  end

  defmodule Asset do
    use Ecto.Schema

    schema "assets" do
      field(:name, :string)
      belongs_to(:current_version, AssetVersion)
    end
  end

  test "tsvector search on direct field" do
    params = %{"search_content[search]" => "bear"}

    query = Bind.query(params, AssetVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "search_content"
    assert query_string =~ "to_tsquery"
    assert query_string =~ "bear"
  end

  test "tsvector search with multiple words" do
    params = %{"search_content[search]" => "bear cat"}

    query = Bind.query(params, AssetVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "to_tsquery"
  end

  test "combines tsvector search with regular constraints" do
    params = %{
      "search_content[search]" => "bear",
      "title[eq]" => "test"
    }

    query = Bind.query(params, AssetVersion)
    query_string = inspect(query)

    assert query_string =~ "title == ^\"test\""
    assert query_string =~ "to_tsquery"
    assert query_string =~ "bear"
  end

  test "tsvector search on joined field" do
    params = %{"current_version:search_content[search]" => "bear"}

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "join:"
    assert query_string =~ "current_version"
    assert query_string =~ "to_tsquery"
    assert query_string =~ "bear"
  end

  test "tsvector search on joined field with other constraints" do
    params = %{
      "current_version:search_content[search]" => "bear",
      "name[eq]" => "test"
    }

    query = Bind.query(params, Asset, joins: [:current_version])
    query_string = inspect(query)

    assert query_string =~ "name == ^\"test\""
    assert query_string =~ "join:"
    assert query_string =~ "to_tsquery"
  end

  test "tsvector search from query string" do
    query_string = "search_content[search]=bear&title[contains]=cat"

    query = Bind.query(query_string, AssetVersion)
    result = inspect(query)

    assert result =~ "to_tsquery"
    assert result =~ "bear"
    assert result =~ "ilike"
    assert result =~ "cat"
  end

  test "tsvector join search from query string" do
    query_string = "current_version:search_content[search]=bear&name[eq]=test"

    query = Bind.query(query_string, Asset, joins: [:current_version])
    result = inspect(query)

    assert result =~ "join:"
    assert result =~ "to_tsquery"
    assert result =~ "bear"
  end
end
