defmodule CsrfPlus.Store.Manager do
  use GenServer

  # Check age from hour to hour
  @check_age_time 60 * 60 * 1000

  def start_link(
        [token_max_age: token_max_age] =
          init_arg
      )
      when is_integer(token_max_age) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(init_arg) do
    state = Enum.into(init_arg, %{})
    {:ok, state, {:continue, :check_age}}
  end

  def handle_continue(:check_age, state) do
    Process.send_after(self(), :check_age, @check_age_time)

    {:noreply, state}
  end

  def handle_info(
        :check_age,
        %{
          token_max_age: token_max_age
        } = state
      ) do
    config = Application.get_env(:csrf_plus, CsrfPlus, [])
    store = Keyword.get(config, :store, nil)

    if !is_nil(store) do
      check_age(store, token_max_age)
      Process.send_after(self(), :check_age, @check_age_time)
    end

    {:noreply, state}
  end

  defp check_age(nil, _) do
    :nop
  end

  defp check_age(store, token_max_age) do
    store.delete_dead_tokens(token_max_age)
  end
end
