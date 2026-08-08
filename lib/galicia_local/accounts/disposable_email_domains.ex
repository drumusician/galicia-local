defmodule GaliciaLocal.Accounts.DisposableEmailDomains do
  @moduledoc """
  Checks an address against the throwaway-mail domains listed in
  `priv/disposable_email_domains.txt`.

  The list is read at compile time so lookups cost nothing at runtime, and the
  file is registered as an external resource so editing it forces a recompile.

  This is a curated list rather than an exhaustive one. It is meant to stop the
  bulk of automated signups cheaply; anyone determined can register a fresh
  domain and get through. The rate limiter and the unconfirmed-signup sweep
  cover what slips past.
  """

  @path Application.app_dir(:galicia_local, "priv/disposable_email_domains.txt")
  @external_resource @path

  @domains @path
           |> File.read!()
           |> String.split("\n", trim: true)
           |> Enum.map(&String.trim/1)
           |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
           |> Enum.map(&String.downcase/1)
           |> MapSet.new()

  @doc "Every blocked domain. Exposed mainly so tests can assert against it."
  def domains, do: @domains

  @doc """
  Returns true when `email`'s domain is a known throwaway provider.

  Subdomains count: an address at `foo.mailinator.com` is blocked by the
  `mailinator.com` entry, since these services hand out arbitrary subdomains.

  Anything that is not a parseable address returns false — rejecting malformed
  input is the job of the email validation, not this check.
  """
  def disposable?(email) do
    case email |> to_string() |> String.split("@") do
      [_local, domain] when domain != "" -> blocked_domain?(String.downcase(domain))
      _ -> false
    end
  end

  defp blocked_domain?(domain) do
    domain
    |> String.split(".")
    |> parent_domains()
    |> Enum.any?(&MapSet.member?(@domains, &1))
  end

  # ["foo", "mailinator", "com"] -> ["foo.mailinator.com", "mailinator.com", "com"]
  defp parent_domains([]), do: []

  defp parent_domains([_ | rest] = labels) do
    [Enum.join(labels, ".") | parent_domains(rest)]
  end
end
