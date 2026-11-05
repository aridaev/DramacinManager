class CreateTelegramPromos < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_promos do |t|
      t.references :telegram_target, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :enabled, null: false, default: true
      t.boolean :has_image, null: false, default: false
      t.integer :sent_count, null: false, default: 0
      t.datetime :last_sent_at
      t.timestamps
    end

    # Jadwal promosi terpisah dari jadwal video, per tujuan (grup/channel/topic).
    add_column :telegram_targets, :promo_enabled, :boolean, null: false, default: false
    add_column :telegram_targets, :promo_interval_minutes, :integer, null: false, default: 180
    add_column :telegram_targets, :promo_next_run_at, :datetime
    add_column :telegram_targets, :promo_last_run_at, :datetime
    add_column :telegram_targets, :promo_last_status, :string
    add_column :telegram_targets, :promo_cursor, :bigint
    add_column :telegram_targets, :promo_posts_count, :integer, null: false, default: 0
    add_column :telegram_targets, :promo_error_streak, :integer, null: false, default: 0
    add_index :telegram_targets, [ :promo_enabled, :promo_next_run_at ]
  end
end
