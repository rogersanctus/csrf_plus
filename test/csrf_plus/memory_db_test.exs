defmodule CsrfPlus.MemoryDbTest do
  use ExUnit.Case

  alias CsrfPlus.Store.MemoryDb

  describe "MemoryDb" do
    test "if, at start, thereis no tokens in the store" do
      MemoryDb.start_link([])

      all_tokens = MemoryDb.all_accesses()

      assert Enum.empty?(all_tokens)
    end
  end
end
