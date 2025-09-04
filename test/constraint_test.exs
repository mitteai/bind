defmodule Bind.ConstraintTest do
  use ExUnit.Case

  alias Bind.QueryBuilder

    test "eq constraint" do
      query = QueryBuilder.constraint(:name, "eq", "Alice")
      assert inspect(query) =~ "r.name == ^\"Alice\""
    end

    test "neq constraint" do
      query = QueryBuilder.constraint(:name, "neq", "Bob")
      assert inspect(query) =~ "r.name != ^\"Bob\""
    end

    test "gt constraint" do
      query = QueryBuilder.constraint(:age, "gt", 30)
      assert inspect(query) =~ "r.age > ^30"
    end

    test "gte constraint" do
      query = QueryBuilder.constraint(:age, "gte", 30)
      assert inspect(query) =~ "r.age >= ^30"
    end

    test "lt constraint" do
      query = QueryBuilder.constraint(:age, "lt", 30)
      assert inspect(query) =~ "r.age < ^30"
    end

    test "lte constraint" do
      query = QueryBuilder.constraint(:age, "lte", 30)
      assert inspect(query) =~ "r.age <= ^30"
    end

    test "true constraint" do
      query = QueryBuilder.constraint(:active, "true", true)
      assert inspect(query) =~ "r.active == true"
    end

    test "false constraint" do
      query = QueryBuilder.constraint(:active, "false", false)
      assert inspect(query) =~ "r.active == false"
    end

    test "starts_with constraint" do
      query = QueryBuilder.constraint(:name, "starts_with", "A")
      assert inspect(query) =~ "ilike(r.name, ^\"A%\")"
    end

    test "ends_with constraint" do
      query = QueryBuilder.constraint(:name, "ends_with", "e")
      assert inspect(query) =~ "ilike(r.name, ^\"%e\")"
    end

    test "in constraint" do
      query = QueryBuilder.constraint(:status, "in", "active,pending")
      assert inspect(query) =~ "r.status in ^[\"active\", \"pending\"]"
    end

    test "contains constraint" do
      query = QueryBuilder.constraint(:description, "contains", "important")
      assert inspect(query) =~ "ilike(r.description, ^\"%important%\")"
    end

    test "nil constraint with true" do
      query = QueryBuilder.constraint(:deleted_at, "nil", "true")
      assert inspect(query) =~ "is_nil(r.deleted_at)"
    end

    test "nil constraint with false" do
      query = QueryBuilder.constraint(:deleted_at, "nil", "false")
      assert inspect(query) =~ "not is_nil(r.deleted_at)"
    end

    test "invalid constraint" do
      assert QueryBuilder.constraint(:name, "invalid", "value") == {:error, "Invalid constraint: name[invalid]"}
    end

end
