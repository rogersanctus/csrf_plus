defmodule CsrfPlus.SupervisorTest do
  use ExUnit.Case

  setup do
    on_exit(fn ->
      Application.delete_env(:csrf_plus, CsrfPlus)
    end)
  end

  test "if the supervisor starts the Store Manager" do
    CsrfPlus.Supervisor.start_link(otp_app: :test_app)

    pid = Process.whereis(CsrfPlus.Store.Manager)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "if the supervisor starts the Store MemoryDB" do
    Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.Store.MemoryDb)
    CsrfPlus.Supervisor.start_link(otp_app: :test_app)

    pid = Process.whereis(CsrfPlus.Store.MemoryDb)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end
end
