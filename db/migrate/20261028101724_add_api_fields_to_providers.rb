class AddApiFieldsToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :api_url, :string
    add_column :providers, :logo_url, :string
  end
end
