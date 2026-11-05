class AddProfileToAutoPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_posts, :username, :string
    add_column :auto_posts, :profile_synced_at, :datetime
    add_column :auto_posts, :profile_status, :string
  end
end