class AddRemixToAutoPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :auto_posts, :remix, :boolean, default: true, null: false
  end
end
