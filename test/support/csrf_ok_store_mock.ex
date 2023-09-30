defmodule CsrfPlus.OkStoreMock do
  @moduledoc false
  alias CsrfPlus.UserAccess
  @behaviour CsrfPlus.Store.Behaviour

  @access_id "the-access-id"
  @the_token "a-unique-token"

  def the_token, do: @the_token
  def access_id, do: @access_id

  def get_access("the-access-id" = access_id) do
    %UserAccess{token: @the_token, access_id: access_id}
  end

  def put_access(%UserAccess{access_id: "the-access-id"} = access) do
    {:ok, Map.merge(access, %{token: @the_token})}
  end

  def delete_access("the-access-id" = access_id) do
    {:ok, %UserAccess{token: @the_token, access_id: access_id}}
  end
end
