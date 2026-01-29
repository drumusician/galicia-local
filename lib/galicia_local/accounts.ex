defmodule GaliciaLocal.Accounts do
  use Ash.Domain,
    otp_app: :galicia_local

  resources do
    resource GaliciaLocal.Accounts.Token
    resource GaliciaLocal.Accounts.User
  end
end
