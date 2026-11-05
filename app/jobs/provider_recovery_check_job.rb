# Cek berkala apakah penyedia yang disembunyikan (gagal beruntun) sudah hidup kembali.
#   perform                  → (dijadwalkan tiap 5 menit, config/recurring.yml) antrekan cek untuk semua penyedia yang dimute
#                              + satu penyedia wakil dari tiap sumber API yang sedang tidak sehat
#   perform(provider_id)     → probe satu penyedia (juga dipakai tombol "Cek sekarang" di admin)
# Probe memanggil adapter penyedia langsung (tanpa cache dan tanpa fallback hub) supaya hasilnya benar-benar mencerminkan
# penyedia itu. Berhasil → Health.ok! (mute dicabut, sumber ditandai sehat). Gagal → mute dibiarkan, hasil dicatat.
class ProviderRecoveryCheckJob < ApplicationJob
  queue_as :default
  MIN_INTERVAL = 4.minutes

  def perform(provider_id = nil)
    return enqueue_due if provider_id.nil?

    provider = Provider.find_by(id: provider_id) or return
    probe(provider)
  end

  private
  def enqueue_due
    now = Time.current
    ids = Provider.where("unavailable_until > ?", now)
                  .where("recovery_checked_at IS NULL OR recovery_checked_at <= ?", MIN_INTERVAL.ago).pluck(:id)
    ApiSource.unhealthy.each do |src|
      ids << Provider.enabled.where(api_source_id: src.id).ordered.limit(1).pick(:id)
    end
    ids.compact.uniq.each { |id| self.class.perform_later(id) }
  end

  def probe(provider)
    adapter = DracinApi::Adapters.for(provider, lang: "id")
    return record(provider, "Tidak ada adapter untuk penyedia ini") if adapter.nil?

    sections = Array(adapter.home)
    items = sections.sum { |section| Array(section.items).size }
    first = sections.flat_map { |section| Array(section.items) }.first
    return record(provider, "Masih gagal: katalog kosong") if first.nil?

    # Beranda saja tidak cukup: halaman detail yang dibuka pengunjung harus ikut berhasil, kalau tidak penyedia
    # akan hidup-mati terus (beranda lolos, detail/putar ditolak).
    adapter.detail(first.id)
    DracinApi::Health.ok!(provider, adapter: adapter)
    record(provider, "Hidup kembali (#{items} judul)")
    Rails.logger.info("[Recovery] #{provider.slug} hidup kembali (#{items} judul)")
  rescue StandardError => e
    record(provider, "Masih gagal: #{e.message}".truncate(250))
    Rails.logger.info("[Recovery] #{provider.slug} masih gagal: #{e.class} #{e.message.to_s.truncate(120)}")
  end

  def record(provider, result)
    provider.update_columns(recovery_checked_at: Time.current, recovery_result: result)
  end
end
