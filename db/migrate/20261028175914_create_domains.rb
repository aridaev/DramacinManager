class CreateDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :domains do |t|
      t.references :instance, null: false, foreign_key: { on_delete: :cascade }
      t.string  :hostname, null: false
      t.integer :status, null: false, default: 0   # pending_ns / active / error / removed
      t.string  :cf_zone_id
      t.jsonb   :cf_nameservers, null: false, default: []
      t.string  :cf_status                           # status zone dari CF: pending / active / moved
      t.text    :last_error
      t.datetime :last_checked_at
      t.datetime :activated_at
      t.timestamps
    end
    add_index :domains, :hostname, unique: true
    add_index :domains, :status
  end
end
