require "tmpdir"

# Satu siklus auto posting Telegram untuk satu TelegramTarget (grup/channel): sama dengan InstagramPostJob sampai
# video jadi (judul/episode/part, render 9:16 + watermark, caption), lalu video diunggah lewat sidecar MTProto dengan
# session akun Telegram instance. Render dibatasi satu dalam satu waktu bersama job Instagram (key "video_post").
class TelegramPostJob < ApplicationJob
  include AutoPoster::TitleResolver

  queue_as :default
  discard_on ActiveJob::DeserializationError
  limits_concurrency to: 1, key: "video_post", duration: 30.minutes
  CAPTION_MAX = 1024 # batas caption Telegram (akun non-Premium)

  def perform(target_id, manual: false)
    t = TelegramTarget.find_by(id: target_id)
    return unless t && (t.enabled? || manual)
    account = t.telegram_account
    t.update_columns(last_run_at: Time.current, next_run_at: (Time.current + t.interval_minutes.minutes if t.enabled?))
    raise AutoPost::RunError, I18n.t("admin.telegram.need_login") unless account.logged_in?
    instance = account.instance
    catalog, drama, ep, part = resolve_target(t, instance_locale(instance))
    stream = catalog.play(t.drama_id, ep.number) or raise AutoPost::RunError, "stream episode #{ep.number} kosong"

    sweep_stale_tmp("tgpost")
    Dir.mktmpdir("tgpost") do |dir|
      builder = AutoPoster::VideoBuilder.new(instance, stream, dir, max_seconds: t.max_seconds, offset_seconds: (part - 1) * t.max_seconds,
                                             remix_seed: (t.remix? ? t.id * 1_000_003 + ep.number : nil), bgm: t.bgm?)
      parts = builder.parts
      if part > parts
        t.update_columns(last_part: parts, parts_total: parts)
        raise AutoPost::RunError, "EP #{ep.number} part #{part} melebihi durasi (#{parts} part); episode berikutnya pada jadwal berikutnya"
      end
      clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      t0 = clock.call
      video, cover, meta = builder.build
      t_render = clock.call - t0
      caption = AutoPoster::CaptionWriter.new(t, drama, ep.number, part: part, parts: parts, locale: instance_locale(instance), max_len: CAPTION_MAX).call
      t0 = clock.call
      result = TelegramClient.from_settings.send_video(account.session, peer: t.peer, video: video, cover: cover, caption: caption, **meta.slice(:width, :height, :duration_ms))
      t_tg = clock.call - t0
      account.refresh_session!(result["session"])
      Rails.logger.info("[TelegramPostJob] target=#{t.id} #{t.display_title} EP #{ep.number} part #{part}/#{parts}: render #{t_render.round}s (#{File.size(video) / 1_048_576} MB), telegram #{t_tg.round}s")
      t.record!(ok: true, episode: ep.number, part: part, parts: parts, url: result["link"])
      t.update_columns(next_run_at: Time.current + InstagramPostJob::PART_GAP) if t.enabled? && part < parts
    end
  rescue TelegramClient::AuthError => e
    t&.record!(ok: false, error: "AUTH: #{e.message}")
    account&.mark_auth_failed!(e.message)
  rescue TelegramClient::FloodWait => e
    t&.record!(ok: false, error: e.message)
    t&.update_columns(next_run_at: Time.current + e.seconds.seconds + 30.seconds) if t&.enabled?
  rescue TelegramClient::Forbidden => e
    t&.record_forbidden!(e.message)
  rescue StandardError => e
    Rails.logger.error("[TelegramPostJob] target=#{target_id} #{e.class}: #{e.message}")
    t&.record!(ok: false, error: "#{e.class.name.demodulize}: #{e.message}")
  end
end
