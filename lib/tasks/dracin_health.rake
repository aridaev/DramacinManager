# Cek kesehatan semua sumber API (token aktif? kuota? kedaluwarsa? hub hidup?) dan simpan ke api_sources
# (unhealthy_until, health_note, quota_*, key_expires_at). Provider dari sumber yang tidak sehat otomatis
# disembunyikan dari situs publik (Provider.available). Dijadwalkan cron tiap 6 jam (/etc/cron.d/dracin-health):
# untuk hub berkuota (Mola) tiap cek = 1 request, jadi jangan dijadwalkan lebih rapat.
#   bin/rails dracin:health
namespace :dracin do
  desc "Cek kesehatan sumber API (token/kuota/kedaluwarsa) → api_sources"
  task health: :environment do
    DracinApi::Health.check_sources!.each do |src, result|
      puts format("%-12s %s", src.slug, result)
    end
    muted = Provider.where("unavailable_until > ?", Time.current).pluck(:slug)
    puts "Provider sedang dimute (#{muted.size}): #{muted.join(', ')}" if muted.any?
  end
end
