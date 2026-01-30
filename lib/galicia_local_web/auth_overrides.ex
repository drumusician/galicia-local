defmodule GaliciaLocalWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  override AshAuthentication.Phoenix.Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "🐚 GaliciaLocal"
    set :text_class, "text-3xl font-bold text-primary tracking-tight"
  end

  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "min-h-[80vh] flex items-center justify-center bg-base-200 px-4"
  end

  override AshAuthentication.Phoenix.Components.SignIn do
    set :root_class, "w-full max-w-md bg-base-100 rounded-xl shadow-lg p-8"
  end
end
