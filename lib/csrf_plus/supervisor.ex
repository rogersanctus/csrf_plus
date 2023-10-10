defmodule CsrfPlus.Supervisor do
  @moduledoc """
  Supervisor to keep the `CsrfPlus.Store.Manager` running.

  If `CsrfPlus.Store.MemoryDb` module is set as the store, then it will also be
  managed by this supervisor.
  """

  use Supervisor

  @doc """
  Starts the supervisor.
  `init_arg` - The options to be used by `CsrfPlus.Store.Manager`.
  """
  def start_link(init_arg) do
    token_max_age = Keyword.get(init_arg, :token_max_age, CsrfPlus.default_token_max_age())

    init_arg =
      Keyword.merge(init_arg, [
        {:token_max_age, token_max_age}
      ])

    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc false
  def init(init_arg) do
    children = [
      {CsrfPlus.Store.Manager, init_arg}
    ]

    config = Application.get_env(:csrf_plus, CsrfPlus, [])
    store = Keyword.get(config, :store, nil)

    children =
      if store == CsrfPlus.Store.MemoryDb do
        children ++ [{CsrfPlus.Store.MemoryDb, []}]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
