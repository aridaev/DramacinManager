class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :category, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :last_status
      t.integer :last_latency_ms
      t.datetime :last_checked_at

      t.timestamps
    end
    add_index :providers, :slug, unique: true
    add_index :providers, :enabled
  end
end
