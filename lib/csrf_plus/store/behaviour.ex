defmodule CsrfPlus.Store.Behaviour do
  @moduledoc """
  Defines the behaviour for a store.
  """

  alias CsrfPlus.UserAccess

  @doc "Returns all the accesses in the store."
  @callback all_accesses() :: [UserAccess.t()]

  @doc """
  Puts an access in the store.

  Returns
    * `{:ok, UserAccess.t()}` if the access was successfully store
    * `{:error, reason}` if it was not possible for any `reason`.
  """
  @callback put_access(user_access :: UserAccess.t()) ::
              {:ok, UserAccess.t()} | {:error, term()}

  @doc """
  Given an `access_id`, returns the access associated with it.
  """
  @callback get_access(access_id :: String.t()) :: UserAccess.t() | nil

  @doc """
  Deletes an access from the store by its `access_id`.

  Returns
    * `{:ok, user_access}` if the access was successfully deleted. `user_access` is the access that was deleted.
    * `{:error, reason}` if it was not possible for any `reason`.
  """
  @callback delete_access(access_id :: String.t()) :: {:ok, UserAccess.t()} | {:error, term()}

  @doc """
  May delete all the tokens in the store that had expired. Other option, is to flag them as expired.

  Returns
  `:ok` in case of success or `{:error, reason}` otherwise.
  """
  @callback delete_dead_accesses(max_age :: non_neg_integer()) :: :ok | {:error, term()}

  @doc """
  A function to return the user access struct for a given connection and raw access map.

  ## Params
  * `conn` - The connection struct.
  * `raw_access` - A map with the required access information.

  ### Raw Access
  * `:access_id` - The id that identifies the access.
  * `:token` - The access token.

  """
  @callback conn_to_access(
              conn :: Plug.Conn.t(),
              raw_access :: %{access_id: String.t(), token: String.t()}
            ) :: UserAccess.t()

  @optional_callbacks [all_accesses: 0, delete_dead_accesses: 1, conn_to_access: 2]
end
