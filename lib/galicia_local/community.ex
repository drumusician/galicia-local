defmodule GaliciaLocal.Community do
  use Ash.Domain,
    otp_app: :galicia_local

  resources do
    resource GaliciaLocal.Community.Review
    resource GaliciaLocal.Community.Favorite
    resource GaliciaLocal.Community.Suggestion
  end
end
