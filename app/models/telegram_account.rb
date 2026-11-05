# Satu akun Telegram (login QR via MTProto) per instance. Session terenkripsi; api_id/api_hash global di Setting.
# Sidecar Telethon stateless: session dikirim di setiap panggilan, dan bila Telegram merotasi key, session baru
# dikembalikan lalu disimpan di sini.
class TelegramAccount < ApplicationRecord
  belongs_to :instance
  has_many :targets, class_name: "TelegramTarget", dependent: :destroy

  encrypts :session

  def logged_in? = session.present? && auth_failed_at.nil?
  def auth_dead? = auth_failed_at.present?
  def label = username.present? ? "@#{username}" : (display_name.presence || "Telegram ##{tg_user_id}")

  def self.for(instance) = instance.telegram_account || instance.build_telegram_account

  def store_login!(session:, user:)
    update!(session: session, tg_user_id: user["id"], username: user["username"], display_name: user["name"], phone: user["phone"],
            logged_in_at: Time.current, auth_failed_at: nil, last_error: nil)
  end

  def mark_auth_failed!(message)
    update_columns(auth_failed_at: Time.current, last_error: message.to_s.first(200), updated_at: Time.current)
    targets.update_all(enabled: false, next_run_at: nil, promo_enabled: false, promo_next_run_at: nil, updated_at: Time.current)
  end

  def refresh_session!(new_session)
    update_columns(session: self.class.encrypt_value(new_session), updated_at: Time.current) if new_session.present?
  end

  def self.encrypt_value(v) = type_for_attribute("session").serialize(v)

  # Muat dialog (grup/channel, dan tiap topic untuk grup forum) dari Telegram lalu perbarui telegram_targets:
  # tujuan baru ditambahkan (nonaktif), yang sudah ada diperbarui judul/hak posting-nya, yang sudah tidak ada
  # dibiarkan (admin bisa menghapus). Tiap topic forum = satu tujuan sendiri dengan jadwal sendiri.
  def sync_dialogs!(client = TelegramClient.from_settings)
    res = client.dialogs(session)
    refresh_session!(res["session"])
    items = Array(res["dialogs"])
    items.each do |d|
      topic_id = d["topic_id"].to_i
      t = targets.find_by(peer_kind: d["peer_kind"], peer_id: d["peer_id"], topic_id: topic_id)
      # Baris lama (sebelum ada topic) milik grup yang kini forum → jadi topic General agar jadwalnya tidak hilang.
      t ||= targets.find_by(peer_kind: d["peer_kind"], peer_id: d["peer_id"], topic_id: 0) if topic_id == 1
      t ||= targets.new(peer_kind: d["peer_kind"], peer_id: d["peer_id"])
      t.assign_attributes(title: d["title"].to_s.first(200).presence || "(tanpa nama)", username: d["username"], chat_type: d["chat_type"],
                          can_post: d["can_post"] ? true : false, access_hash: d["access_hash"]&.to_s,
                          topic_id: topic_id, topic_title: d["topic_title"].to_s.first(200).presence)
      t.fixed_text = TelegramTarget::DEFAULT_FIXED_TEXT if t.new_record? && t.fixed_text.blank?
      t.genres = AutoPost::DEFAULT_GENRES if t.new_record? && t.genres.blank?
      t.save!
    end
    update_columns(dialogs_synced_at: Time.current, updated_at: Time.current)
    items.size
  end
end
