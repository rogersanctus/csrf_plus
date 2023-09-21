defmodule CsrfPlus.OkStoreMock do
  @moduledoc false
  @behaviour CsrfPlus.Store.Behaviour

  @the_token "a-unique-token"

  def the_token, do: @the_token

  def get_token(_access_id) do
    @the_token
  end

  def put_token(_user_access) do
    {:ok, @the_token}
  end

  def delete_token(_access_id) do
    {:ok, @the_token}
  end
end
