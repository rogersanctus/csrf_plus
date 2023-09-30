defmodule CsrfPlus.Store.Behaviour do
  @moduledoc false

  alias CsrfPlus.UserAccess

  @callback all_accesses() :: [UserAccess.t()]

  @callback put_access(user_access :: UserAccess.t()) ::
              {:ok, UserAccess.t()} | {:error, term()}

  @callback get_access(access_id :: String.t()) :: UserAccess.t() | nil

  @callback delete_access(access_id :: String.t()) :: {:ok, UserAccess.t()} | {:error, term()}

  @callback delete_dead_accesses(max_age :: non_neg_integer()) :: :ok | {:error, term()}

  @optional_callbacks [all_accesses: 0, delete_dead_accesses: 1]
end
