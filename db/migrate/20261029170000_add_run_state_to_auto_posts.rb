class AddRunStateToAutoPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :auto_posts, :last_episode, :integer
    add_column :auto_posts, :account_cursor, :integer, null: false, default: 0
    add_column :auto_posts, :posts_count, :integer, null: false, default: 0
    add_column :auto_posts, :log, :jsonb, null: false, default: []
  end
end
