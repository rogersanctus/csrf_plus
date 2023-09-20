defmodule CsrfPlus.Helper do
  require Logger

  def get_header(%Plug.Conn{req_headers: headers} = _conn, key) do
    case List.keyfind(headers, key, 0, nil) do
      nil -> nil
      {_key, value} -> value
    end
  end
end
