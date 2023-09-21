defmodule CsrfPlus.CsrfPlusTest do
  use ExUnit.Case

  import Plug.Test
  alias CsrfPlus

  def build_conn(method, path) do
    conn = conn(method, path)

    %{
      conn
      | secret_key_base: "aReallyLongSecretKeyBase!YeahItsWide."
    }
  end

  describe "CSRF Plug configuration" do
    test "if otp_app is set and returned as in the returning config map" do
      config = CsrfPlus.init(otp_app: :test_app)

      assert match?(%{otp_app: :test_app}, config)
    end

    test "if the correct store is called when the otp_app is set" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      Application.put_env(:test_app, CsrfPlus, store: CsrfPlus.StoreMock)
      config = CsrfPlus.init(otp_app: :test_app)

      conn =
        build_conn(:post, "/")
        |> Plug.Conn.put_req_header("x-csrf-token", CsrfPlus.OkStoreMock.the_token())

      new_conn = CsrfPlus.call(conn, config)
      refute new_conn.halted
    end

    test "if when an allowed method is set the Conn is not halted" do
      Application.put_env(:test_app, CsrfPlis, store: CsrfPlus.StoreMock)
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      config = CsrfPlus.init(otp_app: :test_app, allowed_methods: ["PATCH"])

      conn = build_conn(:patch, "/")
      new_conn = CsrfPlus.call(conn, config)

      refute new_conn.halted
    end
  end

  describe "CSRF Plug on requrests" do
    test "if it can generate a token" do
      conn = build_conn(:get, "/")

      {token, signed} = CsrfPlus.generate_token(conn)

      refute is_nil(token)
      refute is_nil(signed)
    end

    test "if it fails to generate a token when the conn has no secret key" do
      conn = conn(:get, "/")

      assert_raise RuntimeError, fn -> CsrfPlus.generate_token(conn) end
    end

    test "if a generated token is signed and verifyable" do
      conn = build_conn(:get, "/")
      {token, signed} = CsrfPlus.generate_token(conn)
      result = CsrfPlus.verify_token(conn, signed)

      assert match?({:ok, ^token}, result)
    end

    test "if verifying a token fails with invalid token when token is invalid" do
      conn = build_conn(:get, "/")

      wrong_token = "wrong token"
      result = CsrfPlus.verify_token(conn, wrong_token)
      assert match?({:error, "invalid token"}, result)
    end

    test "if verifying a token fails when the conn has no secret key" do
      conn = conn(:get, "/")

      any_token = "any token"
      result = CsrfPlus.verify_token(conn, any_token)
      assert match?({:error, "no secret key provided in the Plug conn"}, result)
    end
  end
end
