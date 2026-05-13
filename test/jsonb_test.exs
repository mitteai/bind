defmodule Bind.JsonbTest do
  use ExUnit.Case

  defmodule VideoVersion do
    use Ecto.Schema

    schema "video_versions" do
      field(:options, :map)
      field(:tags, {:array, :integer})
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

  test "jsonb direct array empty=true" do
    params = %{"tags[empty]" => "true"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "jsonb_array_length"
    assert query_string =~ "tags"
    assert query_string =~ "= 0"
  end

  test "jsonb direct array empty=false" do
    params = %{"tags[empty]" => "false"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "jsonb_array_length"
    assert query_string =~ "tags"
    assert query_string =~ "> 0"
  end

  test "jsonb nested key array empty=true" do
    params = %{"options.foobar[empty]" => "true"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "jsonb_array_length"
    assert query_string =~ "options"
    assert query_string =~ "foobar"
    assert query_string =~ "= 0"
  end

  test "jsonb nested key array empty=false" do
    params = %{"options.foobar[empty]" => "false"}

    query = Bind.query(params, VideoVersion)
    query_string = inspect(query)

    assert query_string =~ "fragment"
    assert query_string =~ "jsonb_array_length"
    assert query_string =~ "options"
    assert query_string =~ "foobar"
    assert query_string =~ "> 0"
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
