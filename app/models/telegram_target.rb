# Satu tujuan posting (grup/channel) milik akun Telegram sebuah instance, dengan jadwal dan konten sendiri.
# Antarmukanya sengaja sama dengan AutoPost (posted_titles, start_title!, genre_list, caption_template, ...)
# sehingga AutoPoster::TitlePicker, AutoPoster::CaptionWriter, dan AutoPoster::TitleResolver bisa dipakai bersama.
class TelegramTarget < ApplicationRecord
  LOG_MAX = 30
  MIN_INTERVAL = 10 # menit; lebih rapat berisiko FloodWait/pembatasan akun
  MAX_INTERVAL = 7 * 24 * 60
  MIN_SECONDS = 15
  MAX_SECONDS = 20 * 60
  MIN_EPISODES_PER_TITLE = 1
  MAX_EPISODES_PER_TITLE = 100
  POSTED_TITLES_MAX = 2000
  ERRORS_TO_DISABLE = 3 # ditolak Telegram (tidak boleh posting) berturut-turut sebanyak ini → target dinonaktifkan
  TARGET_GAP = 2.minutes # jeda minimum antar posting dari akun yang sama
  DEFAULT_FIXED_TEXT = AutoPost::DEFAULT_FIXED_TEXT

  PROMO_MIN_INTERVAL = 60 # menit; promosi lebih jarang dari video agar tidak dianggap spam
  PROMO_MAX_INTERVAL = 7 * 24 * 60

  belongs_to :telegram_account
  has_many :promos, class_name: "TelegramPromo", dependent: :destroy

  validates :promo_interval_minutes, numericality: { only_integer: true, greater_than_or_equal_to: PROMO_MIN_INTERVAL, less_than_or_equal_to: PROMO_MAX_INTERVAL }
  validate :promo_requirements
  validates :interval_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_INTERVAL, less_than_or_equal_to: MAX_INTERVAL }
  validates :max_seconds, numericality: { only_integer: true, greater_than_or_equal_to: MIN_SECONDS, less_than_or_equal_to: MAX_SECONDS }
  validates :episodes_per_title, numericality: { only_integer: true, greater_than_or_equal_to: MIN_EPISODES_PER_TITLE, less_than_or_equal_to: MAX_EPISODES_PER_TITLE }
  validate :enabled_requirements

  before_save :schedule_next_run
  before_save :schedule_promo_next_run

  delegate :instance, :instance_id, to: :telegram_account

  def label = display_title
  def topic? = topic_id.to_i.positive?
  # "Grup › Topic" untuk grup forum; judul biasa untuk lainnya.
  def display_title = topic? ? "#{title} › #{topic_title.presence || "Topic ##{topic_id}"}" : title
  def fixed_text=(v)
    super(v.to_s.strip.first(1000).presence)
  end

  def genres=(v)
    super(v.to_s.split(/[,\n;]+/).map(&:strip).reject(&:blank?).uniq(&:downcase).first(10).join(", ").presence)
  end

  def genre_list = genres.to_s.split(",").map(&:strip).reject(&:blank?)
  def provider = provider_slug.present? ? Provider.find_by(slug: provider_slug) : nil
  def more_parts? = last_episode.present? && last_part.to_i < parts_total.to_i
  def ready? = can_post?
  def title_key = "#{provider_slug}:#{drama_id}"
  def title_done? = auto_title? && drama_id.present? && title_episodes.to_i >= episodes_per_title && !more_parts?

  def peer = { peer_kind: peer_kind, peer_id: peer_id, access_hash: access_hash, username: username, topic_id: topic_id.to_i }

  def status_kind
    s = last_status.to_s
    s.start_with?("ok") ? :ok : (s.start_with?("gagal") ? :failed : (s.present? ? :queued : nil))
  end

  # Judul yang sudah diposting target lain di akun yang sama (rotasi antar tujuan).
  def sibling_title_keys
    TelegramTarget.where(telegram_account_id: telegram_account_id).where.not(id: id).pluck(:posted_titles, :provider_slug, :drama_id).flat_map do |titles, slug, did|
      Array(titles).map(&:to_s) + (did.present? ? [ "#{slug}:#{did}" ] : [])
    end
  end

  def start_title!(provider_slug:, drama_id:, drama_title:, source: nil)
    done = self.drama_id.present? ? [ title_key ] : []
    update_columns(provider_slug: provider_slug, drama_id: drama_id, drama_title: drama_title,
                   posted_titles: (Array(posted_titles) + done).last(POSTED_TITLES_MAX),
                   last_episode: nil, last_part: nil, parts_total: nil, title_episodes: 0,
                   caption_template: nil, caption_tags: nil, updated_at: Time.current)
    Rails.logger.info("[TelegramTarget] ##{id} judul baru (#{source}): #{provider_slug}/#{drama_id} #{drama_title}")
  end

  def record!(ok:, episode: nil, part: nil, parts: nil, url: nil, error: nil)
    part_s = parts.to_i > 1 ? " Part #{part}/#{parts}" : ""
    entry = { "at" => Time.current.iso8601, "ok" => ok, "episode" => episode, "part" => part_s.strip.presence, "account" => label, "url" => url, "error" => error.to_s.first(300).presence }
    attrs = { log: [ entry ] + Array(log).first(LOG_MAX - 1), last_status: ok ? "ok: EP #{episode}#{part_s} → #{url || 'terkirim'}" : "gagal: #{entry['error']}" }
    if ok
      attrs.merge!(last_episode: episode, last_part: part, parts_total: parts, posts_count: posts_count + 1, error_streak: 0)
      attrs[:title_episodes] = title_episodes.to_i + 1 if part.to_i >= parts.to_i
    end
    update_columns(attrs.merge(updated_at: Time.current))
  end

  # Promo berikutnya (rotasi berurutan antar promo aktif, berdasarkan id): setelah promo_cursor, lalu kembali ke awal.
  def next_promo
    list = promos.active.order(:id).to_a
    list.find { |p| p.id > promo_cursor.to_i } || list.first
  end

  def promo_status_kind
    s = promo_last_status.to_s
    s.start_with?("ok") ? :ok : (s.start_with?("gagal") ? :failed : (s.present? ? :queued : nil))
  end

  def record_promo!(ok:, promo: nil, url: nil, error: nil)
    entry = { "at" => Time.current.iso8601, "ok" => ok, "episode" => "promo", "part" => promo ? "##{promo.id}" : nil, "account" => label, "url" => url, "error" => error.to_s.first(300).presence }
    attrs = { log: [ entry ] + Array(log).first(LOG_MAX - 1), promo_cursor: promo&.id || promo_cursor,
              promo_last_status: ok ? "ok: promo → #{url || 'terkirim'}" : "gagal: #{entry['error']}" }
    attrs.merge!(promo_posts_count: promo_posts_count + 1, promo_error_streak: 0) if ok
    update_columns(attrs.merge(updated_at: Time.current))
  end

  # Ditolak Telegram saat kirim promo: setelah ERRORS_TO_DISABLE kali berturut-turut → promosi target dinonaktifkan.
  def record_promo_forbidden!(message, promo: nil)
    record_promo!(ok: false, promo: promo, error: message)
    streak = promo_error_streak.to_i + 1
    attrs = { promo_error_streak: streak, updated_at: Time.current }
    attrs.merge!(promo_enabled: false, promo_next_run_at: nil, promo_last_status: "gagal: #{message.to_s.first(160)} (promosi dinonaktifkan)") if streak >= ERRORS_TO_DISABLE
    update_columns(attrs)
  end

  # Ditolak Telegram (bukan admin channel, dibisukan, dll.): setelah ERRORS_TO_DISABLE kali berturut-turut → nonaktif.
  def record_forbidden!(message)
    record!(ok: false, error: message)
    streak = error_streak.to_i + 1
    attrs = { error_streak: streak, updated_at: Time.current }
    attrs.merge!(enabled: false, next_run_at: nil, last_status: "gagal: #{message.to_s.first(160)} (dinonaktifkan)") if streak >= ERRORS_TO_DISABLE
    update_columns(attrs)
  end

  private
  def enabled_requirements
    errors.add(:base, I18n.t("admin.telegram.need_login")) if enabled? && !telegram_account&.logged_in?
    errors.add(:base, I18n.t("admin.telegram.cannot_post", title: display_title)) if enabled? && !can_post?
  end

  def promo_requirements
    return unless promo_enabled?
    errors.add(:base, I18n.t("admin.telegram.need_login")) unless telegram_account&.logged_in?
    errors.add(:base, I18n.t("admin.telegram.cannot_post", title: display_title)) unless can_post?
    errors.add(:base, I18n.t("admin.telegram.promo.need_active", title: display_title)) if persisted? && !promos.active.exists?
  end

  def schedule_promo_next_run
    self.promo_next_run_at = promo_enabled? ? (promo_next_run_at.presence || Time.current + promo_interval_minutes.minutes) : nil
    self.promo_next_run_at = Time.current + promo_interval_minutes.minutes if promo_enabled? && will_save_change_to_promo_interval_minutes?
  end

  def schedule_next_run
    self.next_run_at = enabled? ? (next_run_at.presence || Time.current + interval_minutes.minutes) : nil
    self.next_run_at = Time.current + interval_minutes.minutes if enabled? && will_save_change_to_interval_minutes?
  end
end
