defmodule GaliciaLocal.Directory do
  use Ash.Domain,
    otp_app: :galicia_local

  resources do
    resource GaliciaLocal.Directory.Region
    resource GaliciaLocal.Directory.City
    resource GaliciaLocal.Directory.CityTranslation
    resource GaliciaLocal.Directory.Category
    resource GaliciaLocal.Directory.CategoryTranslation
    resource GaliciaLocal.Directory.Business
    resource GaliciaLocal.Directory.BusinessTranslation
    resource GaliciaLocal.Directory.ScrapeJob
    resource GaliciaLocal.Directory.BusinessClaim
  end
end
