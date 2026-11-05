class AddTopicToTelegramTargets < ActiveRecord::Migration[8.1]
  def change
    # topic_id 0 = bukan topic (grup/channel biasa); >0 = topic forum (1 = General).
    add_column :telegram_targets, :topic_id, :bigint, null: false, default: 0
    add_column :telegram_targets, :topic_title, :string

    remove_index :telegram_targets, name: "idx_tg_targets_peer", column: [ :telegram_account_id, :peer_kind, :peer_id ], unique: true
    add_index :telegram_targets, [ :telegram_account_id, :peer_kind, :peer_id, :topic_id ], unique: true, name: "idx_tg_targets_peer"
  end
end
