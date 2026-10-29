class CreateVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.references :instance, null: false, foreign_key: true
      t.string  :visitor_id, null: false, limit: 32   # hash harian (ip + ua + instance) → pengunjung unik tanpa menyimpan IP
      t.string  :path, null: false, limit: 300
      t.string  :kind, limit: 20                       # home / drama / watch / search / genre / member / other
      t.string  :provider, limit: 40
      t.string  :drama_id, limit: 80
      t.string  :country, limit: 2
      t.string  :device, limit: 10                     # mobile / tablet / desktop / bot
      t.string  :os, limit: 30
      t.string  :browser, limit: 30
      t.string  :referrer_host, limit: 120
      t.string  :ip_prefix, limit: 24                  # /24 (IPv4) atau /48 (IPv6) saja
      t.string  :user_agent, limit: 300
      t.datetime :created_at, null: false
    end
    add_index :visits, [ :instance_id, :created_at ]
    add_index :visits, [ :instance_id, :visitor_id, :created_at ]
  end
end
