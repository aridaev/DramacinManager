# Dijalankan tiap menit (config/recurring.yml): antrekan InstagramPostJob untuk akun AutoPost aktif yang sudah jatuh tempo.
# next_run_at digeser dulu agar tidak diantrekan dua kali bila job sebelumnya masih berjalan.
class AutoPostSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    AutoPost.where(enabled: true).where("next_run_at <= ?", Time.current).order(:next_run_at).find_each do |ap|
      next unless ap.instance&.active? && ap.ready?
      ap.update_columns(next_run_at: Time.current + ap.interval_minutes.minutes)
      InstagramPostJob.perform_later(ap.id) if ap.platform == "instagram"
    end
  end
end
