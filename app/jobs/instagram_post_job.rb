require "tmpdir"

# Satu siklus auto posting Instagram untuk satu AutoPost (= satu akun): tentukan episode/part berikutnya dari judul
# yang dipilih, render video Reels (9:16 + watermark instance terbakar, dipotong sesuai max_seconds akun), buat
# caption (template TokenPlus per judul + teks tetap + hashtag), unggah dengan cookie akun. Episode yang lebih
# panjang dari max_seconds dipecah jadi Part 1..n: part berikutnya dijadwalkan PART_GAP kemudian, setelah part
# terakhir episode berikutnya mengikuti interval akun. Hasil/galat dicatat di last_status + log.
class InstagramPostJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError
  # Render ffmpeg berat (4 core) → satu posting dalam satu waktu untuk semua akun.
  limits_concurrency to: 1, key: "instagram_post", duration: 20.minutes
  PART_GAP = 3.minutes

  # manual: true (tombol "Posting sekarang") → jalan walau auto posting belum diaktifkan.
  def perform(auto_post_id, manual: false)
    ap = AutoPost.find_by(id: auto_post_id)
    return unless ap && ap.platform == "instagram" && (ap.enabled? || manual)
    ap.update_columns(last_run_at: Time.current, next_run_at: (Time.current + ap.interval_minutes.minutes if ap.enabled?))
    instance = ap.instance
    catalog, drama, ep, part = resolve_target(ap, instance_locale(instance))
    stream = catalog.play(ap.drama_id, ep.number) or raise AutoPost::RunError, "stream episode #{ep.number} kosong"

    sweep_stale_tmp
    Dir.mktmpdir("igpost") do |dir|
      builder = AutoPoster::VideoBuilder.new(instance, stream, dir, max_seconds: ap.max_seconds, offset_seconds: (part - 1) * ap.max_seconds)
      parts = parts_for(builder.source_duration, ap.max_seconds)
      if part > parts # durasi sumber berubah / part sebelumnya salah hitung → tutup episode ini, lanjut episode berikutnya
        ap.update_columns(last_part: parts, parts_total: parts)
        raise AutoPost::RunError, "EP #{ep.number} part #{part} melebihi durasi (#{parts} part); episode berikutnya pada jadwal berikutnya"
      end
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      video, cover, meta = builder.build
      t_render = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
      caption = AutoPoster::CaptionWriter.new(ap, drama, ep.number, part: part, parts: parts, locale: instance_locale(instance)).call
      t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = AutoPoster::InstagramClient.new(ap.cookie).post_reel(video, cover, caption, **meta.slice(:width, :height, :duration_ms))
      t_ig = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
      Rails.logger.info("[InstagramPostJob] auto_post=#{ap.id} EP #{ep.number} part #{part}/#{parts}: render #{t_render.round}s (#{File.size(video) / 1_048_576} MB, #{meta[:duration_ms] / 1000}s), instagram #{t_ig.round}s")
      ap.record!(ok: true, episode: ep.number, part: part, parts: parts, url: result.url)
      ap.update_columns(next_run_at: Time.current + PART_GAP) if ap.enabled? && part < parts
    end
  rescue AutoPoster::InstagramClient::AuthError => e
    ap&.record!(ok: false, error: "AUTH: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[InstagramPostJob] auto_post=#{auto_post_id} #{e.class}: #{e.message}")
    ap&.record!(ok: false, error: "#{e.class.name.demodulize}: #{e.message}")
  end

  private
  # Menentukan judul + episode/part berikutnya. Judul otomatis: bila belum ada judul, jatah episode judul ini habis,
  # atau episode terbuka sudah habis → TitlePicker memilih judul baru (statistik → acak terbaru), maksimal 2x ganti.
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

  # Sisa < 5 detik tidak dijadikan part sendiri.
  def parts_for(duration_s, max_s) = [ ((duration_s - 5) / max_s.to_f).ceil, 1 ].max

  # Dir.mktmpdir dengan blok sudah menghapus folder kerja (video/cover/watermark) setelah unggah, sukses maupun gagal.
  # Sisa folder hanya mungkin ada bila proses dimatikan di tengah jalan (restart service) — bersihkan yang > 2 jam.
  def sweep_stale_tmp
    Dir.glob(File.join(Dir.tmpdir, "igpost*")).each do |d|
      FileUtils.rm_rf(d) if File.directory?(d) && File.mtime(d) < 2.hours.ago
    end
  rescue StandardError => e
    Rails.logger.warn("[InstagramPostJob] sweep tmp: #{e.message}")
  end

  def instance_locale(instance) = (instance.respond_to?(:default_locale) && instance.default_locale.presence) || I18n.default_locale.to_s
end
