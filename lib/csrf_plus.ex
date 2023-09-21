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

      %{
        otp_app: otp_app,
        csrf_key: csrf_key,
        allowed_methods: @non_csrf_request_methods
      }
    end
  end

  def call(%Plug.Conn{} = conn, opts) do
    try_do_checks(conn, opts)
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

  defp try_do_checks(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  defp try_do_checks(%Plug.Conn{} = conn, %{allowed_methods: allowed_methods} = opts) do
    if conn.method in allowed_methods do
      conn
    else
      try_check_token(conn, opts)
    end
  end

  defp try_check_token(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  defp try_check_token(%Plug.Conn{} = conn, opts) do
    check_token(conn, opts)
  end

  defp check_token(%Plug.Conn{} = conn, opts) do
    config = Application.get_env(opts.otp_app, CsrfPlus, nil)
    store = Keyword.get(config, :store, nil)

    check_token_store(conn, store)
  end

  defp check_token_store(conn, nil) do
    Logger.debug("CsrfPlus: No token store configured")

    conn
    |> send_resp(:unauthorized, Jason.encode!(%{error: "No token store configured"}))
    |> halt()
  end

  defp check_token_store(conn, store) do
    user_info = get_user_info(conn)

    header_token = get_req_header(conn, "x-csrf-token")

    header_token = if Enum.empty?(header_token), do: nil, else: hd(header_token)

    store_token = store.get_token(user_info)

    cond do
      header_token == nil ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Missing token header"}))
        |> halt()

      store_token == nil ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Token is not set in the store"}))
        |> halt()

      header_token == store_token ->
        conn

      true ->
        Logger.debug("Token mismatch: #{inspect(header_token)} != #{inspect(store_token)}")

        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Invalid token"}))
        |> halt()
    end
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