class CreateAutoPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :auto_posts do |t|
      t.references :instance, null: false, foreign_key: { on_delete: :cascade }
      t.string   :platform, null: false, default: "instagram"
      t.boolean  :enabled, null: false, default: false
      t.jsonb    :cookies, null: false, default: []
      t.string   :provider_slug
      t.string   :drama_id
      t.string   :drama_title
      t.integer  :interval_minutes, null: false, default: 60
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.string   :last_status
      t.timestamps
    end
    add_index :auto_posts, [ :instance_id, :platform ], unique: true
    add_index :auto_posts, :next_run_at
  end
end
