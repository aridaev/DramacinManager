class AddCaptionTemplateToAutoPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :auto_posts, :caption_template, :text
  end
end
