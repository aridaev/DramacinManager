module AutoPoster
  # Logika bersama job posting (Instagram & Telegram): menentukan judul + episode/part berikutnya untuk objek yang
  # punya antarmuka AutoPost, membersihkan folder kerja sisa, dan locale instance.
  module TitleResolver
    private

    # Judul otomatis: bila belum ada judul, jatah episode judul ini habis, atau episode terbuka sudah habis →
    # TitlePicker memilih judul baru (statistik → acak terbaru), maksimal 2x ganti.
    def resolve_target(ap, locale, hops = 0)
      AutoPoster::TitlePicker.new(ap, locale: locale).pick! if ap.auto_title? && (ap.drama_id.blank? || ap.title_done?)
      provider = ap.provider or raise AutoPost::RunError, "penyedia #{ap.provider_slug} tidak ada"
      catalog = DracinApi::Catalog.for(provider, lang: locale)
      drama = catalog.detail(ap.drama_id)
      episodes = catalog.episodes(ap.drama_id).reject(&:locked).sort_by(&:number)

      ep = part = nil
      if ap.more_parts?
        ep = episodes.find { |e| e.number == ap.last_episode }
        part = ap.last_part + 1
      end
      unless ep
        ep = episodes.find { |e| e.number > ap.last_episode.to_i }
        part = 1
      end
      if ep.nil? && ap.auto_title? # judul ini tidak punya episode (lagi) → judul berikutnya
        raise AutoPost::RunError, "tidak ada episode terbuka di #{ap.drama_title}" if hops >= 2
        AutoPoster::TitlePicker.new(ap, locale: locale).pick!
        return resolve_target(ap, locale, hops + 1)
      end
      ep ||= episodes.first or raise AutoPost::RunError, "tidak ada episode terbuka" # manual: habis → ulang dari awal
      [ catalog, drama, ep, part ]
    end

    # Dir.mktmpdir dengan blok sudah menghapus folder kerja; sisa folder hanya ada bila proses dimatikan di tengah jalan.
    def sweep_stale_tmp(prefix)
      Dir.glob(File.join(Dir.tmpdir, "#{prefix}*")).each do |d|
        FileUtils.rm_rf(d) if File.directory?(d) && File.mtime(d) < 2.hours.ago
      end
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] sweep tmp: #{e.message}")
    end

    def instance_locale(instance) = (instance.respond_to?(:default_locale) && instance.default_locale.presence) || I18n.default_locale.to_s
  end
end
