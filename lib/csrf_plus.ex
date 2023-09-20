defmodule CsrfPlus do
  @moduledoc false
  @behaviour Plug

  defmacro __using__(opts) do
    quote do
      unquote(config(opts))
    end
  end

  defp config(opts) do
    quote do
      @otp_app unquote(opts)[:otp_app] || raise("CsrfPlus expects :otp_app to be set")
    end
  end

  alias CsrfPlus.UserAccessInfo
  require Logger

  @default_csrf_key "_csrf_token_"
  @non_csrf_request_methods ["GET", "HEAD", "OPTIONS"]

  # Max token age in milliseconds
  @default_token_max_age 24 * 60 * 60 * 1000

  import Plug.Conn

  def init(opts \\ []) do
    csrf_key = Keyword.get(opts, :csrf_key, @default_csrf_key)
    allowed_origins = Keyword.get(opts, :allowed_origins, [])

    %{
      csrf_key: csrf_key,
      allowed_origins: allowed_origins,
      allowed_methods: @non_csrf_request_methods
    }
  end

  def call(%Plug.Conn{} = conn, %{allowed_methods: allowed_methods} = opts) do
    if conn.method in allowed_methods do
      conn
    else
      {conn, opts} = prepare_for_checks(conn, opts)

      try_do_checks(conn, opts)
    end
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

  defp prepare_for_checks(%Plug.Conn{host: host} = conn, %{allowed_origins: []} = opts)
       when is_binary(host) do
    {conn, Map.put(opts, :allowed_origins, [host])}
  end

  defp prepare_for_checks(
         %Plug.Conn{host: host} = conn,
         %{allowed_origins: allowed_origins} = opts
       ) do
    origins =
      if conn.host in allowed_origins do
        allowed_origins
      else
        [host | allowed_origins]
      end

    {conn, Map.put(opts, :allowed_origins, origins)}
  end

  defp prepare_for_checks(conn, opts) do
    conn =
      conn
      |> send_resp(500, "")
      |> halt()

    {conn, opts}
  end

  defp try_do_checks(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  defp try_do_checks(%Plug.Conn{} = conn, opts) do
    check_origins(conn, opts)
    |> try_check_token(opts)
  end

  defp try_check_token(%Plug.Conn{halted: true} = conn, _opts) do
    conn
  end

  defp try_check_token(%Plug.Conn{} = conn, opts) do
    check_token(conn, opts)
  end

  defp check_token(%Plug.Conn{} = conn, opts) do
    store = Application.get_env(opts.otp_app, :store, Recaptcha.Csrf.Store.BdStore)

    user_info = get_user_info(conn)

    header_token = get_req_header(conn, "x-csrf-token")

    store_token = store.get_token(user_info)

    if header_token == store_token do
      conn
    else
      Logger.debug("Token mismatch: #{inspect(header_token)} != #{inspect(store_token)}")

      conn
      |> send_resp(:unauthorized, Jason.encode!(%{error: "Invalid token"}))
    end
  end

  defp get_conn_ip(%Plug.Conn{remote_ip: remote_ip, req_headers: req_headers}) do
    [x_real_ip | _] = List.keyfind(req_headers, "x-real-ip", 0)
    [x_forwarded_for | _] = List.keyfind(req_headers, "x-forwarded-for", 0)

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
    conn
    |> get_req_header("user-agent")
    |> hd
  end

  defp check_origins(
         %Plug.Conn{req_headers: headers} = conn,
         %{allowed_origins: allowed_origins}
       )
       when is_list(allowed_origins) do
    case List.keyfind(headers, "origin", 0) do
      nil ->
        conn
        |> send_resp(:unauthorized, Jason.encode!(%{error: "Missing Origin header"}))
        |> halt()

      origin ->
        allowed_origins
        |> Enum.any?(fn allowed_origin -> check_origin(origin, allowed_origin) end)
        |> check_origins_result(conn)
    end
  end

  defp check_origins_result(true, conn) do
    conn
  end

  defp check_origins_result(false, conn) do
    conn
    |> send_resp(:unauthorized, Jason.encode!(%{error: "Origin not allowed"}))
    |> halt()
  end

  defp check_origin(origin, allowed_origin) when is_binary(allowed_origin) do
    origin == allowed_origin
  end

  defp check_origin(origin, %Regex{} = allowed_origin) do
    Regex.match?(allowed_origin, origin)
  end

  defp check_origin(origin, allowed_origin) when is_function(allowed_origin) do
    allowed_origin.(origin)
  end

  defp check_origin(_origin, _allowed_origin) do
    false
  end
end
