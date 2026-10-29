require "json"

# Satu AutoPost = satu akun Instagram (satu cookie) dengan kontennya sendiri. Baris lama yang punya beberapa
# cookie dipecah: cookie pertama tetap di baris itu, sisanya jadi baris baru dengan pengaturan sama.
class RestructureAutoPostsPerAccount < ActiveRecord::Migration[8.1]
  def up
    add_column :auto_posts, :label, :string
    add_column :auto_posts, :cookie, :text
    add_column :auto_posts, :max_seconds, :integer, null: false, default: 90
    add_column :auto_posts, :fixed_text, :text
    add_column :auto_posts, :last_part, :integer
    add_column :auto_posts, :parts_total, :integer
    add_column :auto_posts, :caption_tags, :text
    remove_index :auto_posts, [ :instance_id, :platform ]
    add_index :auto_posts, [ :instance_id, :platform ]

    fixed = quote(AutoPost::DEFAULT_FIXED_TEXT)
    select_all("SELECT id, cookies FROM auto_posts ORDER BY id").each do |r|
      list = (JSON.parse(r["cookies"].to_s) rescue []).select { |c| c.is_a?(Hash) && c["cookie"].present? }
      first, *rest = list
      execute("UPDATE auto_posts SET label = #{quote(first&.dig('label'))}, cookie = #{quote(first&.dig('cookie'))}, fixed_text = #{fixed}, caption_template = NULL WHERE id = #{r['id']}")
      rest.each_with_index do |c, i|
        execute(<<~SQL)
          INSERT INTO auto_posts (instance_id, platform, enabled, provider_slug, drama_id, drama_title, interval_minutes, next_run_at,
                                  label, cookie, max_seconds, fixed_text, cookies, created_at, updated_at)
          SELECT instance_id, platform, enabled, provider_slug, drama_id, drama_title, interval_minutes, next_run_at + interval '#{(i + 1) * 5} minutes',
                 #{quote(c['label'])}, #{quote(c['cookie'])}, 90, #{fixed}, '[]', now(), now()
          FROM auto_posts WHERE id = #{r['id']}
        SQL
      end
    end

    remove_column :auto_posts, :cookies
    remove_column :auto_posts, :account_cursor
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
