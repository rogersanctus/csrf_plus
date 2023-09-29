defmodule CsrfPlus.SupervisorTest do
  use ExUnit.Case

  setup do
    on_exit(fn ->
      Application.delete_env(:csrf_plus, CsrfPlus)
    end)
  end

  test "if the supervisor starts the Store Manager" do
    CsrfPlus.Supervisor.start_link([])

    pid = Process.whereis(CsrfPlus.Store.Manager)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "if the supervisor starts the Store MemoryDB" do
    Application.put_env(:csrf_plus, CsrfPlus, store: CsrfPlus.Store.MemoryDb)
    CsrfPlus.Supervisor.start_link([])

    pid = Process.whereis(CsrfPlus.Store.MemoryDb)

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "if only Store Manager is started when there is no store set" do
    CsrfPlus.Supervisor.start_link([])

    pid = Process.whereis(CsrfPlus.Store.Manager)

    children = Supervisor.which_children(CsrfPlus.Supervisor)

    assert is_pid(pid) && Process.alive?(pid)
    assert Enum.count(children) == 1
  end
end
