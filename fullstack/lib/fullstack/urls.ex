defmodule Fullstack.Urls do
  @moduledoc """
  The Urls context.
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Urls.Url

  @doc """
  Returns the list of ulrs.

  ## Examples

      iex> list_ulrs()
      [%Url{}, ...]

  """
  def list_ulrs do
    Repo.all(Url)
  end

  @doc """
  Gets a single url.

  Raises `Ecto.NoResultsError` if the Url does not exist

  ## Examples

      iex> get_url!(123)
      %Url{}

      iex> get_url!(456)
      ** (Ecto.NoResultsError)

  """
  def get_url!(id), do: Repo.get!(Url, id)

  def find_url(origin) do
    case Repo.get_by(Url, origin: origin) do
      nil ->
        {:error, :not_found}

      %Url{destiny: destiny, id: url_id} ->
        {:ok, _increment_count_id} =
          Task.start_link(fn -> increment_visits(url_id) end)

        {:ok, destiny}
    end
  end

  @doc """
  Creates a url.

  ## Examples

      iex> create_url(%{field: value})
      {:ok, %Url{}}

      iex> create_url(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_url(attrs \\ %{}) do
    %Url{}
    |> Url.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  updates a url.

  ## examples

      iex> update_url(url, %{field: new_value})
      {:ok, %url{}}

      iex> update_url(url, %{field: bad_value})
      {:error, %ecto.changeset{}}

  """
  def update_url(%Url{} = url, attrs) do
    url
    |> Url.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  increments the url count.

  ## examples

      iex> increment_visits(url_id)
      {:ok, %url{}}

      iex> increment_visits(unexistent_url_id)
      {:error, :not_found}

  """
  def increment_visits(url_id) do
    %Url{id: url_id, visit_count: 1}
    |> Repo.insert(
      returning: [:visit_count],
      conflict_target: :id,
      on_conflict: [inc: [visit_count: 1]]
    )
  end

  @doc """
  Deletes a url.

  ## Examples

      iex> delete_url(url)
      {:ok, %Url{}}

      iex> delete_url(url)
      {:error, %Ecto.Changeset{}}

  """
  def delete_url(%Url{} = url) do
    Repo.delete(url)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking url changes.

  ## Examples

      iex> change_url(url)
      %Ecto.Changeset{data: %Url{}}

  """
  def change_url(%Url{} = url, attrs \\ %{}) do
    Url.changeset(url, attrs)
  end
end
