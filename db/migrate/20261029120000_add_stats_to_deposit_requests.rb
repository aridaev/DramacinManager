class AddStatsToDepositRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :deposit_requests, :amount_value, :bigint
    add_column :deposit_requests, :adfree_until, :datetime
    add_index  :deposit_requests, [ :instance_id, :reviewed_at ]
    execute <<~SQL
      UPDATE deposit_requests SET amount_value = NULLIF(regexp_replace(COALESCE(amount, ''), '[^0-9]', '', 'g'), '')::bigint
    SQL
  end

  def down
    remove_index  :deposit_requests, [ :instance_id, :reviewed_at ]
    remove_column :deposit_requests, :adfree_until
    remove_column :deposit_requests, :amount_value
  end
end
