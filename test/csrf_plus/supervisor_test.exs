defmodule CsrfPlus.SupervisorTest do
  use ExUnit.Case

  test "if the supervisor starts the Store Manager" do
    CsrfPlus.Supervisor.start_link(otp_app: :test_app)

    pid = Process.whereis(CsrfPlus.Store.Manager)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end
end
