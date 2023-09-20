defmodule CsrfPlus.Store.Behaviour do
  @moduledoc false

  alias CsrfPlus.UserAccess

  @callback put_token(user_access :: UserAccess.t()) ::
              {:ok, String.t()} | {:error, term()}

  @callback get_token(access_id :: integer()) :: String.t() | nil

  @callback delete_token(access_id :: integer()) :: {:ok, String.t()} | {:error, term()}

  @callback delete_dead_tokens(max_age :: non_neg_integer()) :: :ok | {:error, term()}

  @optional_callbacks [delete_dead_tokens: 1]
end
