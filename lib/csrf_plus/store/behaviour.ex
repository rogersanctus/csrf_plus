defmodule CsrfPlus.Store.Behaviour do
  @moduledoc false

  alias CsrfPlus.UserAccess

  @callback all_accesses() :: [UserAccess.t()]

  @callback put_token(user_access :: UserAccess.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback get_token(access_id :: String.t()) :: String.t() | nil

  @callback get_user_access(access_id :: String.t()) :: UserAccess.t() | nil

  @callback delete_token(access_id :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @callback delete_dead_tokens(max_age :: non_neg_integer()) :: :ok | {:error, term()}

  @optional_callbacks [all_accesses: 0, delete_dead_tokens: 1, get_user_access: 1]
end
