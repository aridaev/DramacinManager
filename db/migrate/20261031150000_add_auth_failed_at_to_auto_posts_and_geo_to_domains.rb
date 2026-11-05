class AddAuthFailedAtToAutoPostsAndGeoToDomains < ActiveRecord::Migration[8.0]
  def change
    # Cookie Instagram mati (AUTH gagal berturut-turut) → akun dinonaktifkan otomatis dan ditandai di sini;
    # direset saat cookie baru disimpan.
    add_column :auto_posts, :auth_failed_at, :datetime
    # Pembatasan negara di Cloudflare (WAF custom rule): "ID" = hanya Indonesia yang boleh mengakses situs publik.
    add_column :domains, :geo_country, :string
    add_column :domains, :cf_geo_ruleset_id, :string
  end
end
