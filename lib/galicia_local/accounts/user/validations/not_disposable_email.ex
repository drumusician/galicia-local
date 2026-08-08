defmodule GaliciaLocal.Accounts.User.Validations.NotDisposableEmail do
  @moduledoc """
  Rejects registrations from throwaway email providers.

  Applied to the registration action only, never to sign-in. Blocking an
  existing account from signing in because its domain was later added to the
  list would lock out a real person for something they did nothing wrong.
  """

  use Ash.Resource.Validation

  alias GaliciaLocal.Accounts.DisposableEmailDomains

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    argument = Keyword.get(opts, :argument, :email)

    case Ash.Changeset.fetch_argument(changeset, argument) do
      {:ok, email} ->
        if DisposableEmailDomains.disposable?(email) do
          {:error,
           Ash.Error.Changes.InvalidArgument.exception(
             field: argument,
             message: "please use a permanent email address"
           )}
        else
          :ok
        end

      :error ->
        :ok
    end
  end

  # Runs against a plain argument rather than stored data, so there is nothing
  # to push into the database as an atomic expression.
  @impl true
  def atomic(_changeset, _opts, _context), do: :not_atomic
end
