defmodule GaliciaLocal.Repo.Migrations.CreateCityTranslations do
  use Ecto.Migration

  def change do
    create table(:city_translations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :city_id, references(:cities, type: :uuid, on_delete: :delete_all), null: false
      add :locale, :text, null: false
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:city_translations, [:city_id, :locale])
    create index(:city_translations, [:locale])
  end
end
