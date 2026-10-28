class CreateMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.references :instance, null: false, foreign_key: { on_delete: :cascade }
      t.string   :username, null: false
      t.string   :password_digest, null: false
      t.datetime :adfree_until
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :members, [ :instance_id, :username ], unique: true

    create_table :deposit_requests do |t|
      t.references :instance, null: false, foreign_key: { on_delete: :cascade }
      t.references :member,   null: false, foreign_key: { on_delete: :cascade }
      t.integer  :status, null: false, default: 0   # pending / approved / rejected
      t.string   :amount
      t.integer  :days
      t.string   :note
      t.string   :proof_path
      t.string   :proof_type
      t.integer  :proof_size
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :deposit_requests, [ :instance_id, :status ]
  end
end
