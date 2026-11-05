# Dijalankan tiap menit (config/recurring.yml): antrekan InstagramPostJob / TelegramPostJob / TelegramPromoJob untuk
# akun/tujuan aktif yang sudah jatuh tempo. next_run_at digeser dulu agar tidak diantrekan dua kali bila job
# sebelumnya masih berjalan.
class AutoPostSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    AutoPost.where(enabled: true).where("next_run_at <= ?", Time.current).order(:next_run_at).find_each do |ap|
      next unless ap.instance&.active? && ap.ready?
      ap.update_columns(next_run_at: Time.current + ap.interval_minutes.minutes)
      InstagramPostJob.perform_later(ap.id) if ap.platform == "instagram"
    end
    busy = schedule_telegram
    schedule_promos(busy)
  end

  private
  # Satu akun Telegram hanya boleh memposting (video atau promo) satu tujuan per TARGET_GAP agar tidak memicu
  # FloodWait; tujuan yang tertahan dijadwalkan ulang sebentar lagi (bukan menunggu satu interval penuh).
  # Mengembalikan himpunan id akun yang sudah dipakai pada putaran ini.
  def schedule_telegram
    busy = Set.new
    TelegramTarget.where(enabled: true).where("next_run_at <= ?", Time.current).includes(telegram_account: :instance).order(:next_run_at).find_each do |t|
      account = t.telegram_account
      next unless account.logged_in? && account.instance&.active? && t.ready?
      if busy.include?(account.id) || recently_posted?(account)
        t.update_columns(next_run_at: Time.current + TelegramTarget::TARGET_GAP)
        next
      end
      busy << account.id
      t.update_columns(next_run_at: Time.current + t.interval_minutes.minutes)
      TelegramPostJob.perform_later(t.id)
    end
    busy
  end

  def schedule_promos(busy)
    TelegramTarget.where(promo_enabled: true).where("promo_next_run_at <= ?", Time.current).includes(telegram_account: :instance).order(:promo_next_run_at).find_each do |t|
      account = t.telegram_account
      next unless account.logged_in? && account.instance&.active? && t.ready? && t.promos.active.exists?
      if busy.include?(account.id) || recently_posted?(account)
        t.update_columns(promo_next_run_at: Time.current + TelegramTarget::TARGET_GAP)
        next
      end
      busy << account.id
      t.update_columns(promo_next_run_at: Time.current + t.promo_interval_minutes.minutes)
      TelegramPromoJob.perform_later(t.id)
    end
  end

  def recently_posted?(account)
    since = Time.current - TelegramTarget::TARGET_GAP
    TelegramTarget.where(telegram_account_id: account.id).where("last_run_at > :t OR promo_last_run_at > :t", t: since).exists?
  end
end
