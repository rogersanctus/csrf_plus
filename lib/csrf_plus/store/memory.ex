defmodule CsrfPlus.Store.Memory do
  @moduledoc false
  alias CsrfPlus.Store.MemoryDb

  @behaviour CsrfPlus.Store.Behaviour

  def put_token(user_access) do
    MemoryDb.put_token(user_access)
  end

  def get_token(access_id) do
    MemoryDb.get_token(access_id)
  end

  def delete_token(access_id) do
    MemoryDb.delete_token(access_id)
  end
end
