class AddAutoTitleToAutoPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :auto_posts, :auto_title, :boolean, default: true, null: false
    add_column :auto_posts, :episodes_per_title, :integer, default: 3, null: false
    add_column :auto_posts, :title_episodes, :integer, default: 0, null: false
    add_column :auto_posts, :posted_titles, :jsonb, default: [], null: false
  end
end
