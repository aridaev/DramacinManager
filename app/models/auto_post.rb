# Satu akun Instagram untuk auto posting (satu baris = satu cookie) dengan kontennya sendiri: penyedia + judul,
# interval, batas durasi per Reel (episode lebih panjang dipecah jadi Part 1..n dengan jeda InstagramPostJob::PART_GAP,
# lalu episode berikutnya mengikuti interval), dan teks tetap yang disisipkan sebelum hashtag.
# Beberapa akun boleh memakai judul yang sama. Progres (last_episode/last_part) dan cache caption per baris.
# Judul otomatis (auto_title): tiap judul hanya episodes_per_title episode, lalu AutoPoster::TitlePicker memilih
# judul berikutnya dari Statistik pengunjung (belum pernah diposting akun ini) atau acak dari beranda penyedia.
class AutoPost < ApplicationRecord
  class RunError < StandardError; end
  LOG_MAX = 30
  PLATFORMS = %w[instagram].freeze
  MIN_INTERVAL = 5
  MAX_INTERVAL = 7 * 24 * 60
  MIN_SECONDS = 15
  MAX_SECONDS = 20 * 60
  MIN_EPISODES_PER_TITLE = 1
  MAX_EPISODES_PER_TITLE = 100
  POSTED_TITLES_MAX = 2000
  DEFAULT_FIXED_TEXT = "Tonight, @thv took a turn in the audience as he watched @gracieabrams and @dojacat perform at #VogueWorld Hollywood. No stranger to a fashion show either, the @bts.bighitofficial star dressed in a look that could have easily appeared on the runway."

  belongs_to :instance

  validates :platform, inclusion: { in: PLATFORMS }
  validates :interval_minutes, numericality: { only_integer: true, greater_than_or_equal_to: MIN_INTERVAL, less_than_or_equal_to: MAX_INTERVAL }
  validates :max_seconds, numericality: { only_integer: true, greater_than_or_equal_to: MIN_SECONDS, less_than_or_equal_to: MAX_SECONDS }
  validates :cookie, presence: true
  validates :episodes_per_title, numericality: { only_integer: true, greater_than_or_equal_to: MIN_EPISODES_PER_TITLE, less_than_or_equal_to: MAX_EPISODES_PER_TITLE }
  validate :cookie_has_session
  validate :enabled_requirements

  before_validation { self.label = self.class.account_label(cookie) if label.blank? }
  before_save :schedule_next_run
  before_save :reset_progress, if: :will_save_change_to_drama_id?

  # Input mentah boleh berupa header Cookie, JSON ekspor Cookie-Editor, atau format Netscape (dinormalisasi ke header).
  def cookie=(raw)
    super(self.class.normalize_cookie(raw))
  end

  def label=(v)
    super(v.to_s.strip.first(60).presence)
  end

  def fixed_text=(v)
    super(v.to_s.strip.first(1000).presence)
  end

  def provider = provider_slug.present? ? Provider.find_by(slug: provider_slug) : nil
  def more_parts? = last_episode.present? && last_part.to_i < parts_total.to_i
  def ready? = auto_title? || (provider_slug.present? && drama_id.present?)
  def title_key = "#{provider_slug}:#{drama_id}"
  # Jatah episode judul ini habis (dan tidak ada part yang tersisa) → TitlePicker memilih judul baru.
  def title_done? = auto_title? && drama_id.present? && title_episodes.to_i >= episodes_per_title && !more_parts?

  # Ganti judul aktif (dipanggil TitlePicker): judul lama dicatat agar tidak terulang, progres & caption di-reset.
  def start_title!(provider_slug:, drama_id:, drama_title:, source: nil)
    done = self.drama_id.present? ? [ title_key ] : []
    update_columns(provider_slug: provider_slug, drama_id: drama_id, drama_title: drama_title,
                   posted_titles: (Array(posted_titles) + done).last(POSTED_TITLES_MAX),
                   last_episode: nil, last_part: nil, parts_total: nil, title_episodes: 0,
                   caption_template: nil, caption_tags: nil, updated_at: Time.current)
    Rails.logger.info("[AutoPost] ##{id} judul baru (#{source}): #{provider_slug}/#{drama_id} #{drama_title}")
  end

  # Catat hasil satu siklus posting (log terbaru di depan, maks LOG_MAX) + status ringkas.
  def record!(ok:, episode: nil, part: nil, parts: nil, url: nil, error: nil)
    part_s = parts.to_i > 1 ? " Part #{part}/#{parts}" : ""
    entry = { "at" => Time.current.iso8601, "ok" => ok, "episode" => episode, "part" => part_s.strip.presence, "account" => label, "url" => url, "error" => error.to_s.first(300).presence }
    attrs = { log: [ entry ] + Array(log).first(LOG_MAX - 1), last_status: ok ? "ok: EP #{episode}#{part_s} → #{url || 'diunggah'}" : "gagal: #{entry['error']}" }
    if ok
      attrs.merge!(last_episode: episode, last_part: part, parts_total: parts, posts_count: posts_count + 1)
      attrs[:title_episodes] = title_episodes.to_i + 1 if part.to_i >= parts.to_i # episode selesai (semua part terunggah)
    end
    update_columns(attrs.merge(updated_at: Time.current))
  end

  # Textarea "tambah akun" boleh berisi beberapa cookie: dipisah baris kosong atau "---" (JSON = satu akun).
  def self.split_cookies(text)
    s = text.to_s.strip
    return [ s ] if s.start_with?("[", "{")
    s.split(/\n\s*(?:---+\s*)?\n|\n---+\n/).map(&:strip).reject(&:blank?)
  end

  # Header Cookie / JSON [{name,value}] / Netscape (7 kolom tab) → "a=b; c=d".
  def self.normalize_cookie(text)
    s = text.to_s.strip
    return "" if s.empty?
    pairs =
      if s.start_with?("[", "{")
        arr = JSON.parse(s)
        arr = arr["cookies"] if arr.is_a?(Hash) && arr["cookies"].is_a?(Array)
        Array(arr).filter_map { |c| c.is_a?(Hash) && c["name"].present? ? [ c["name"].to_s, c["value"].to_s ] : nil }
      elsif s.lines.any? { |l| l.split("\t").size >= 7 }
        s.lines.filter_map { |l| cols = l.chomp.split("\t"); cols.size >= 7 && !l.start_with?("#") ? [ cols[5], cols[6] ] : nil }
      else
        s.sub(/\Acookie:\s*/i, "").split(/;\s*|\r?\n/).filter_map { |kv| k, v = kv.split("=", 2); k.present? && v ? [ k.strip, v.strip ] : nil }
      end
    pairs.uniq { |k, _| k }.map { |k, v| "#{k}=#{v}" }.join("; ")
  rescue JSON::ParserError
    s.gsub(/\s+/, " ")
  end

  def self.cookie_value(cookie, name) = cookie.to_s[/(?:\A|;\s*)#{Regexp.escape(name)}=([^;]*)/, 1]
  def self.account_label(cookie) = (id = cookie_value(cookie, "ds_user_id")).present? ? "IG ##{id}" : "Akun"

  private
  def enabled_requirements
    errors.add(:base, I18n.t("admin.auto_post.drama_required")) if enabled? && !ready?
  end

  def cookie_has_session
    errors.add(:base, I18n.t("admin.auto_post.cookie_invalid")) if cookie.present? && self.class.cookie_value(cookie, "sessionid").blank?
  end

  def reset_progress
    self.last_episode = self.last_part = self.parts_total = nil
    self.title_episodes = 0
    self.caption_template = self.caption_tags = nil
  end

  def schedule_next_run
    self.next_run_at = enabled? ? (next_run_at.presence || Time.current + interval_minutes.minutes) : nil
    self.next_run_at = Time.current + interval_minutes.minutes if enabled? && will_save_change_to_interval_minutes?
  end
end
