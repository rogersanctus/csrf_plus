defmodule CsrfPlus.CsrfPlusTest do
  use ExUnit.Case

  import Plug.Test
  alias CsrfPlus

  def build_conn(method, path) do
    conn = conn(method, path)

    %{
      conn
      | # Generated with :crypto.strong_rand_bytes(64) |> Base.encode64()
        secret_key_base:
          "96uqV4XL/GpDMgDDc7/G2p6AO1PM6FqI5b4JnyUh95F2bUtGDA5Uee1eHd+vaxmB6ilrZfU6ZglBJI6Wo7tW9A=="
    }
  end

  def build_session_conn(method, path) do
    config =
      Plug.Session.init(key: "_session_test", store: :cookie, signing_salt: "$salt4meSalTforU&")

    build_conn(method, path)
    |> Plug.Session.call(config)
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
        build_session_conn(:post, "/")
        |> Plug.Conn.fetch_session()
        |> Plug.Conn.put_session(:access_id, CsrfPlus.OkStoreMock.access_id())
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

  describe "CSRF tokens generation" do
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

  describe "CsrfPlus validations" do
    test "if it can put a token into the session" do
      Mox.stub_with(CsrfPlus.StoreMock, CsrfPlus.OkStoreMock)
      plug_config = CsrfPlus.init(otp_app: :test_app, csrf_key: :csrf_token)

      conn =
        build_session_conn(:get, "/")
        |> Plug.Conn.fetch_session()
        |> CsrfPlus.call(plug_config)

      {token, signed} = CsrfPlus.generate_token(conn)
      new_conn = CsrfPlus.put_session_token(conn, token)

      conn_token = Plug.Conn.get_session(new_conn, :csrf_token)
      result = CsrfPlus.verify_token(new_conn, signed)

      assert conn_token == token
      assert match?({:ok, ^token}, result)
    end
  end
end
