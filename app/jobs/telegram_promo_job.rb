# Satu siklus promosi untuk satu TelegramTarget: kirim teks (+ gambar opsional) promo aktif berikutnya (rotasi)
# lewat sidecar. Jadwalnya (promo_next_run_at) terpisah dari jadwal video; tidak butuh render sehingga tidak
# memakai kunci video_post.
class TelegramPromoJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(target_id, manual: false)
    t = TelegramTarget.find_by(id: target_id)
    return unless t && (t.promo_enabled? || manual)
    account = t.telegram_account
    t.update_columns(promo_last_run_at: Time.current, promo_next_run_at: (Time.current + t.promo_interval_minutes.minutes if t.promo_enabled?))
    raise AutoPost::RunError, I18n.t("admin.telegram.need_login") unless account.logged_in?
    promo = t.next_promo or raise AutoPost::RunError, I18n.t("admin.telegram.promo.need_active", title: t.display_title)
    image = promo.image_path.to_s if promo.image_exists?

    result = TelegramClient.from_settings.send_promo(account.session, peer: t.peer, text: promo.body, image: image)
    account.refresh_session!(result["session"])
    promo.update_columns(sent_count: promo.sent_count + 1, last_sent_at: Time.current)
    Rails.logger.info("[TelegramPromoJob] target=#{t.id} #{t.display_title} promo=#{promo.id}#{' +gambar' if image}")
    t.record_promo!(ok: true, promo: promo, url: result["link"])
  rescue TelegramClient::AuthError => e
    t&.record_promo!(ok: false, promo: promo, error: "AUTH: #{e.message}")
    account&.mark_auth_failed!(e.message)
  rescue TelegramClient::FloodWait => e
    t&.record_promo!(ok: false, promo: promo, error: e.message)
    t&.update_columns(promo_next_run_at: Time.current + e.seconds.seconds + 30.seconds) if t&.promo_enabled?
  rescue TelegramClient::Forbidden => e
    t&.record_promo_forbidden!(e.message, promo: promo)
  rescue StandardError => e
    Rails.logger.error("[TelegramPromoJob] target=#{target_id} #{e.class}: #{e.message}")
    t&.record_promo!(ok: false, promo: promo, error: "#{e.class.name.demodulize}: #{e.message}")
  end
end
