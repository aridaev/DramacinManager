class AddBgmToAutoPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :auto_posts, :bgm, :boolean, default: true, null: false
  end
end
