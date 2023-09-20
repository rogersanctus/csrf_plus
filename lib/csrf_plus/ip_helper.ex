defmodule CsrfPlus.IpHelper do
  @moduledoc false

  def normalize_ip!(ip) do
    {version, ip} = split_ip(ip)

    ip_terms = Enum.map(ip, fn ip_term -> normalize_ip_term(ip_term) end)

    ip =
      case version do
        :maybe_ipv6 ->
          Enum.join(ip_terms, ":")

        :maybe_ipv4 ->
          Enum.join(ip_terms, ".")
      end

    case :inet.parse_address(to_charlist(ip)) do
      {:ok, ip} ->
        ip
        |> :inet.ntoa()
        |> to_string()

      {:error, _} ->
        throw({:error, "Invalid IP address"})
    end
  end

  defp normalize_ip_term(ip_term) do
    if ip_term == "" do
      ip_term
    else
      ip_term
      |> String.to_integer()
      |> to_string()
    end
  end

  defp split_ip(ip) do
    if String.match?(ip, ~r/:/) do
      {:maybe_ipv6, String.split(ip, ":")}
    else
      {:maybe_ipv4, String.split(ip, ".")}
    end
  end
end
