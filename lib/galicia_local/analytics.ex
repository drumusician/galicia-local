defmodule GaliciaLocal.Analytics do
  use Ash.Domain,
    otp_app: :galicia_local

  resources do
    resource GaliciaLocal.Analytics.PageView
  end
end
