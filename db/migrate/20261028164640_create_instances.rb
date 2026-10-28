class CreateInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :instances do |t|
      t.string  :name, null: false                 # nama acak, dibuat otomatis
      t.string  :title                              # label opsional dari admin
      t.integer :status, null: false, default: 0    # active / paused / disabled
      t.text    :notes
      t.jsonb   :settings, null: false, default: {} # konfigurasi instance (logika menyusul)
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
      t.timestamps
    end
    add_index :instances, :name, unique: true
    add_index :instances, :status
  end
end
