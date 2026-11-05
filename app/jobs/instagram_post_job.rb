require "tmpdir"

# Satu siklus auto posting Instagram untuk satu AutoPost (= satu akun): tentukan episode/part berikutnya dari judul
# yang dipilih, render video Reels (9:16 + watermark instance terbakar, dipotong sesuai max_seconds akun), buat
# caption (template TokenPlus per judul + teks tetap + hashtag), unggah dengan cookie akun. Episode yang lebih
# panjang dari max_seconds dipecah jadi Part 1..n: part berikutnya dijadwalkan PART_GAP kemudian, setelah part
# terakhir episode berikutnya mengikuti interval akun. Hasil/galat dicatat di last_status + log.
class InstagramPostJob < ApplicationJob
  include AutoPoster::TitleResolver

  queue_as :default
  discard_on ActiveJob::DeserializationError
  # Render ffmpeg berat (4 core) → satu posting dalam satu waktu untuk semua akun.
  limits_concurrency to: 1, key: "video_post", duration: 30.minutes
  PART_GAP = 3.minutes

  # manual: true (tombol "Posting sekarang") → jalan walau auto posting belum diaktifkan.
  def perform(auto_post_id, manual: false)
    ap = AutoPost.find_by(id: auto_post_id)
    return unless ap && ap.platform == "instagram" && (ap.enabled? || manual)
    ap.update_columns(last_run_at: Time.current, next_run_at: (Time.current + ap.interval_minutes.minutes if ap.enabled?))
    instance = ap.instance
    InstagramProfileSyncJob.perform_later(ap.id) if InstagramProfileSyncJob.due?(ap) # username + website bio, maks 1x/hari
    catalog, drama, ep, part = resolve_target(ap, instance_locale(instance))
    stream = catalog.play(ap.drama_id, ep.number) or raise AutoPost::RunError, "stream episode #{ep.number} kosong"

    sweep_stale_tmp("igpost")
    Dir.mktmpdir("igpost") do |dir|
      builder = AutoPoster::VideoBuilder.new(instance, stream, dir, max_seconds: ap.max_seconds, offset_seconds: (part - 1) * ap.max_seconds,
                                             remix_seed: (ap.remix? ? ap.id * 1_000_003 + ep.number : nil), bgm: ap.bgm?)
      parts = builder.parts
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
      Rails.logger.info("[InstagramPostJob] auto_post=#{ap.id} EP #{ep.number} part #{part}/#{parts}#{builder.remix? ? " remix" : ""}#{builder.bgm? ? " bgm" : ""}: render #{t_render.round}s (#{File.size(video) / 1_048_576} MB, #{meta[:duration_ms] / 1000}s), instagram #{t_ig.round}s")
      ap.record!(ok: true, episode: ep.number, part: part, parts: parts, url: result.url)
      ap.update_columns(next_run_at: Time.current + PART_GAP) if ap.enabled? && part < parts
    end
  rescue AutoPoster::InstagramClient::AuthError => e
    ap&.record_auth_failure!(e.message)
  rescue StandardError => e
    Rails.logger.error("[InstagramPostJob] auto_post=#{auto_post_id} #{e.class}: #{e.message}")
    ap&.record!(ok: false, error: "#{e.class.name.demodulize}: #{e.message}")
  end
end
