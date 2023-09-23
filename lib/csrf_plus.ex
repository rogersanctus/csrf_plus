defmodule CsrfPlus do
  @moduledoc false
  @behaviour Plug

  alias CsrfPlus.UserAccessInfo
  require Logger

  @default_csrf_key "_csrf_token_"
  @non_csrf_request_methods ["GET", "HEAD", "OPTIONS"]

  # Max token age in milliseconds
  @default_token_max_age 24 * 60 * 60 * 1000

  import Plug.Conn

  def init(opts \\ []) do
    otp_app = Keyword.get(opts, :otp_app)

    if otp_app == nil do
      raise "CsrfPlus requires :otp_app to be set"
    else
      csrf_key = Keyword.get(opts, :csrf_key, @default_csrf_key)

      allowed_methods = Keyword.get(opts, :allowed_methods, @non_csrf_request_methods)

      %{
        otp_app: otp_app,
        csrf_key: csrf_key,
        allowed_methods: allowed_methods
      }
    end
  end

  def call(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  def call(%Plug.Conn{} = conn, opts) do
    allowed_method? = allowed_method?(conn, opts)

    conn
    |> put_private(:plug_csrf_plus_config, fn -> opts end)
    |> check_token(allowed_method?, opts)
  end

  def get_user_info(conn) do
    %UserAccessInfo{
      ip: get_conn_ip(conn),
      user_agent: get_conn_user_agent(conn)
    }
  end

  def default_token_max_age do
    @default_token_max_age
  end

  def generate_token(%Plug.Conn{secret_key_base: nil}) do
    raise "CsrfPlus requires conn.secret_key_base to be set"
  end

  def generate_token(%Plug.Conn{secret_key_base: key}) do
    token = UUID.uuid4()
    signed_token = Plug.Crypto.MessageVerifier.sign(token, key)
    {token, signed_token}
  end

  def verify_token(%Plug.Conn{secret_key_base: nil}, _signed_token) do
    {:error, "no secret key provided in the Plug conn"}
  end

  def verify_token(
        %Plug.Conn{secret_key_base: key},
        signed_token
      ) do
    case Plug.Crypto.MessageVerifier.verify(signed_token, key) do
      :error ->
        {:error, "invalid token"}

      ok ->
        ok
    end
  end

  def put_session_token(%Plug.Conn{} = conn, token) do
    opts = get_opts(conn)
    csrf_key = Map.get(opts, :csrf_key, nil)

    if csrf_key == nil do
      raise "CsrfPlus.put_session_token/2 must be called after CsrfPlus is plugged"
    else
      put_session(conn, csrf_key, token)
    end
  end

  defp get_opts(%Plug.Conn{} = conn) do
    opts_fun = Map.get(conn.private, :plug_csrf_plus_config, fn -> %{} end)

    if is_function(opts_fun) do
      opts_fun.()
    else
      %{}
    end
  end

  defp allowed_method?(
         %Plug.Conn{method: method},
         %{allowed_methods: allowed_methods} = _opts
       ) do
    method in allowed_methods
  end

  def check_token(%Plug.Conn{} = conn, true = _allowed_method?, _opts) do
    conn
  end

  def check_token(%Plug.Conn{} = conn, false = _allowed_method?, opts) do
    access_id = get_session(conn, :access_id)

    header_token =
      conn
      |> get_req_header("x-csrf-token")
      |> Enum.at(0)

    cond do
      is_nil(access_id) ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Missing access_id in the session"}))
        |> halt()

      header_token == nil ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Missing token header"}))
        |> halt()

      true ->
        config = Application.get_env(opts.otp_app, CsrfPlus, [])
        store = Keyword.get(config, :store, nil)

        check_token_store(conn, store, {access_id, header_token})
    end
  end

  defp check_token_store(conn, nil, _to_check) do
    Logger.debug("CsrfPlus: No token store configured")

    conn
    |> send_resp(:unauthorized, Jason.encode!(%{error: "No token store configured"}))
    |> halt()
  end

  defp check_token_store(conn, store, {access_id, header_token}) do
    opts = get_opts(conn)
    csrf_key = Map.get(opts, :csrf_key, nil)
    store_token = store.get_token(access_id)
    session_token = get_session(conn, csrf_key)

    cond do
      session_token == nil ->
        send_resp(conn, :unauthorized, Jason.encode!(%{error: "Missing session token"}))
        |> halt()

      session_token != store_token ->
        Logger.debug(
          "Token mismatch session:#{inspect(session_token)} != store:#{inspect(store_token)}"
        )

        send_resp(conn, :unauthorized, Jason.encode!(%{error: "Invalid token"}))
        |> halt()

      true ->
        conn
        |> verify_token(header_token)
        |> check_token_store_verified(conn, store_token)
    end
  end

  defp check_token_store_verified({:ok, verified_token}, conn, store_token) do
    if verified_token != store_token do
      Logger.debug(
        "Token mismatch: verified_token:#{inspect(verified_token)} != store_token:#{inspect(store_token)}"
      )

      send_resp(conn, :unauthorized, Jason.encode!(%{error: "Invalid token"}))
      |> halt()
    else
      conn
    end
  end

  defp check_token_store_verified({:error, error}, conn, _store_token) do
    Logger.debug("Token validation error: #{inspect(error)}")

    send_resp(conn, :unauthorized, Jason.encode!(%{error: error}))
    |> halt()
  end

  defp get_conn_ip(%Plug.Conn{remote_ip: remote_ip, req_headers: req_headers}) do
    [x_real_ip | _] = List.keyfind(req_headers, "x-real-ip", 0, [nil])
    [x_forwarded_for | _] = List.keyfind(req_headers, "x-forwarded-for", 0, [nil])

    case {remote_ip, x_real_ip, x_forwarded_for} do
      {nil, nil, nil} ->
        nil

      {nil, nil, x_forwarded_for} ->
        x_forwarded_for

      {nil, x_real_ip, nil} ->
        x_real_ip

      {remote_ip, nil, nil} ->
        remote_ip
    end
  end

  defp get_conn_user_agent(%Plug.Conn{} = conn) do
    user_agent = get_req_header(conn, "user-agent")

    if Enum.empty?(user_agent) do
      nil
    else
      hd(user_agent)
    end
  end
end
