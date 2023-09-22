defmodule CsrfPlus.OkStoreMock do
  @moduledoc false
  alias CsrfPlus.UserAccess
  @behaviour CsrfPlus.Store.Behaviour

  @access_id "the-access-id"
  @the_token "a-unique-token"

  def the_token, do: @the_token
  def access_id, do: @access_id

  def get_token("the-access-id") do
    @the_token
  end

  def put_token(%UserAccess{access_id: "the-access-id"}) do
    {:ok, @the_token}
  end

  def delete_token("the-access-id") do
    {:ok, @the_token}
  end
end
