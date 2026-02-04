defmodule GaliciaLocal.Repo.Migrations.CreateBusinessTranslations do
  use Ecto.Migration

  def change do
    create table(:business_translations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :business_id, references(:businesses, type: :uuid, on_delete: :delete_all), null: false
      add :locale, :text, null: false
      add :description, :text
      add :summary, :text
      add :highlights, {:array, :text}, default: []
      add :warnings, {:array, :text}, default: []
      add :integration_tips, {:array, :text}, default: []
      add :cultural_notes, {:array, :text}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:business_translations, [:business_id, :locale])
    create index(:business_translations, [:locale])
  end
end
