defmodule Bind.JsonbTest do
  use ExUnit.Case

  defmodule VideoVersion do
    use Ecto.Schema

    schema "video_versions" do
      field(:options, :map)
      field(:user_id, :string)
    end
  end

  test "jsonb field search with contains" do
    params = %{"options.prompt[contains]" => "motorbike"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    # Should generate fragment with JSONB operator
    assert query_string =~ "fragment"
    assert query_string =~ "options"
    assert query_string =~ "prompt"
    assert query_string =~ "ILIKE"
    assert query_string =~ "motorbike"
  end

  test "jsonb field search with eq" do
    params = %{"options.duration[eq]" => "5"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "duration"
    assert query_string =~ " = "
  end

  test "combines regular and jsonb constraints" do
    params = %{
      "user_id[eq]" => "yghBv272",
      "options.prompt[contains]" => "cat"
    }

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    # Regular constraint
    assert query_string =~ "user_id == ^\"yghBv272\""

    # JSONB constraint
    assert query_string =~ "fragment"
    assert query_string =~ "prompt"
    assert query_string =~ "cat"
  end
end
