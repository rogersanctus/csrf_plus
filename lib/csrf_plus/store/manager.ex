defmodule CsrfPlus.Store.Manager do
  @moduledoc """
  Manager to check the configured store tokens age.
  If a token age is greater than the max age configured, the token is flagged as expired.

  The manager is started by the `start_link/1` function.
  """

  require Logger
  use GenServer

  # Check age from hour to hour
  @check_age_time 60 * 60 * 1000

  @doc """
  Starts the Manager.

    > #### Note {: .info}
    > It's preferable to start this by the `CsrfPlus.Supervisor`.

  `init_arg` - Is a Keyword with the options to be used.

  ## Options

    * `:token_max_age` - Maximum age of the tokens before they expires. It's a non-negative integer with the age in milliseconds. Defaults to one day.

    * `:check_age_time` - How often to check the age of the tokens. Non-negative integer with the time in milliseconds. Defaults to one hour.
  """
  def start_link(init_arg) when is_list(init_arg) do
    if Keyword.get(init_arg, :token_max_age, nil) == nil do
      raise "CsrfPlus.Store.Manager requires token_max_age to be set"
    end

    check_time = Keyword.get(init_arg, :check_age_time, @check_age_time)

    init_arg = Keyword.put(init_arg, :check_age_time, check_time)
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc false
  def init(init_arg) do
    state = Enum.into(init_arg, %{})
    {:ok, state, {:continue, :check_age}}
  end

  @doc false
  def handle_continue(:check_age, %{check_age_time: check_time} = state) do
    Process.send_after(self(), :check_age, check_time)

    {:noreply, state}
  end

  @doc false
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
