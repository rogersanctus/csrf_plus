defmodule CsrfPlus.Store.MemoryDb do
  @moduledoc false
  alias CsrfPlus.UserAccess
  use GenServer
  @behaviour CsrfPlus.Store.Behaviour

  def start_link(_opts) do
    state = %{
      db: []
    }

    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def all_accesses() do
    GenServer.call(__MODULE__, :all_accesses)
  end

  def put_access(
        %UserAccess{token: token, access_id: access_id, created_at: nil} =
          user_access
      )
      when is_binary(token) and is_binary(access_id) do
    created_at = System.os_time(:millisecond)

    %{user_access | created_at: created_at}
    |> put_access()
  end

  def put_access(
        %UserAccess{
          token: token,
          access_id: access_id,
          created_at: created_at
        } = user_access
      )
      when is_binary(token) and is_binary(access_id) and is_integer(created_at) do
    GenServer.call(
      __MODULE__,
      {:put_access, user_access}
    )
  end

  def put_access(_) do
    {:error, :invalid_param}
  end

  def get_access(access_id = access_id)
      when is_binary(access_id) do
    GenServer.call(__MODULE__, {:get_access, access_id})
  end

  def get_access(_) do
    {:error, :invalid_param}
  end

  def delete_access(access_id = access_id)
      when is_binary(access_id) do
    GenServer.call(__MODULE__, {:delete_access, access_id})
  end

  def delete_access(_) do
    {:error, :invalid_param}
  end

  def delete_dead_accesses(max_age) do
    GenServer.call(__MODULE__, {:delete_dead_accesses, max_age})
  end

  def handle_call(:all_accesses, _from, state) do
    db = Enum.map(state.db, fn entry -> Map.merge(%UserAccess{}, entry) end)

    {:reply, db, state}
  end

  def handle_call(
        {:put_access, %{token: _token, access_id: _access_id, created_at: _created_at} = access},
        _from,
        state
      ) do
    state =
      %{
        state
        | db: [access | state.db]
      }

    user_access = Map.merge(%UserAccess{}, access)

    {:reply, {:ok, user_access}, state}
  end

  def handle_call({:get_access, access_id}, _from, state) do
    access =
      Enum.find(state.db, nil, fn entry -> entry.access_id == access_id end)

    user_access =
      if access != nil do
        Map.merge(%UserAccess{}, access)
      end

    {:reply, user_access, state}
  end

  def handle_call({:delete_access, access_id}, _from, state) do
    deleted = Enum.find(state.db, nil, fn entry -> entry.access_id == access_id end)

    {state, result} =
      if deleted != nil do
        {
          %{
            state
            | db:
                Enum.reject(state.db, fn entry ->
                  entry == deleted
                end)
          },
          {:ok, deleted}
        }
      else
        {state, {:error, :not_found}}
      end

    {:reply, result, state}
  end

  def handle_call({:delete_dead_accesses, max_age}, _from, %{db: db} = state)
      when is_integer(max_age) do
    checking_time = System.os_time(:millisecond)

    state = %{
      state
      | db:
          Enum.map(db, fn entry ->
            if checking_time > entry.created_at + max_age do
              Map.put(entry, :expired?, true)
            else
              entry
            end
          end)
    }

    {:reply, :ok, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
