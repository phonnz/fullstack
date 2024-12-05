defmodule Fullstack.UrlsTest do
  use Fullstack.DataCase

  alias Fullstack.Urls

  describe "ulrs" do
    alias Fullstack.Urls.Url

    import Fullstack.UrlsFixtures

    @invalid_attrs %{origin: nil, destiny: nil, visit_count: nil}

    test "list_ulrs/0 returns all ulrs" do
      url = url_fixture()
      assert Urls.list_ulrs() == [url]
    end

    test "get_url!/1 returns the url with given id" do
      url = url_fixture()
      assert Urls.get_url!(url.id) == url
    end

    test "create_url/1 with valid data creates a url" do
      valid_attrs = %{origin: "some origin", destiny: "some destiny", visit_count: 42}

      assert {:ok, %Url{} = url} = Urls.create_url(valid_attrs)
      assert url.origin == "some origin"
      assert url.destiny == "some destiny"
      assert url.visit_count == 42
    end

    test "create_url/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Urls.create_url(@invalid_attrs)
    end

    test "update_url/2 with valid data updates the url" do
      url = url_fixture()
      update_attrs = %{origin: "some updated origin", destiny: "some updated destiny", visit_count: 43}

      assert {:ok, %Url{} = url} = Urls.update_url(url, update_attrs)
      assert url.origin == "some updated origin"
      assert url.destiny == "some updated destiny"
      assert url.visit_count == 43
    end

    test "update_url/2 with invalid data returns error changeset" do
      url = url_fixture()
      assert {:error, %Ecto.Changeset{}} = Urls.update_url(url, @invalid_attrs)
      assert url == Urls.get_url!(url.id)
    end

    test "delete_url/1 deletes the url" do
      url = url_fixture()
      assert {:ok, %Url{}} = Urls.delete_url(url)
      assert_raise Ecto.NoResultsError, fn -> Urls.get_url!(url.id) end
    end

    test "change_url/1 returns a url changeset" do
      url = url_fixture()
      assert %Ecto.Changeset{} = Urls.change_url(url)
    end
  end
end
