class AddHealthToProvidersAndApiSources < ActiveRecord::Migration[8.0]
  def change
    # Kesehatan provider dari pengalaman nyata (DracinApi::Health): gagal beruntun → disembunyikan sementara dari situs publik.
    change_table :providers do |t|
      t.integer :failures_count, null: false, default: 0
      t.integer :mute_level, null: false, default: 0     # backoff: 0 → 30 mnt, 1 → 1 jam, 2 → 3 jam
      t.string :last_error
      t.datetime :last_error_at
      t.datetime :last_ok_at
      t.datetime :unavailable_until
    end
    add_index :providers, :unavailable_until

    # Kesehatan sumber API (token mati / kuota habis / host down) → semua provider sumber itu disembunyikan.
    change_table :api_sources do |t|
      t.datetime :unhealthy_until
      t.string :health_note
      t.datetime :health_checked_at
      t.integer :quota_limit
      t.integer :quota_used
      t.datetime :key_expires_at
    end
  end
end
