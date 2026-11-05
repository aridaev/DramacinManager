class AddGenresToAutoPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :auto_posts, :genres, :string
  end
end