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

  def put_token(
        %UserAccess{token: token, access_id: access_id, created_at: nil} =
          user_access
      )
      when is_binary(token) and is_binary(access_id) do
    created_at = System.os_time(:millisecond)

    %{user_access | created_at: created_at}
    |> put_token()
  end

  def put_token(
        %UserAccess{
          token: token,
          access_id: access_id,
          created_at: created_at
        } = user_access
      )
      when is_binary(token) and is_binary(access_id) and is_integer(created_at) do
    case GenServer.call(
           __MODULE__,
           {:put_token, user_access}
         ) do
      :ok -> {:ok, token}
      error -> {:error, error}
    end
  end

  def put_token(_) do
    {:error, "invalid_param"}
  end

  def get_token(access_id = access_id)
      when is_binary(access_id) do
    GenServer.call(__MODULE__, {:get_token, access_id})
  end

  def get_token(_) do
    {:error, "invalid_param"}
  end

  def delete_token(access_id = access_id)
      when is_binary(access_id) do
    GenServer.call(__MODULE__, {:delete_token, access_id})
  end

  def delete_token(_) do
    {:error, "invalid_param"}
  end

  def delete_dead_tokens(max_age) do
    GenServer.call(__MODULE__, {:delete_dead_tokens, max_age})
  end

  def handle_call(
        {:put_token, %{token: token, access_id: access_id, created_at: created_at}},
        _from,
        state
      ) do
    state =
      %{
        state
        | db: [%{token: token, access_id: access_id, created_at: created_at} | state.db]
      }

    {:reply, :ok, state}
  end

  def handle_call({:get_token, access_id}, _from, state) do
    user_access =
      Enum.find(state.db, nil, fn entry -> entry.access_id == access_id end)

    {:reply, user_access.token, state}
  end

  def handle_call({:delete_token, access_id}, _from, state) do
    state =
      %{
        state
        | db:
            Enum.reject(state.db, fn entry ->
              entry.access_id == access_id
            end)
      }

    {:reply, :ok, state}
  end

  def handle_call({:delete_dead_tokens, max_age}, _from, %{db: db} = state)
      when is_integer(max_age) do
    state = %{
      state
      | db:
          Enum.reject(db, fn entry ->
            System.os_time(:millisecond) > entry.created_at + max_age
          end)
    }

    {:reply, :ok, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
