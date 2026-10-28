class CreateApiSources < ActiveRecord::Migration[8.1]
  def up
    create_table :api_sources do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :base_url, null: false
      t.text    :api_key
      t.string  :auth_mode, null: false, default: "header_x_token"
      t.string  :auth_param
      t.string  :status_path, default: "/api/status"
      t.boolean :is_default, null: false, default: false
      t.boolean :enabled, null: false, default: true
      t.text    :notes
      t.datetime :last_tested_at
      t.string  :last_test_result
      t.timestamps
    end
    add_index :api_sources, :slug, unique: true
    add_index :api_sources, :is_default

    add_reference :providers, :api_source, foreign_key: { on_delete: :nullify }, null: true
    add_column :providers, :auth_mode, :string
    add_column :providers, :adapter_key, :string
    add_column :providers, :api_key, :text
    add_column :providers, :notes, :text
    add_column :providers, :custom, :boolean, null: false, default: false

    # Pindahkan pengaturan lama (settings.dracin_api.*) menjadi sumber default.
    say_with_time "migrate DracinAPI settings → api_sources" do
      base = Setting.find_by(key: "dracin_api.base_url")&.value.presence || "https://api.dramabuzz.sbs"
      key  = Setting.find_by(key: "dracin_api.api_key")&.value
      ApiSource.reset_column_information
      ApiSource.create!(name: "DracinAPI", slug: "dracinapi", base_url: base.chomp("/"), api_key: key,
                        auth_mode: "header_x_token", status_path: "/api/status", is_default: true,
                        notes: "Hub https://api.dramabuzz.sbs — status 44 platform; konten per platform di *.goodbos.online")
    end
  end

  def down
    remove_reference :providers, :api_source
    remove_column :providers, :auth_mode
    remove_column :providers, :adapter_key
    remove_column :providers, :api_key
    remove_column :providers, :notes
    remove_column :providers, :custom
    drop_table :api_sources
  end
end
