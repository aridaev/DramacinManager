# Sinkron profil satu akun AutoPost dari cookie: ambil username IG (dipakai sebagai nama akun), pastikan website
# di bio mengarah ke situs instance (domain aktif), dan isi tautan Instagram instance bila masih kosong.
# Dipanggil saat cookie ditambahkan dan diulang oleh InstagramPostJob paling cepat tiap SYNC_EVERY.
class InstagramProfileSyncJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError
  SYNC_EVERY = 24.hours

  def self.due?(ap) = ap.profile_synced_at.nil? || ap.profile_synced_at < SYNC_EVERY.ago

  def perform(auto_post_id)
    ap = AutoPost.find_by(id: auto_post_id) or return
    instance = ap.instance
    client = AutoPoster::InstagramClient.new(ap.cookie)
    prof = client.profile
    username = prof["username"].to_s.strip
    attrs = { profile_synced_at: Time.current, updated_at: Time.current }
    attrs[:username] = username if username.present?
    # Nama akun otomatis ("IG #123" / "Akun") diganti @username; nama yang diisi manual dipertahankan.
    attrs[:label] = "@#{username}" if username.present? && ap.label.to_s.match?(/\A(IG #\d+|Akun)\z/)

    site = instance.public_url
    if site.start_with?("https://") && prof["external_url"].to_s.strip.chomp("/") != site.chomp("/")
      client.update_profile!(website: site)
      attrs[:profile_status] = "website → #{site}"
      Rails.logger.info("[InstagramProfileSyncJob] auto_post=#{ap.id} @#{username} website diset ke #{site}")
    else
      attrs[:profile_status] = "ok"
    end
    ap.update_columns(attrs)

    # Tautan Instagram instance (footer/sosial) diisi dari akun pertama yang punya username.
    if username.present? && instance.social_instagram.blank?
      instance.social_instagram = "https://instagram.com/#{username}"
      instance.save
    end
  rescue AutoPoster::InstagramClient::AuthError => e
    ap&.update_columns(profile_synced_at: Time.current, profile_status: "AUTH: #{e.message.first(200)}", updated_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("[InstagramProfileSyncJob] auto_post=#{auto_post_id} #{e.class}: #{e.message}")
    ap&.update_columns(profile_synced_at: Time.current, profile_status: "gagal: #{e.message.first(200)}", updated_at: Time.current)
  end
end
