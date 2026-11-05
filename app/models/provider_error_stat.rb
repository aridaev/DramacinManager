# Hitungan harian per penyedia: kind "ok" (berhasil), "rescued" (gagal tapi tertolong fallback), atau jenis error
# (DracinApi::Failure.kind). Dicatat oleh DracinApi::Health, dibaca halaman admin Sumber API.
class ProviderErrorStat < ApplicationRecord
  belongs_to :provider

  OK = "ok".freeze
  RESCUED = "rescued".freeze
  RETENTION = 60.days
  IGNORED_KIND = "not_found".freeze # judul tidak ada (sering dari bot/ID salah) tidak dihitung untuk rekomendasi
  DISCARD_MIN_ERRORS = 15
  DISCARD_RATE = 0.5
  WATCH_MIN_ERRORS = 5
  WATCH_RATE = 0.25

  def self.bump!(provider, kind)
    return if provider.nil?
    now = Time.current
    connection.execute(sanitize_sql_array([ <<~SQL, provider.id, Time.zone.today, kind.to_s, now, now ]))
      INSERT INTO provider_error_stats (provider_id, day, kind, hits, created_at, updated_at)
      VALUES (?, ?, ?, 1, ?, ?)
      ON CONFLICT (provider_id, day, kind)
      DO UPDATE SET hits = provider_error_stats.hits + 1, updated_at = EXCLUDED.updated_at
    SQL
  rescue StandardError => e
    Rails.logger.warn("[ErrorStat] #{provider&.slug}: #{e.class} #{e.message}")
  end

  # Satu baris per penyedia yang punya catatan dalam 30 hari terakhir, error terbanyak (7 hari) di atas.
  def self.report
    today = Time.zone.today
    week_from = today - 6
    acc = Hash.new { |h, k| h[k] = { today: 0, week: 0, month: 0, ok_week: 0, ok_month: 0, real_week: 0, rescued_month: 0, kinds: Hash.new(0) } }
    where(day: (today - 29)..today).group(:provider_id, :day, :kind).sum(:hits).each do |(pid, day, kind), n|
      a = acc[pid]
      case kind
      when OK
        a[:ok_month] += n
        a[:ok_week] += n if day >= week_from
      when RESCUED
        a[:rescued_month] += n
      else
        a[:month] += n
        a[:kinds][kind] += n
        a[:week] += n if day >= week_from
        a[:today] += n if day == today
        a[:real_week] += n if day >= week_from && kind != IGNORED_KIND
      end
    end

    providers = Provider.where(id: acc.keys).includes(:api_source).index_by(&:id)
    rows = acc.filter_map do |pid, a|
      provider = providers[pid] or next
      total = a[:ok_week] + a[:real_week]
      rate = total.zero? ? nil : a[:real_week].fdiv(total)
      a.merge(provider: provider, rate: rate, verdict: verdict(a[:real_week], rate))
    end
    rows.sort_by { |r| [ -r[:week], -r[:month], r[:provider].position ] }
  end

  def self.verdict(real_errors, rate)
    return :no_data if rate.nil?
    return :discard if real_errors >= DISCARD_MIN_ERRORS && rate >= DISCARD_RATE
    return :watch if real_errors >= WATCH_MIN_ERRORS && rate >= WATCH_RATE
    :healthy
  end

  def self.purge_old!
    where("day < ?", Time.zone.today - RETENTION.in_days.to_i).delete_all
  end
end
