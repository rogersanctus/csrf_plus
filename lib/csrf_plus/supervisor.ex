defmodule CsrfPlus.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    otp_app = Keyword.fetch!(init_arg, :otp_app)
    token_max_age = Keyword.get(init_arg, :token_max_age, CsrfPlus.default_token_max_age())

    init_arg =
      Keyword.merge(init_arg, [
        {:otp_app, otp_app},
        {:token_max_age, token_max_age}
      ])

    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(
        [otp_app: otp_app, token_max_age: token_max_age] =
          _init_arg
      ) do
    children = [
      {CsrfPlus.Store.Manager, [otp_app: otp_app, token_max_age: token_max_age]}
    ]

    config = Application.get_env(otp_app, CsrfPlus, [])
    store = Keyword.get(config, :store, nil)

    children =
      if store == CsrfPlus.Store.Manager do
        children ++ {CsrfPlus.Store.MemoryDB, []}
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
