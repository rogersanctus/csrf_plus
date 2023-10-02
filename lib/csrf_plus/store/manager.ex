defmodule CsrfPlus.Store.Manager do
  require Logger
  use GenServer

  # Check age from hour to hour
  @check_age_time 60 * 60 * 1000

  def start_link(init_arg) when is_list(init_arg) do
    if Keyword.get(init_arg, :token_max_age, nil) == nil do
      raise "CsrfPlus.Store.Manager requires token_max_age to be set"
    end

    check_time = Keyword.get(init_arg, :check_age_time, @check_age_time)

    init_arg = Keyword.put(init_arg, :check_age_time, check_time)
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(init_arg) do
    state = Enum.into(init_arg, %{})
    {:ok, state, {:continue, :check_age}}
  end

  def handle_continue(:check_age, %{check_age_time: check_time} = state) do
    Process.send_after(self(), :check_age, check_time)

    {:noreply, state}
  end

  def handle_info(
        :check_age,
        %{
          token_max_age: token_max_age,
          check_age_time: check_time
        } = state
      ) do
    config = Application.get_env(:csrf_plus, CsrfPlus, [])
    store = Keyword.get(config, :store, nil)

    if !is_nil(store) do
      check_age(store, token_max_age)
      Process.send_after(self(), :check_age, check_time)
    end

    {:noreply, state}
  end

  defp check_age(nil, _) do
    :nop
  end

  defp check_age(store, token_max_age) do
    if Kernel.function_exported?(store, :delete_dead_accesses, 1) do
      store.delete_dead_accesses(token_max_age)
    else
      Logger.warning("CsrfPlus.Store.Manager :delete_dead_accesses not implemented")
    end
  end
end
