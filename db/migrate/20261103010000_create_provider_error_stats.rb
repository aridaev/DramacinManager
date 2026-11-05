class CreateProviderErrorStats < ActiveRecord::Migration[8.0]
  def change
    # Hitungan harian per penyedia & jenis (ok / rescued / jenis error) untuk menilai penyedia mana yang layak dibuang.
    create_table :provider_error_stats do |t|
      t.references :provider, null: false, foreign_key: true
      t.date :day, null: false
      t.string :kind, null: false
      t.integer :hits, null: false, default: 0
      t.timestamps
    end
    add_index :provider_error_stats, [ :provider_id, :day, :kind ], unique: true, name: "index_provider_error_stats_unique"
    add_index :provider_error_stats, :day
  end
end
