class CreateTelegramAccountsAndTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_accounts do |t|
      t.references :instance, null: false, foreign_key: true, index: { unique: true }
      t.text :session
      t.bigint :tg_user_id
      t.string :username
      t.string :display_name
      t.string :phone
      t.datetime :logged_in_at
      t.datetime :auth_failed_at
      t.datetime :dialogs_synced_at
      t.string :last_error
      t.timestamps
    end

    create_table :telegram_targets do |t|
      t.references :telegram_account, null: false, foreign_key: true
      t.string :peer_kind, null: false
      t.bigint :peer_id, null: false
      t.text :access_hash
      t.string :title, null: false
      t.string :username
      t.string :chat_type
      t.boolean :can_post, null: false, default: true
      t.boolean :enabled, null: false, default: false
      t.integer :interval_minutes, null: false, default: 60
      t.integer :max_seconds, null: false, default: 90
      t.boolean :auto_title, null: false, default: true
      t.integer :episodes_per_title, null: false, default: 3
      t.string :genres
      t.boolean :remix, null: false, default: true
      t.boolean :bgm, null: false, default: false
      t.text :fixed_text
      t.string :provider_slug
      t.string :drama_id
      t.string :drama_title
      t.integer :last_episode
      t.integer :last_part
      t.integer :parts_total
      t.integer :title_episodes, null: false, default: 0
      t.jsonb :posted_titles, null: false, default: []
      t.text :caption_template
      t.text :caption_tags
      t.integer :posts_count, null: false, default: 0
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.string :last_status
      t.jsonb :log, null: false, default: []
      t.integer :error_streak, null: false, default: 0
      t.timestamps
    end
    add_index :telegram_targets, [ :telegram_account_id, :peer_kind, :peer_id ], unique: true, name: "idx_tg_targets_peer"
    add_index :telegram_targets, [ :enabled, :next_run_at ]
  end
end
